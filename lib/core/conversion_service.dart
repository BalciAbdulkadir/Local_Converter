import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'conversion.dart';
import 'converter_registry.dart';
import 'converters/pdf_converter.dart';
import 'formats.dart';
import 'tools.dart';

enum JobStatus { pending, running, done, failed, cancelled }

/// Bir dosyanın dönüşüm durumundaki değişiklik.
class JobUpdate {
  const JobUpdate(this.status, {this.progress = 0, this.outputs = const [], this.error});
  final JobStatus status;
  final double progress;
  final List<String> outputs;
  final String? error;
}

/// Toplu dönüşümleri yürütür: dönüştürücü seçimi, çıktı adları, eşzamanlılık, iptal.
/// Runs batch conversions: converter selection, output naming, concurrency, cancellation.
class ConversionService {
  ConversionService({ConverterRegistry? registry}) : registry = registry ?? ConverterRegistry();

  final ConverterRegistry registry;

  Future<void> runBatch({
    required List<String> inputs,
    required FileFormat target,
    required ConversionOptions options,
    required ExternalTools tools,
    required CancelToken cancelToken,
    required void Function(int index, JobUpdate update) onUpdate,
  }) async {
    if (inputs.isEmpty) return;

    if (target == Formats.pdf && options.mergeIntoSinglePdf && inputs.length > 1) {
      await _runMerge(inputs, options, tools, cancelToken, onUpdate);
      return;
    }

    // Ses/video zaten çok çekirdek kullanır; diğerleri paralel işlenir.
    final heavy = inputs.any((i) => const {FormatCategory.audio, FormatCategory.video}
        .contains(Formats.fromPath(i)?.category));
    final concurrency = heavy ? 1 : math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= inputs.length) return;
        if (cancelToken.isCancelled) {
          onUpdate(index, const JobUpdate(JobStatus.cancelled));
          continue;
        }
        await _runOne(index, inputs[index], target, options, tools, cancelToken, onUpdate);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }

  Future<void> _runOne(
    int index,
    String input,
    FileFormat target,
    ConversionOptions options,
    ExternalTools tools,
    CancelToken cancelToken,
    void Function(int, JobUpdate) onUpdate,
  ) async {
    onUpdate(index, const JobUpdate(JobStatus.running));
    try {
      final format = Formats.fromPath(input);
      if (format == null) throw const ConversionException('Tanınmayan dosya türü.');
      if (!await File(input).exists()) throw const ConversionException('Dosya bulunamadı.');
      final converter = registry.find(format, target, tools);
      if (converter == null) {
        throw ConversionException('${format.id} → ${target.id} dönüşümü desteklenmiyor.');
      }

      final outDir = options.outputDirectory ?? p.dirname(input);
      await Directory(outDir).create(recursive: true);
      final request = ConversionRequest(
        inputs: [input],
        target: target,
        outputBasePath: p.join(outDir, p.basenameWithoutExtension(input)),
      );
      final context = ConversionContext(
        options: options,
        tools: tools,
        cancelToken: cancelToken,
        onProgress: (v) => onUpdate(index, JobUpdate(JobStatus.running, progress: v)),
      );
      final outputs = await converter.convert(request, context);
      onUpdate(index, JobUpdate(JobStatus.done, progress: 1, outputs: outputs));
    } on ConversionCancelled {
      onUpdate(index, const JobUpdate(JobStatus.cancelled));
    } catch (e) {
      onUpdate(index, JobUpdate(JobStatus.failed, error: describeError(e)));
    }
  }

  Future<void> _runMerge(
    List<String> inputs,
    ConversionOptions options,
    ExternalTools tools,
    CancelToken cancelToken,
    void Function(int, JobUpdate) onUpdate,
  ) async {
    void all(JobUpdate u) {
      for (var i = 0; i < inputs.length; i++) {
        onUpdate(i, u);
      }
    }

    all(const JobUpdate(JobStatus.running));
    try {
      final first = inputs.first;
      final outDir = options.outputDirectory ?? p.dirname(first);
      await Directory(outDir).create(recursive: true);
      final out = uniquePath(p.join(outDir, '${p.basenameWithoutExtension(first)}_birlesik.pdf'));
      final context = ConversionContext(
        options: options,
        tools: tools,
        cancelToken: cancelToken,
        onProgress: (v) => all(JobUpdate(JobStatus.running, progress: v)),
      );
      await PdfMerger.merge(inputs, out, context);
      all(JobUpdate(JobStatus.done, progress: 1, outputs: [out]));
    } on ConversionCancelled {
      all(const JobUpdate(JobStatus.cancelled));
    } catch (e) {
      all(JobUpdate(JobStatus.failed, error: describeError(e)));
    }
  }
}

/// Hataları kullanıcıya gösterilecek kısa metne çevirir.
String describeError(Object e) {
  if (e is ConversionException) return e.message;
  if (e is FileSystemException) {
    final reason = e.osError?.message ?? e.message;
    return 'Dosya hatası: $reason${e.path != null ? ' (${p.basename(e.path!)})' : ''}';
  }
  if (e is OutOfMemoryError) return 'Bellek yetersiz; dosya çok büyük olabilir.';
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
