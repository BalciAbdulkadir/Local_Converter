import 'dart:io';

import 'package:path/path.dart' as p;

import 'formats.dart';
import 'tools.dart';

/// Video kalitesi ön ayarları (FFmpeg CRF değerlerine eşlenir).
enum VideoQuality {
  high('Yüksek'),
  medium('Orta'),
  low('Düşük (küçük dosya)');

  const VideoQuality(this.label);
  final String label;
}

/// PDF sayfa boyutu seçenekleri.
enum PdfPageSize {
  a4('A4'),
  letter('Letter'),
  fit('Görsele uydur');

  const PdfPageSize(this.label);
  final String label;
}

/// Kullanıcının seçebildiği tüm dönüşüm ayarları.
/// Every conversion setting the user can choose.
class ConversionOptions {
  const ConversionOptions({
    this.imageQuality = 90,
    this.maxWidth,
    this.maxHeight,
    this.pdfPageSize = PdfPageSize.a4,
    this.mergeIntoSinglePdf = false,
    this.pdfRenderDpi = 150,
    this.audioBitrateKbps = 192,
    this.videoQuality = VideoQuality.medium,
    this.videoMaxHeight,
    this.gifFps = 12,
    this.csvSemicolon = false,
    this.outputDirectory,
  });

  /// JPG / WEBP / AVIF kalitesi (1-100).
  final int imageQuality;

  /// Görsel boyutlandırma sınırları (en-boy oranı korunur). null = sınır yok.
  final int? maxWidth;
  final int? maxHeight;

  final PdfPageSize pdfPageSize;
  final bool mergeIntoSinglePdf;

  /// PDF sayfaları görsele çevrilirken kullanılan çözünürlük.
  final int pdfRenderDpi;

  final int audioBitrateKbps;
  final VideoQuality videoQuality;
  final int? videoMaxHeight;
  final int gifFps;

  /// CSV çıktısında virgül yerine noktalı virgül (Türkçe Excel için).
  final bool csvSemicolon;

  /// null ise çıktı kaynak dosyanın yanına yazılır.
  final String? outputDirectory;

  ConversionOptions copyWith({
    int? imageQuality,
    int? Function()? maxWidth,
    int? Function()? maxHeight,
    PdfPageSize? pdfPageSize,
    bool? mergeIntoSinglePdf,
    int? pdfRenderDpi,
    int? audioBitrateKbps,
    VideoQuality? videoQuality,
    int? Function()? videoMaxHeight,
    int? gifFps,
    bool? csvSemicolon,
    String? Function()? outputDirectory,
  }) {
    return ConversionOptions(
      imageQuality: imageQuality ?? this.imageQuality,
      maxWidth: maxWidth != null ? maxWidth() : this.maxWidth,
      maxHeight: maxHeight != null ? maxHeight() : this.maxHeight,
      pdfPageSize: pdfPageSize ?? this.pdfPageSize,
      mergeIntoSinglePdf: mergeIntoSinglePdf ?? this.mergeIntoSinglePdf,
      pdfRenderDpi: pdfRenderDpi ?? this.pdfRenderDpi,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      videoQuality: videoQuality ?? this.videoQuality,
      videoMaxHeight: videoMaxHeight != null ? videoMaxHeight() : this.videoMaxHeight,
      gifFps: gifFps ?? this.gifFps,
      csvSemicolon: csvSemicolon ?? this.csvSemicolon,
      outputDirectory: outputDirectory != null ? outputDirectory() : this.outputDirectory,
    );
  }
}

/// Kullanıcı iptal ettiğinde fırlatılır.
class ConversionCancelled implements Exception {
  const ConversionCancelled();
  @override
  String toString() => 'İptal edildi';
}

/// Kullanıcıya gösterilecek anlaşılır hata.
class ConversionException implements Exception {
  const ConversionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uzun süren işlemleri (ör. FFmpeg) durdurmak için iptal belirteci.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void throwIfCancelled() {
    if (_cancelled) throw const ConversionCancelled();
  }
}

/// Bir dönüştürücünün çalışırken ihtiyaç duyduğu her şey.
class ConversionContext {
  ConversionContext({
    required this.options,
    required this.tools,
    required this.cancelToken,
    required this.onProgress,
  });

  final ConversionOptions options;
  final ExternalTools tools;
  final CancelToken cancelToken;

  /// Mevcut dosyanın ilerlemesi (0.0 - 1.0).
  final void Function(double progress) onProgress;
}

/// Tek bir dönüşüm isteği: hangi dosya(lar), hangi hedef, nereye.
class ConversionRequest {
  ConversionRequest({
    required this.inputs,
    required this.target,
    required this.outputBasePath,
  });

  /// Genelde tek dosya; birleştirme işlemlerinde birden fazla.
  final List<String> inputs;
  final FileFormat target;

  /// Uzantısız çıktı yolu (ör. C:\klasör\resim). Dönüştürücü uzantıyı ekler.
  final String outputBasePath;

  String get input => inputs.first;
  FileFormat get inputFormat => Formats.fromPath(input)!;

  /// Tek çıktı üreten dönüştürücüler için çakışmayan dosya yolu.
  String primaryOutputPath() => uniquePath('$outputBasePath.${target.extension}');

  /// Çok çıktı üreten dönüştürücüler için (ör. PDF sayfaları) numaralı yol.
  String numberedOutputPath(int index, int total, {String? extension}) {
    final digits = total.toString().length.clamp(2, 6);
    final n = index.toString().padLeft(digits, '0');
    return uniquePath('${outputBasePath}_$n.${extension ?? target.extension}');
  }
}

/// Bu oturumda başka bir iş için ayrılmış çıktı yolları. Paralel işlerde iki
/// dosyanın (ör. a.png ve a.jpg → a.webp) aynı adı almasını önler.
final Set<String> _reservedPaths = {};

bool _isTaken(String path) =>
    _reservedPaths.contains(p.normalize(path).toLowerCase()) ||
    File(path).existsSync() ||
    Directory(path).existsSync();

/// Dosya varsa "ad (1).ext", "ad (2).ext"... şeklinde boş bir ad bulur ve ayırır.
String uniquePath(String path) {
  var candidate = path;
  if (_isTaken(candidate)) {
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    for (var i = 1;; i++) {
      candidate = p.join(dir, '$base ($i)$ext');
      if (!_isTaken(candidate)) break;
    }
  }
  _reservedPaths.add(p.normalize(candidate).toLowerCase());
  return candidate;
}

/// Tüm dönüştürücülerin uyguladığı arayüz.
/// Interface implemented by every converter.
abstract class Converter {
  /// Bu dönüştürücünün okuyabildiği formatlar.
  Set<FileFormat> get inputFormats;

  /// [input] formatı için üretilebilecek hedef formatlar.
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools);

  bool supports(FileFormat input, FileFormat output, ExternalTools tools) =>
      inputFormats.contains(input) && outputFormatsFor(input, tools).contains(output);

  /// Dönüşümü yapar ve oluşturulan dosyaların yollarını döner.
  Future<List<String>> convert(ConversionRequest request, ConversionContext context);
}
