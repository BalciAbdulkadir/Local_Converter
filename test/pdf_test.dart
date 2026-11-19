import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_converter/core/conversion.dart';
import 'package:local_converter/core/conversion_service.dart';
import 'package:local_converter/core/converters/pdf_converter.dart';
import 'package:local_converter/core/document/doc_readers.dart';
import 'package:local_converter/core/converters/pdf_writer.dart';
import 'package:local_converter/core/formats.dart';
import 'package:local_converter/core/tools.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' as rx;

void main() {
  late Directory tmp;
  late ExternalTools tools;
  final service = ConversionService();

  setUpAll(() async {
    pdfEngineInitializer = rx.pdfrxInitialize;
    tools = await ExternalTools.detect();
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('lc_pdf_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 3 sayfalık, Türkçe metinli bir PDF oluşturur.
  Future<String> makePdf(String name) async {
    final md = [
      for (var i = 1; i <= 3; i++) '# Sayfa $i\n\nÇağrı şöyle dedi: ığdır İzmir.\n\n${'Uzun paragraf. ' * 400}',
    ].join('\n\n');
    final path = p.join(tmp.path, name);
    await writeDocToPdf(readMarkdown(md), path, PdfPageSize.a4);
    return path;
  }

  Future<int> pageCount(String path) async {
    final d = await rx.PdfDocument.openFile(path);
    final n = d.pages.length;
    await d.dispose();
    return n;
  }

  Future<List<JobUpdate>> run(List<String> inputs, FileFormat target, [ConversionOptions? o]) async {
    final finals = List<JobUpdate?>.filled(inputs.length, null);
    await service.runBatch(
      inputs: inputs,
      target: target,
      options: o ?? const ConversionOptions(pdfRenderDpi: 72),
      tools: tools,
      cancelToken: CancelToken(),
      onUpdate: (i, u) {
        if (u.status != JobStatus.running) finals[i] = u;
      },
    );
    return finals.cast<JobUpdate>();
  }

  test('PDF → PNG: her sayfa ayrı görsel', () async {
    final src = await makePdf('belge.pdf');
    final pages = await pageCount(src);
    expect(pages, greaterThanOrEqualTo(3));
    final [r] = await run([src], Formats.png);
    expect(r.status, JobStatus.done, reason: r.error);
    expect(r.outputs.length, pages);
    expect(p.basename(r.outputs.first), 'belge_01.png');
    final image = img.decodePng(File(r.outputs.first).readAsBytesSync())!;
    // A4 @ 72 DPI ≈ 595 x 842
    expect(image.width, closeTo(595, 2));
    // Beyaz zemin (şeffaf değil).
    expect(image.getPixel(2, 2).r, 255);
  });

  test('PDF → JPG ve WEBP', () async {
    final src = await makePdf('belge.pdf');
    final [jpg] = await run([src], Formats.jpg);
    expect(jpg.status, JobStatus.done, reason: jpg.error);
    final [webp] = await run([src], Formats.webp);
    expect(webp.status, JobStatus.done, reason: webp.error);
    expect(String.fromCharCodes(File(webp.outputs.first).readAsBytesSync().sublist(8, 12)), 'WEBP');
  });

  test('PDF → TXT / DOCX metni Türkçe karakterleriyle çıkarır', () async {
    final src = await makePdf('belge.pdf');
    final [txt] = await run([src], Formats.txt);
    expect(txt.status, JobStatus.done, reason: txt.error);
    final text = File(txt.outputs.single).readAsStringSync();
    expect(text, contains('Sayfa 1'));
    expect(text, contains('Çağrı şöyle dedi: ığdır İzmir.'));
    final [docx] = await run([src], Formats.docx);
    expect(docx.status, JobStatus.done, reason: docx.error);
  });

  test('PDF → PDF sayfalara böler', () async {
    final src = await makePdf('belge.pdf');
    final pages = await pageCount(src);
    final [r] = await run([src], Formats.pdf);
    expect(r.status, JobStatus.done, reason: r.error);
    expect(r.outputs.length, pages);
    for (final o in r.outputs) {
      expect(await pageCount(o), 1);
    }
  });

  test('PDF + görsel + Markdown tek PDF\'te birleşir', () async {
    final pdf = await makePdf('belge.pdf');
    final png = p.join(tmp.path, 'resim.png');
    File(png).writeAsBytesSync(img.encodePng(img.Image(width: 100, height: 50)));
    final md = p.join(tmp.path, 'not.md');
    File(md).writeAsStringSync('# Not\n\nKısa metin.');
    final pdfPages = await pageCount(pdf);

    final results = await run([pdf, png, md], Formats.pdf, const ConversionOptions(mergeIntoSinglePdf: true));
    expect(results.every((r) => r.status == JobStatus.done), isTrue, reason: results.first.error);
    final out = results.first.outputs.single;
    expect(p.basename(out), 'belge_birlesik.pdf');
    expect(await pageCount(out), pdfPages + 2);
  });

  test('bozuk PDF anlaşılır hata verir', () async {
    final bad = p.join(tmp.path, 'bozuk.pdf');
    File(bad).writeAsStringSync('bu bir pdf değil');
    final [r] = await run([bad], Formats.png);
    expect(r.status, JobStatus.failed);
    expect(r.error, contains('PDF olarak açılamadı'));
  });
}
