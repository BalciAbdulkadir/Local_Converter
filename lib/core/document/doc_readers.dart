import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;
import 'package:xml/xml.dart';

import '../conversion.dart';
import 'doc_model.dart';

/// Baytları metne çevirir: UTF-8 BOM'u atlar, geçersiz UTF-8 ise Latin-1'e düşer.
String decodeText(Uint8List bytes) {
  var data = bytes;
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = data.sublist(3);
  }
  // UTF-16 LE/BE BOM (Windows Not Defteri "Unicode" kaydı).
  if (data.length >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))) {
    final littleEndian = data[0] == 0xFF;
    final codes = <int>[];
    for (var i = 2; i + 1 < data.length; i += 2) {
      codes.add(littleEndian ? (data[i + 1] << 8) | data[i] : (data[i] << 8) | data[i + 1]);
    }
    return String.fromCharCodes(codes);
  }
  try {
    return utf8.decode(data);
  } on FormatException {
    return latin1.decode(data);
  }
}

// ---------------------------------------------------------------------------
// TXT
// ---------------------------------------------------------------------------

Doc readTxt(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = <Block>[];
  for (final para in normalized.split(RegExp(r'\n[ \t]*\n'))) {
    final trimmed = para.trimRight();
    if (trimmed.trim().isEmpty) continue;
    blocks.add(ParagraphBlock([Inline(trimmed)]));
  }
  return Doc(blocks);
}

// ---------------------------------------------------------------------------
// Markdown (HTML'e çevrilip HTML okuyucusuyla işlenir)
// ---------------------------------------------------------------------------

