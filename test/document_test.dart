import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_converter/core/conversion.dart';
import 'package:local_converter/core/converters/pdf_writer.dart';
import 'package:local_converter/core/document/doc_model.dart';
import 'package:local_converter/core/document/doc_readers.dart';
import 'package:local_converter/core/document/doc_writers.dart';

const _markdown = '''
# Başlık Bir

Bu bir **kalın** ve *italik* paragraftır. [Bağlantı](https://example.com) ve `kod`.

## Liste

- Birinci
- İkinci
  - İç içe
- Üçüncü

1. Bir
2. İki

> Alıntı metni

```
void main() {}
```

| Ad | Şehir |
| --- | --- |
| Ayşe | İzmir |

---

Son paragraf.
''';

void main() {
  test('Markdown okuyucu blokları tanır', () {
    final doc = readMarkdown(_markdown);
    final types = doc.blocks.map((b) => b.runtimeType).toList();
    expect(types, [
      HeadingBlock, ParagraphBlock, HeadingBlock, ListBlock, ListBlock,
      QuoteBlock, CodeBlock, TableBlock, RuleBlock, ParagraphBlock,
    ]);
    final para = doc.blocks[1] as ParagraphBlock;
    expect(para.spans.any((s) => s.bold && s.text == 'kalın'), isTrue);
    expect(para.spans.any((s) => s.link == 'https://example.com'), isTrue);
    final list = doc.blocks[3] as ListBlock;
    expect(list.items.map((i) => i.level), [0, 0, 1, 0]);
    expect((doc.blocks[4] as ListBlock).ordered, isTrue);
  });

  test('MD → HTML → MD yapıyı korur', () {
    final doc = readMarkdown(_markdown);
    final html = writeHtml(doc);
    expect(html, contains('<strong>kalın</strong>'));
    expect(html, contains('<ul><li>Birinci</li><li>İkinci<ul><li>İç içe</li></ul></li><li>Üçüncü</li></ul>'));
    final again = readHtml(html);
    expect(writeMarkdown(again), writeMarkdown(doc));
  });

  test('MD → DOCX → MD yapıyı korur', () {
    final doc = readMarkdown(_markdown);
    final docx = writeDocx(doc);
    final archive = ZipDecoder().decodeBytes(docx);
    expect(archive.findFile('word/document.xml'), isNotNull);
    final back = readDocx(docx);
    final types = back.blocks.map((b) => b.runtimeType).toSet();
    expect(types, containsAll([HeadingBlock, ParagraphBlock, ListBlock, QuoteBlock, TableBlock]));
    final heading = back.blocks.first as HeadingBlock;
    expect(heading.level, 1);
    expect(spansToPlain(heading.spans), 'Başlık Bir');
    final table = back.blocks.whereType<TableBlock>().first;
    expect(table.rows, [
      ['Ad', 'Şehir'],
      ['Ayşe', 'İzmir'],
    ]);
  });

  test('TXT okuyucu paragrafları ayırır, kodlamaları çözer', () {
    final doc = readTxt('Birinci satır\nikinci satır\n\n\nYeni paragraf');
    expect(doc.blocks.length, 2);
    // UTF-8 BOM
    expect(decodeText(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('çğ')])), 'çğ');
    // UTF-16 LE BOM
    expect(decodeText(Uint8List.fromList([0xFF, 0xFE, 0xE7, 0x00, 0x1F, 0x01])), 'çğ');
    // Geçersiz UTF-8 → Latin-1
    expect(decodeText(Uint8List.fromList([0x63, 0xE7])), 'cç');
  });

  test('HTML okuyucu script/style içeriğini atlar', () {
    final doc = readHtml('<html><head><title>T</title><style>p{}</style></head>'
        '<body><script>alert(1)</script><div>Metin <b>kalın</b></div></body></html>');
    expect(doc.title, 'T');
    expect(writeTxt(doc).trim(), 'Metin kalın');
  });

  test('Belge → PDF geçerli bir PDF üretir', () async {
    final doc = readMarkdown(_markdown);
    final fonts = await FontBundle.load();
    final pdf = await buildDocPdf(doc, fonts, PdfPageSize.a4);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });

  test('uniquePath aynı yolu iki kez vermez', () {
    final a = uniquePath(r'C:\olmayan\klasor\dosya.txt');
    final b = uniquePath(r'C:\olmayan\klasor\dosya.txt');
    expect(a, isNot(b));
    expect(b, endsWith('dosya (1).txt'));
  });
}
