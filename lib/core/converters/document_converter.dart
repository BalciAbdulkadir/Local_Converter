import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../conversion.dart';
import '../document/doc_model.dart';
import '../document/doc_readers.dart';
import '../document/doc_writers.dart';
import '../formats.dart';
import '../tools.dart';
import 'pdf_writer.dart';

/// TXT, Markdown, HTML ve DOCX arasında; ayrıca bunlardan PDF'e dönüşüm.
class DocumentConverter extends Converter {
  static const readable = {Formats.txt, Formats.md, Formats.html, Formats.docx};
  static const writable = {Formats.txt, Formats.md, Formats.html, Formats.docx, Formats.pdf};

  @override
  Set<FileFormat> get inputFormats => readable;

  @override
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools) =>
      // DOCX → DOCX ve HTML → HTML biçimlendirmeyi kaybettirir; sunulmaz.
      {...writable}..removeAll({Formats.docx, Formats.html}.where((f) => f == input));

  @override
  Future<List<String>> convert(ConversionRequest request, ConversionContext context) async {
    final doc = await readDocument(request.input);
    context.cancelToken.throwIfCancelled();
    context.onProgress(0.5);
    final out = request.primaryOutputPath();
    await writeDocument(
      doc,
      request.target,
      out,
      context.options,
      fallbackTitle: p.basenameWithoutExtension(request.input),
    );
    context.onProgress(1);
    return [out];
  }

  static Future<Doc> readDocument(String path) async {
    final format = Formats.fromPath(path);
    final bytes = await File(path).readAsBytes();
    return Isolate.run(() {
      switch (format) {
        case Formats.txt:
          return readTxt(decodeText(bytes));
        case Formats.md:
          return readMarkdown(decodeText(bytes));
        case Formats.html:
          return readHtml(decodeText(bytes));
        case Formats.docx:
          return readDocx(bytes);
        default:
          throw ConversionException('${format?.id ?? 'Bu'} belge olarak okunamıyor.');
      }
    });
  }

  static Future<void> writeDocument(
    Doc doc,
    FileFormat target,
    String out,
    ConversionOptions options, {
    String? fallbackTitle,
  }) async {
    switch (target) {
      case Formats.txt:
        await File(out).writeAsString(writeTxt(doc));
      case Formats.md:
        await File(out).writeAsString(writeMarkdown(doc));
      case Formats.html:
        await File(out).writeAsString(writeHtml(doc, title: doc.title ?? fallbackTitle));
      case Formats.docx:
        await File(out).writeAsBytes(await Isolate.run(() => writeDocx(doc)));
      case Formats.pdf:
        await writeDocToPdf(Doc(doc.blocks, title: doc.title ?? fallbackTitle), out, options.pdfPageSize);
      default:
        throw ConversionException('Belge ${target.id} formatına yazılamıyor.');
    }
  }
}
