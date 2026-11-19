import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../conversion.dart';
import '../document/doc_model.dart';
import 'image_converter.dart';

/// PDF'e gömülecek font dosyaları. PDF'in yerleşik Helvetica fontu Türkçe
/// karakterleri (ş, ğ, ı, İ) içermediği için sistem fontları kullanılır.
class FontBundle {
  const FontBundle({this.regular, this.bold, this.italic, this.boldItalic, this.mono});
  final Uint8List? regular;
  final Uint8List? bold;
  final Uint8List? italic;
  final Uint8List? boldItalic;
  final Uint8List? mono;

  static FontBundle? _cache;

  static Future<FontBundle> load() async {
    if (_cache != null) return _cache!;
    final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final fontsDir = p.join(windir, 'Fonts');

    Future<Uint8List?> read(List<String> names) async {
      for (final n in names) {
        final f = File(p.join(fontsDir, n));
        if (await f.exists()) return f.readAsBytes();
      }
      return null;
    }

    return _cache = FontBundle(
      regular: await read(['arial.ttf', 'segoeui.ttf', 'calibri.ttf']),
      bold: await read(['arialbd.ttf', 'segoeuib.ttf', 'calibrib.ttf']),
      italic: await read(['ariali.ttf', 'segoeuii.ttf', 'calibrii.ttf']),
      boldItalic: await read(['arialbi.ttf', 'segoeuiz.ttf', 'calibriz.ttf']),
      mono: await read(['consola.ttf', 'cour.ttf']),
    );
  }

  pw.ThemeData theme() {
    pw.Font? f(Uint8List? b) => b == null ? null : pw.Font.ttf(b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes));
    final base = f(regular);
    if (base == null) return pw.ThemeData.base();
    return pw.ThemeData.withFont(
      base: base,
      bold: f(bold) ?? base,
      italic: f(italic) ?? base,
      boldItalic: f(boldItalic) ?? f(bold) ?? base,
    );
  }

  pw.Font? monoFont() => mono == null ? null : pw.Font.ttf(mono!.buffer.asByteData(mono!.offsetInBytes, mono!.lengthInBytes));
}

PdfPageFormat _pageFormat(PdfPageSize size) => switch (size) {
      PdfPageSize.letter => PdfPageFormat.letter,
      _ => PdfPageFormat.a4,
    };

// ---------------------------------------------------------------------------
// Belge → PDF
// ---------------------------------------------------------------------------

Future<void> writeDocToPdf(Doc doc, String outPath, PdfPageSize size) async {
  final fonts = await FontBundle.load();
  final bytes = await Isolate.run(() => buildDocPdf(doc, fonts, size));
  await File(outPath).writeAsBytes(bytes);
}