Doc readMarkdown(String text) {
  final htmlText = md.markdownToHtml(
    text.replaceAll('\r\n', '\n'),
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return readHtml('<html><body>$htmlText</body></html>');
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

const _skipTags = {'script', 'style', 'head', 'noscript', 'template', 'svg', 'iframe', 'object', 'button', 'select'};
const _containerTags = {
  'body', 'div', 'section', 'article', 'main', 'header', 'footer', 'nav', 'aside',
  'figure', 'figcaption', 'form', 'fieldset', 'details', 'summary', 'center', 'dl', 'dd', 'dt',
  'address', 'html',
};

Doc readHtml(String source) {
  final document = html_parser.parse(source);
  final title = document.querySelector('title')?.text.trim();
  final root = document.body ?? document.documentElement;
  final blocks = <Block>[];
  if (root != null) _walkBlocks(root.nodes, blocks);
  return Doc(blocks, title: (title == null || title.isEmpty) ? null : title);
}

void _walkBlocks(List<dom.Node> nodes, List<Block> blocks) {
  var pending = <Inline>[];

  void flush() {
    final spans = _trimSpans(normalizeSpans(pending));
    if (spansToPlain(spans).trim().isNotEmpty) blocks.add(ParagraphBlock(spans));
    pending = [];
  }

  for (final node in nodes) {
    if (node is dom.Text) {
      pending.add(Inline(_collapse(node.data)));
      continue;
    }
    if (node is! dom.Element) continue;
    final tag = node.localName ?? '';
    if (_skipTags.contains(tag)) continue;

    final headingMatch = RegExp(r'^h([1-6])$').firstMatch(tag);
    if (headingMatch != null) {
      flush();
      final spans = _trimSpans(normalizeSpans(_inlines(node)));
      if (spansToPlain(spans).trim().isNotEmpty) {
        blocks.add(HeadingBlock(int.parse(headingMatch.group(1)!), spans));
      }
      continue;
    }

    switch (tag) {
      case 'p':
        flush();
        pending.addAll(_inlines(node));
        flush();
      case 'ul':
      case 'ol':
        flush();
        final items = <ListItem>[];
        _collectListItems(node, 0, items);
        if (items.isNotEmpty) blocks.add(ListBlock(items, ordered: tag == 'ol'));
      case 'pre':
        flush();
        final code = node.text.replaceAll('\r\n', '\n');
        blocks.add(CodeBlock(code.endsWith('\n') ? code.substring(0, code.length - 1) : code));
      case 'blockquote':
        flush();
        final spans = _trimSpans(normalizeSpans(_inlines(node)));
        if (spansToPlain(spans).trim().isNotEmpty) blocks.add(QuoteBlock(spans));
      case 'hr':
        flush();
        blocks.add(const RuleBlock());
      case 'table':
        flush();
        final rows = <List<String>>[];
        for (final tr in node.querySelectorAll('tr')) {
          rows.add([
            for (final cell in tr.children)
              if (cell.localName == 'td' || cell.localName == 'th') _collapse(cell.text).trim(),
          ]);
        }
        if (rows.isNotEmpty) blocks.add(TableBlock(rows));
      case 'br':
        pending.add(const Inline('\n'));
      default:
        if (_containerTags.contains(tag)) {
          flush();
          _walkBlocks(node.nodes, blocks);
        } else {
          pending.addAll(_inlines(node));
        }
    }
  }
  flush();
}

void _collectListItems(dom.Element list, int level, List<ListItem> out) {
  for (final li in list.children.where((e) => e.localName == 'li')) {
    final spans = <Inline>[];
    final nested = <dom.Element>[];
    for (final child in li.nodes) {
      if (child is dom.Element && (child.localName == 'ul' || child.localName == 'ol')) {
        nested.add(child);
      } else if (child is dom.Text) {
        spans.add(Inline(_collapse(child.data)));
      } else if (child is dom.Element) {
        spans.addAll(_inlines(child));
      }
    }
    out.add(ListItem(_trimSpans(normalizeSpans(spans)), level: level));
    for (final n in nested) {
      _collectListItems(n, level + 1, out);
    }
  }
}

List<Inline> _inlines(dom.Element el, {bool bold = false, bool italic = false, bool code = false, String? link}) {
  final out = <Inline>[];
  for (final node in el.nodes) {
    if (node is dom.Text) {
      final text = code ? node.data : _collapse(node.data);
      out.add(Inline(text, bold: bold, italic: italic, code: code, link: link));
    } else if (node is dom.Element) {
      final tag = node.localName ?? '';
      if (_skipTags.contains(tag)) continue;
      if (tag == 'br') {
        out.add(const Inline('\n'));
        continue;
      }
      if (tag == 'img') {
        final alt = node.attributes['alt'];
        if (alt != null && alt.isNotEmpty) out.add(Inline('[$alt]', italic: true));
        continue;
      }
      out.addAll(_inlines(
        node,
        bold: bold || tag == 'b' || tag == 'strong' || tag == 'th',
        italic: italic || tag == 'i' || tag == 'em' || tag == 'cite',
        code: code || tag == 'code' || tag == 'kbd' || tag == 'samp' || tag == 'tt',
        link: tag == 'a' ? (node.attributes['href'] ?? link) : link,
      ));
      // Blok öğeleri arasında boşluk bırak (ör. liste içindeki <p>).
      if (tag == 'p' || tag == 'div' || tag == 'li') out.add(const Inline(' '));
    }
  }
  return out;
}

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

List<Inline> _trimSpans(List<Inline> spans) {
  final list = List.of(spans);
  while (list.isNotEmpty && list.first.text.trim().isEmpty) {
    list.removeAt(0);
  }
  while (list.isNotEmpty && list.last.text.trim().isEmpty) {
    list.removeLast();
  }
  if (list.isEmpty) return list;
  list[0] = list[0].copyWith(text: list[0].text.trimLeft());
  list[list.length - 1] = list.last.copyWith(text: list.last.text.trimRight());
  // Satır sonlarının etrafındaki boşlukları temizle.
  return [
    for (final s in list) s.code ? s : s.copyWith(text: s.text.replaceAll(RegExp(r' *\n *'), '\n')),
  ];
}

// ---------------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------------

final _headingStyle = RegExp(r'^(heading|balk|başlık|berschrift|titre|titolo|encabezado)\s?(\d)$', caseSensitive: false);

Doc readDocx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ConversionException('DOCX dosyası açılamadı (bozuk ya da şifreli olabilir).');
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) throw const ConversionException('Geçerli bir Word belgesi değil.');
  final xml = XmlDocument.parse(utf8.decode(entry.content as List<int>));
  final body = xml.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'body',
        orElse: () => throw const ConversionException('Word belgesinin gövdesi bulunamadı.'),
      );

  final blocks = <Block>[];
  List<ListItem>? pendingList;
  var pendingOrdered = false;

  void flushList() {
    if (pendingList != null && pendingList!.isNotEmpty) {
      blocks.add(ListBlock(pendingList!, ordered: pendingOrdered));
    }
    pendingList = null;
    pendingOrdered = false;
  }

  for (final el in body.childElements) {
    if (el.name.local == 'p') {
      final pPr = _child(el, 'pPr');
      final style = _attr(_child(pPr, 'pStyle'), 'val') ?? '';
      final numPr = _child(pPr, 'numPr');
      final spans = _trimSpans(normalizeSpans(_docxRuns(el)));
      final text = spansToPlain(spans);

      if (numPr != null) {
        final level = int.tryParse(_attr(_child(numPr, 'ilvl'), 'val') ?? '0') ?? 0;
        (pendingList ??= []).add(ListItem(spans, level: level));
        continue;
      }
      // Numaralandırma tanımı olmadan, elle yazılmış işaretli liste paragrafları
      // (bu uygulamanın ürettiği DOCX'ler dahil): "•<tab>metin" veya "1.<tab>metin".
      final marker = _listMarker.firstMatch(text);
      if (marker != null && (style == 'ListParagraph' || style.toLowerCase().startsWith('liste'))) {
        final left = int.tryParse(_attr(_child(pPr, 'ind'), 'left') ?? _attr(_child(pPr, 'ind'), 'start') ?? '') ?? 720;
        final level = ((left - 720) / 360).round().clamp(0, 8);
        if (pendingList == null) pendingOrdered = marker.group(1) != null;
        (pendingList ??= []).add(ListItem(_dropPrefix(spans, marker.end), level: level));
        continue;
      }
      flushList();
      if (text.trim().isEmpty) continue;

      final hm = _headingStyle.firstMatch(style);
      if (hm != null) {
        blocks.add(HeadingBlock(int.parse(hm.group(2)!).clamp(1, 6), spans));
      } else if (style.toLowerCase() == 'title' || style.toLowerCase() == 'konuby') {
        blocks.add(HeadingBlock(1, spans));
      } else if (style.toLowerCase().contains('quote') || style.toLowerCase().contains('alnt')) {
        blocks.add(QuoteBlock(spans));
      } else if (style.toLowerCase() == 'code') {
        blocks.add(CodeBlock(text));
      } else {
        blocks.add(ParagraphBlock(spans));
      }
    } else if (el.name.local == 'tbl') {
      flushList();
      final rows = <List<String>>[];
      for (final tr in el.childElements.where((e) => e.name.local == 'tr')) {
        rows.add([
          for (final tc in tr.childElements.where((e) => e.name.local == 'tc'))
            tc.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'p')
                .map((p) => spansToPlain(_docxRuns(p)).trim())
                .where((s) => s.isNotEmpty)
                .join(' '),
        ]);
      }
      if (rows.isNotEmpty) blocks.add(TableBlock(rows));
    }
  }
  flushList();
  return Doc(blocks);
}

