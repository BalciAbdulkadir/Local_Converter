import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' as rx;

import '../conversion.dart';
import '../document/doc_model.dart';
import '../document/doc_readers.dart';
import '../formats.dart';
import '../tools.dart';
import 'document_converter.dart';
import 'image_converter.dart';
import 'pdf_writer.dart';

bool _pdfEngineReady = false;

/// PDFium motorunu başlatan fonksiyon. Testlerde Flutter eklentileri olmadığı
/// için saf Dart sürümü (`rx.pdfrxInitialize`) ile değiştirilebilir.
@visibleForTesting
Future<void> Function() pdfEngineInitializer = rx.pdfrxFlutterInitialize;

/// PDFium motorunu (pdfrx) bir kez başlatır.
Future<void> ensurePdfEngine() async {
  if (_pdfEngineReady) return;
  await pdfEngineInitializer();
  _pdfEngineReady = true;
}

Future<rx.PdfDocument> _open(String path) async {
  await ensurePdfEngine();
  try {
    return await rx.PdfDocument.openFile(path, passwordProvider: () => null);
  } on rx.PdfPasswordException {
    throw ConversionException('${p.basename(path)} parola korumalı; açılamadı.');
  } catch (e) {
    throw ConversionException('${p.basename(path)} PDF olarak açılamadı: $e');
  }
}

/// PDF → görsel (her sayfa ayrı dosya), PDF → metin belgeleri ve PDF → sayfalara bölme.
class PdfConverter extends Converter {
  @override
  Set<FileFormat> get inputFormats => {Formats.pdf};

  @override
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools) => {
        ...ImageConverter.nativeOutputs,
        if (tools.hasCwebp || tools.hasFfmpeg) Formats.webp,
        if (tools.hasFfmpeg) Formats.avif,
        Formats.txt,
        Formats.md,
        Formats.html,
        Formats.docx,
        // PDF → PDF: her sayfayı ayrı bir PDF dosyasına böler.
        Formats.pdf,
      };

  @override
  Future<List<String>> convert(ConversionRequest request, ConversionContext context) async {
    final target = request.target;
    final document = await _open(request.input);
    try {
      final pages = document.pages;
      if (pages.isEmpty) throw const ConversionException('PDF\'te sayfa yok.');

      if (target.category == FormatCategory.image) {
        return await _toImages(document, request, context);
      }
      if (target == Formats.pdf) {
        return await _split(document, request, context);
      }
      return [await _toDocument(document, request, context)];
    } finally {
      await document.dispose();
    }
  }

  Future<List<String>> _toImages(rx.PdfDocument document, ConversionRequest request, ConversionContext context) async {
    final target = request.target;
    final options = context.options;
    final pages = document.pages;
    final outputs = <String>[];
    final scale = options.pdfRenderDpi / 72;

    for (var i = 0; i < pages.length; i++) {
      context.cancelToken.throwIfCancelled();
      final page = pages[i];
      final rendered = await page.render(
        width: (page.width * scale).round(),
        height: (page.height * scale).round(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) throw ConversionException('${i + 1}. sayfa işlenemedi.');
      final image = rendered.createImageNF();
      rendered.dispose();

      final spec = ImageEncodeSpec(
        format: ImageConverter.nativeOutputs.contains(target) ? target.id : 'PNG',
        quality: options.imageQuality,
        maxWidth: options.maxWidth,
        maxHeight: options.maxHeight,
      );
      final encoded = await Isolate.run(() => encodeImage(image, spec));
      final out = pages.length == 1 ? request.primaryOutputPath() : request.numberedOutputPath(i + 1, pages.length);
      if (ImageConverter.nativeOutputs.contains(target)) {
        await File(out).writeAsBytes(encoded);
      } else {
        await ImageConverter.encodeWithExternalTool(encoded, out, target, context);
      }
      outputs.add(out);
      context.onProgress((i + 1) / pages.length);
    }
    return outputs;
  }

  Future<List<String>> _split(rx.PdfDocument document, ConversionRequest request, ConversionContext context) async {
    final pages = document.pages;
    final outputs = <String>[];
    for (var i = 0; i < pages.length; i++) {
      context.cancelToken.throwIfCancelled();
      final single = await rx.PdfDocument.createNew(sourceName: 'page_${i + 1}.pdf');
      try {
        single.pages = [pages[i]];
        final out = request.numberedOutputPath(i + 1, pages.length);
        await File(out).writeAsBytes(await single.encodePdf());
        outputs.add(out);
      } finally {
        await single.dispose();
      }
      context.onProgress((i + 1) / pages.length);
    }
    return outputs;
  }

  Future<String> _toDocument(rx.PdfDocument document, ConversionRequest request, ConversionContext context) async {
    final blocks = <Block>[];
    final pages = document.pages;
    for (var i = 0; i < pages.length; i++) {
      context.cancelToken.throwIfCancelled();
      final text = await pages[i].loadText();
      if (text != null) blocks.addAll(readTxt(text.fullText).blocks);
      context.onProgress((i + 1) / pages.length * 0.8);
    }
    if (blocks.isEmpty) {
      throw const ConversionException(
        'PDF\'te seçilebilir metin bulunamadı (taranmış bir belge olabilir; OCR desteklenmiyor).',
      );
    }
    final out = request.primaryOutputPath();
    await DocumentConverter.writeDocument(
      Doc(blocks),
      request.target,
      out,
      context.options,
      fallbackTitle: p.basenameWithoutExtension(request.input),
    );
    context.onProgress(1);
    return out;
  }
}