Future<Uint8List> buildDocPdf(Doc doc, FontBundle fonts, PdfPageSize size) async {
  final mono = fonts.monoFont();
  final pdf = pw.Document(theme: fonts.theme(), title: doc.title);

  pw.TextSpan spans(List<Inline> list, {pw.TextStyle? base}) => pw.TextSpan(
        style: base,
        children: [
          for (final s in list)
            pw.TextSpan(
              text: s.text,
              style: pw.TextStyle(
                fontWeight: s.bold ? pw.FontWeight.bold : null,
                fontStyle: s.italic ? pw.FontStyle.italic : null,
                font: s.code ? mono : null,
                color: s.link != null ? PdfColors.blue700 : null,
                decoration: s.link != null ? pw.TextDecoration.underline : null,
                background: s.code ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
              ),
            ),
        ],
      );

  const headingSizes = [22.0, 18.0, 15.0, 13.0, 12.0, 11.0];
  final widgets = <pw.Widget>[];
  for (final b in doc.blocks) {
    switch (b) {
      case HeadingBlock():
        widgets.add(pw.Padding(
          padding: pw.EdgeInsets.only(top: b.level <= 2 ? 14 : 10, bottom: 6),
          child: pw.RichText(
            text: spans(b.spans,
                base: pw.TextStyle(
                  fontSize: headingSizes[b.level - 1],
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1F3864'),
                )),
          ),
        ));
      case ParagraphBlock():
        // TextOverflow.span: sayfadan uzun paragraflar sonraki sayfaya taşar.
        // (Padding gibi bir sarmalayıcı bölünmeyi engellediği için boşluk ayrı eklenir.)
        widgets.add(pw.RichText(text: spans(b.spans), textAlign: pw.TextAlign.left, overflow: pw.TextOverflow.span));
        widgets.add(pw.SizedBox(height: 8));
      case ListBlock():
        final counters = <int, int>{};
        for (final item in b.items) {
          counters.removeWhere((lvl, _) => lvl > item.level);
          final n = counters[item.level] = (counters[item.level] ?? 0) + 1;
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: 12.0 + item.level * 16, bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 18, child: pw.Text(b.ordered ? '$n.' : '•')),
              pw.Expanded(child: pw.RichText(text: spans(item.spans))),
            ]),
          ));
        }
        widgets.add(pw.SizedBox(height: 6));
      case CodeBlock():
        // Uzun kod blokları sayfalara bölünebilsin diye satır satır eklenir.
        final lines = b.text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          widgets.add(pw.Container(
            color: PdfColors.grey200,
            padding: pw.EdgeInsets.fromLTRB(8, i == 0 ? 6 : 0, 8, i == lines.length - 1 ? 6 : 0),
            child: pw.Text(lines[i].isEmpty ? ' ' : lines[i], style: pw.TextStyle(font: mono, fontSize: 9)),
          ));
        }
        widgets.add(pw.SizedBox(height: 8));
      case QuoteBlock() when spansToPlain(b.spans).length > 1500:
        // Çok uzun alıntılar kenarlıklı kutuya sığmaz; bölünebilir metin olarak yaz.
        widgets.add(pw.RichText(
          text: spans(b.spans, base: const pw.TextStyle(color: PdfColors.grey700, fontStyle: pw.FontStyle.italic)),
          overflow: pw.TextOverflow.span,
        ));
        widgets.add(pw.SizedBox(height: 8));
      case QuoteBlock():
        widgets.add(pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.only(left: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 3)),
          ),
          child: pw.RichText(
            text: spans(b.spans, base: const pw.TextStyle(color: PdfColors.grey700, fontStyle: pw.FontStyle.italic)),
          ),
        ));
      case RuleBlock():
        widgets.add(pw.Divider(color: PdfColors.grey400));
      case TableBlock():
        final cols = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
        final rows = [for (final r in b.rows) [...r, ...List.filled(cols - r.length, '')]];
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ));
    }
  }
  if (widgets.isEmpty) widgets.add(pw.SizedBox());

  pdf.addPage(pw.MultiPage(
    pageFormat: _pageFormat(size),
    margin: const pw.EdgeInsets.all(48),
    maxPages: 10000,
    build: (_) => widgets,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
  ));
  return pdf.save();
}

// ---------------------------------------------------------------------------
// Görseller → PDF
// ---------------------------------------------------------------------------

Future<void> writeImagesToPdf(
  List<Uint8List> images,
  String outPath,
  PdfPageSize size,
  int? maxWidth,
  int? maxHeight,
) async {
  final bytes = await Isolate.run(() => buildImagesPdf(images, size, maxWidth, maxHeight));
  await File(outPath).writeAsBytes(bytes);
}

Future<Uint8List> buildImagesPdf(List<Uint8List> images, PdfPageSize size, int? maxWidth, int? maxHeight) async {
  final pdf = pw.Document();
  for (final raw in images) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) throw const ConversionException('Görsel okunamadı.');
    var image = img.bakeOrientation(img.Image.from(decoded, noAnimation: true));
    image = resizeToFit(image, maxWidth, maxHeight);
    // Fotoğrafları JPG, şeffaf görselleri PNG olarak göm (dosya boyutu için).
    final embedded = image.hasAlpha ? img.encodePng(image) : img.encodeJpg(image, quality: 92);
    final pdfImage = pw.MemoryImage(embedded);

    final PdfPageFormat format;
    final double margin;
    if (size == PdfPageSize.fit) {
      // 96 DPI kabulüyle piksel → punto.
      format = PdfPageFormat(image.width * 72 / 96, image.height * 72 / 96);
      margin = 0;
    } else {
      final base = _pageFormat(size);
      format = image.width > image.height ? base.landscape : base.portrait;
      margin = 24;
    }
    pdf.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.all(margin),
      build: (_) => pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
    ));
  }
  return pdf.save();
}
