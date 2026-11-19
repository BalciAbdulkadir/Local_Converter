import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/conversion.dart';
import '../core/conversion_service.dart';
import '../core/converter_registry.dart';
import '../core/formats.dart';
import '../core/tools.dart';

/// Listeye eklenmiş tek bir dosya ve dönüşüm durumu.
class FileEntry {
  FileEntry(this.path, this.format, this.size);

  final String path;
  final FileFormat format;
  final int size;

  JobStatus? status;
  double progress = 0;
  List<String> outputs = const [];
  String? error;

  String get name => p.basename(path);

  void reset() {
    status = null;
    progress = 0;
    outputs = const [];
    error = null;
  }
}

/// Dosya ekleme sonucunun özeti (kullanıcıya bildirim için).
class AddResult {
  const AddResult({this.added = 0, this.unsupported = const [], this.duplicates = 0});
  final int added;
  final List<String> unsupported;
  final int duplicates;
}

/// Ekranın tüm durumunu tutar: dosyalar, hedef format, ayarlar, ilerleme.
/// Holds all screen state: files, target format, options, progress.
class ConverterController extends ChangeNotifier {
  ConverterController({
    ConversionService? service,
    Future<ExternalTools> Function()? detectTools,
  })  : service = service ?? ConversionService(),
        _detectTools = detectTools ?? ExternalTools.detect;

  final ConversionService service;
  final Future<ExternalTools> Function() _detectTools;

  ConverterRegistry get registry => service.registry;

  final List<FileEntry> files = [];
  ExternalTools tools = const ExternalTools();
  bool toolsLoaded = false;

  FileFormat? _target;
  FileFormat? get target => _target;

  ConversionOptions _options = const ConversionOptions();
  ConversionOptions get options => _options;

  bool _running = false;
  bool get isRunning => _running;
  CancelToken? _cancelToken;

  static const _maxFolderFiles = 5000;

  Future<void> init() async {
    tools = await _detectTools();
    toolsLoaded = true;
    _ensureValidTarget();
    notifyListeners();
  }

  // --- Dosyalar ---

  /// Dosya ve klasör yollarını ekler; klasörler alt klasörleriyle taranır.
  AddResult addPaths(Iterable<String> paths) {
    if (_running) return const AddResult();
    final existing = {for (final f in files) p.normalize(f.path).toLowerCase()};
    var added = 0;
    var duplicates = 0;
    final unsupported = <String>[];

    void addFile(String path, {bool fromFolder = false}) {
      final format = Formats.fromPath(path);
      if (format == null || !registry.isKnownInput(format)) {
        // Klasör taramasında tanınmayan dosyaları sessizce atla.
        if (!fromFolder) unsupported.add(p.basename(path));
        return;
      }
      final key = p.normalize(path).toLowerCase();
      if (!existing.add(key)) {
        duplicates++;
        return;
      }
      int size = 0;
      try {
        size = File(path).lengthSync();
      } catch (_) {}
      files.add(FileEntry(path, format, size));
      added++;
    }

    for (final path in paths) {
      if (FileSystemEntity.isDirectorySync(path)) {
        var count = 0;
        try {
          for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
            if (e is File) {
              addFile(e.path, fromFolder: true);
              if (++count >= _maxFolderFiles) break;
            }
          }
        } catch (_) {
          // Erişilemeyen alt klasörler atlanır.
        }
      } else {
        addFile(path);
      }
    }

    // Önceki dönüşümün sonuçlarını temizle; yeni bir seçim başlıyor.
    if (added > 0) {
      for (final f in files) {
        if (f.status != null && f.status != JobStatus.done) f.reset();
      }
    }
    _ensureValidTarget();
    notifyListeners();
    return AddResult(added: added, unsupported: unsupported, duplicates: duplicates);
  }

  void removeAt(int index) {
    if (_running) return;
    files.removeAt(index);
    _ensureValidTarget();
    notifyListeners();
  }

  void clear() {
    if (_running) return;
    files.clear();
    _ensureValidTarget();
    notifyListeners();
  }

  /// Başarıyla dönüştürülmüş dosyaları listeden çıkarır.
  void clearCompleted() {
    if (_running) return;
    files.removeWhere((f) => f.status == JobStatus.done);
    _ensureValidTarget();
    notifyListeners();
  }

  // --- Hedef ve ayarlar ---

  List<FileFormat> get availableTargets => registry.commonOutputs(files.map((f) => f.format), tools);

  Set<FormatCategory> get inputCategories => {for (final f in files) f.format.category};
  Set<FileFormat> get inputFormats => {for (final f in files) f.format};

  bool get canMerge => _target == Formats.pdf && registry.canMergeToPdf(files.map((f) => f.format).toList(), tools);

  bool get willMerge => canMerge && _options.mergeIntoSinglePdf;

  /// Seçili dosyalardan herhangi biri FFmpeg gerektiriyor ama FFmpeg yoksa.
  bool get missingFfmpeg =>
      toolsLoaded &&
      !tools.hasFfmpeg &&
      files.any((f) =>
          f.format.category == FormatCategory.audio ||
          f.format.category == FormatCategory.video ||
          f.format == Formats.avif ||
          f.format == Formats.heic);

  void setTarget(FileFormat? format) {
    if (_running) return;
    _target = format;
    notifyListeners();
  }

  void updateOptions(ConversionOptions options) {
    if (_running) return;
    _options = options;
    notifyListeners();
  }

  void _ensureValidTarget() {
    final targets = availableTargets;
    if (_target != null && !targets.contains(_target)) _target = null;
    // Tek bir hedef mümkünse otomatik seç.
    if (_target == null && targets.length == 1) _target = targets.first;
  }

  // --- Dönüşüm ---

  bool get canStart => !_running && files.isNotEmpty && _target != null;

  int get doneCount => files.where((f) => f.status == JobStatus.done).length;
  int get failedCount => files.where((f) => f.status == JobStatus.failed).length;
  int get cancelledCount => files.where((f) => f.status == JobStatus.cancelled).length;
  bool get hasResults => files.any((f) => f.status != null && f.status != JobStatus.running && f.status != JobStatus.pending);

  double get overallProgress {
    if (files.isEmpty) return 0;
    final sum = files.fold<double>(0, (s, f) {
      if (f.status == JobStatus.done || f.status == JobStatus.failed || f.status == JobStatus.cancelled) return s + 1;
      return s + f.progress;
    });
    return sum / files.length;
  }

  /// Tüm çıktı dosyaları (benzersiz).
  List<String> get allOutputs => {for (final f in files) ...f.outputs}.toList();

  Future<void> start() async {
    if (!canStart) return;
    final target = _target!;
    _running = true;
    final token = _cancelToken = CancelToken();
    for (final f in files) {
      f.reset();
      f.status = JobStatus.pending;
    }
    notifyListeners();

    final snapshot = List<FileEntry>.of(files);
    try {
      await service.runBatch(
        inputs: [for (final f in snapshot) f.path],
        target: target,
        options: _options,
        tools: tools,
        cancelToken: token,
        onUpdate: (i, u) {
          final f = snapshot[i];
          f.status = u.status;
          f.progress = u.progress;
          if (u.outputs.isNotEmpty) f.outputs = u.outputs;
          f.error = u.error;
          notifyListeners();
        },
      );
    } finally {
      _running = false;
      _cancelToken = null;
      notifyListeners();
    }
  }

  void cancel() => _cancelToken?.cancel();
}