/// Birden fazla dosyayı (görsel, belge, PDF) tek bir PDF'te birleştirir.
class PdfMerger {
  /// Tek PDF'e dönüştürülebilen giriş formatları.
  static bool canMerge(FileFormat f) =>
      f == Formats.pdf ||
      ImageConverter.nativeInputs.contains(f) ||
      ImageConverter.ffmpegInputs.contains(f) ||
      DocumentConverter.readable.contains(f);

  static Future<String> merge(List<String> inputs, String outPath, ConversionContext context) async {
    final formats = inputs.map(Formats.fromPath).toList();
    final allImages = formats.every((f) => f != null && f.category == FormatCategory.image);
    final options = context.options;

    if (allImages) {
      // Hepsi görselse doğrudan tek PDF oluştur (PDFium gerekmez).
      final images = [
        for (var i = 0; i < inputs.length; i++)
          await () async {
            context.cancelToken.throwIfCancelled();
            final b = await ImageConverter.loadImageBytes(inputs[i], context);
            context.onProgress((i + 1) / inputs.length * 0.6);
            return b;
          }(),
      ];
      await writeImagesToPdf(images, outPath, options.pdfPageSize, options.maxWidth, options.maxHeight);
      context.onProgress(1);
      return outPath;
    }

    await ensurePdfEngine();
    final tmpDir = await Directory.systemTemp.createTemp('lc_merge_');
    final opened = <rx.PdfDocument>[];
    try {
      final pdfPaths = <String>[];
      for (var i = 0; i < inputs.length; i++) {
        context.cancelToken.throwIfCancelled();
        final input = inputs[i];
        final f = formats[i]!;
        if (f == Formats.pdf) {
          pdfPaths.add(input);
        } else {
          final tmp = p.join(tmpDir.path, '$i.pdf');
          if (f.category == FormatCategory.image) {
            final bytes = await ImageConverter.loadImageBytes(input, context);
            await writeImagesToPdf([bytes], tmp, options.pdfPageSize, options.maxWidth, options.maxHeight);
          } else {
            final doc = await DocumentConverter.readDocument(input);
            await writeDocToPdf(doc, tmp, options.pdfPageSize);
          }
          pdfPaths.add(tmp);
        }
        context.onProgress((i + 1) / inputs.length * 0.7);
      }

      for (final path in pdfPaths) {
        opened.add(await _open(path));
      }
      final combined = await rx.PdfDocument.createNew(sourceName: p.basename(outPath));
      try {
        combined.pages = [for (final d in opened) ...d.pages];
        await File(outPath).writeAsBytes(await combined.encodePdf());
      } finally {
        await combined.dispose();
      }
      context.onProgress(1);
      return outPath;
    } finally {
      for (final d in opened) {
        await d.dispose();
      }
      await tmpDir.delete(recursive: true);
    }
  }
}