List<Inline> _docxRuns(XmlElement paragraph) {
  final out = <Inline>[];
  for (final r in paragraph.descendants.whereType<XmlElement>().where((e) => e.name.local == 'r')) {
    final rPr = _child(r, 'rPr');
    final bold = _flag(_child(rPr, 'b'));
    final italic = _flag(_child(rPr, 'i'));
    final buf = StringBuffer();
    for (final c in r.childElements) {
      switch (c.name.local) {
        case 't':
          buf.write(c.innerText);
        case 'tab':
          buf.write('\t');
        case 'br':
        case 'cr':
          buf.write('\n');
      }
    }
    if (buf.isNotEmpty) out.add(Inline(buf.toString(), bold: bold, italic: italic));
  }
  return out;
}

final _listMarker = RegExp(r'^(?:(\d+)[.)]|[•\-–·▪◦*])	');

/// Satır içi parçalardan ilk [count] karakteri atar.
List<Inline> _dropPrefix(List<Inline> spans, int count) {
  final out = <Inline>[];
  var remaining = count;
  for (final s in spans) {
    if (remaining >= s.text.length) {
      remaining -= s.text.length;
      continue;
    }
    out.add(remaining > 0 ? s.copyWith(text: s.text.substring(remaining)) : s);
    remaining = 0;
  }
  return out;
}

XmlElement? _child(XmlElement? el, String local) {
  if (el == null) return null;
  for (final c in el.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

String? _attr(XmlElement? el, String local) {
  if (el == null) return null;
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

bool _flag(XmlElement? el) {
  if (el == null) return false;
  final v = _attr(el, 'val');
  return v == null || !(v == '0' || v == 'false' || v == 'none');
}
