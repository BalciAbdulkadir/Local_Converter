import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'doc_model.dart';

// ---------------------------------------------------------------------------
// TXT
// ---------------------------------------------------------------------------

String writeTxt(Doc doc) {
  final parts = <String>[];
  for (final b in doc.blocks) {
    switch (b) {
      case HeadingBlock():
        final t = spansToPlain(b.spans);
        parts.add(b.level <= 2 ? '$t\n${(b.level == 1 ? '=' : '-') * t.length.clamp(3, 80)}' : t);
      case ParagraphBlock():
        parts.add(spansToPlain(b.spans));
      case ListBlock():
        parts.add(_listLines(b, (i) => spansToPlain(i.spans)).join('\n'));
      case CodeBlock():
        parts.add(b.text.split('\n').map((l) => '    $l').join('\n'));
      case QuoteBlock():
        parts.add(spansToPlain(b.spans).split('\n').map((l) => '> $l').join('\n'));
      case RuleBlock():
        parts.add('-' * 40);
      case TableBlock():
        parts.add(_textTable(b.rows));
    }
  }
  return '${parts.join('\n\n')}\n';
}

List<String> _listLines(ListBlock list, String Function(ListItem) render) {
  final counters = <int, int>{};
  return [
    for (final item in list.items)
      () {
        counters.removeWhere((lvl, _) => lvl > item.level);
        final n = counters[item.level] = (counters[item.level] ?? 0) + 1;
        final marker = list.ordered ? '$n.' : '-';
        return '${'  ' * item.level}$marker ${render(item)}';
      }(),
  ];
}

String _textTable(List<List<String>> rows) {
  final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  final widths = List<int>.filled(cols, 0);
  for (final r in rows) {
    for (var i = 0; i < r.length; i++) {
      if (r[i].length > widths[i]) widths[i] = r[i].length;
    }
  }
  String line(List<String> r) =>
      [for (var i = 0; i < cols; i++) (i < r.length ? r[i] : '').padRight(widths[i])].join(' | ').trimRight();
  final out = <String>[line(rows.first)];
  if (rows.length > 1) {
    out.add(widths.map((w) => '-' * w.clamp(1, 1000)).join('-+-'));
    out.addAll(rows.skip(1).map(line));
  }
  return out.join('\n');
}

// ---------------------------------------------------------------------------
// Markdown
// ---------------------------------------------------------------------------

String writeMarkdown(Doc doc) {
  final parts = <String>[];
  for (final b in doc.blocks) {
    switch (b) {
      case HeadingBlock():
        parts.add('${'#' * b.level} ${_mdInline(b.spans)}');
      case ParagraphBlock():
        parts.add(_mdInline(b.spans).replaceAll('\n', '  \n'));
      case ListBlock():
        parts.add(_listLines(b, (i) => _mdInline(i.spans)).join('\n'));
      case CodeBlock():
        final fence = b.text.contains('```') ? '~~~' : '```';
        parts.add('$fence\n${b.text}\n$fence');
      case QuoteBlock():
        parts.add(_mdInline(b.spans).split('\n').map((l) => '> $l').join('\n'));
      case RuleBlock():
        parts.add('---');
      case TableBlock():
        final cols = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
        String row(List<String> r) =>
            '| ${[for (var i = 0; i < cols; i++) (i < r.length ? r[i] : '').replaceAll('|', r'\|')].join(' | ')} |';
        parts.add([
          row(b.rows.first),
          '|${List.filled(cols, ' --- ').join('|')}|',
          ...b.rows.skip(1).map(row),
        ].join('\n'));
    }
  }
  return '${parts.join('\n\n')}\n';
}

String _mdEscape(String s) => s.replaceAllMapped(RegExp(r'([\\`*_\[\]])'), (m) => '\\${m[1]}');

String _mdInline(List<Inline> spans) {
  final buf = StringBuffer();
  for (final s in spans) {
    if (s.code) {
      final tick = s.text.contains('`') ? '``' : '`';
      buf.write('$tick${s.text}$tick');
      continue;
    }
    // İşaretleri boşlukların içine yerleştir: "**kalın** " doğru, "**kalın **" yanlış.
    final m = RegExp(r'^(\s*)(.*?)(\s*)$', dotAll: true).firstMatch(s.text)!;
    var core = _mdEscape(m[2]!);
    if (core.isEmpty) {
      buf.write(s.text);
      continue;
    }
    if (s.italic) core = '*$core*';
    if (s.bold) core = '**$core**';
    if (s.link != null) core = '[$core](${s.link})';
    buf.write('${m[1]}$core${m[3]}');
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

const htmlEscape = HtmlEscape(HtmlEscapeMode.element);

String writeHtml(Doc doc, {String? title}) {
  final body = StringBuffer();
  for (final b in doc.blocks) {
    switch (b) {
      case HeadingBlock():
        body.writeln('<h${b.level}>${_htmlInline(b.spans)}</h${b.level}>');
      case ParagraphBlock():
        body.writeln('<p>${_htmlInline(b.spans)}</p>');
      case ListBlock():
        body.writeln(_htmlList(b));
      case CodeBlock():
        body.writeln('<pre><code>${htmlEscape.convert(b.text)}</code></pre>');
      case QuoteBlock():
        body.writeln('<blockquote>${_htmlInline(b.spans)}</blockquote>');
      case RuleBlock():
        body.writeln('<hr>');
      case TableBlock():
        body.writeln('<table>');
        for (var i = 0; i < b.rows.length; i++) {
          final tag = i == 0 ? 'th' : 'td';
          body.writeln('  <tr>${b.rows[i].map((c) => '<$tag>${htmlEscape.convert(c)}</$tag>').join()}</tr>');
        }
        body.writeln('</table>');
    }
  }
  final pageTitle = htmlEscape.convert(title ?? doc.title ?? 'Belge');
  return '''<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$pageTitle</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: "Segoe UI", system-ui, sans-serif; line-height: 1.6; max-width: 820px; margin: 2rem auto; padding: 0 1rem; }
  pre { background: rgba(127,127,127,.12); padding: 1rem; border-radius: 6px; overflow-x: auto; }
  code { font-family: Consolas, "Cascadia Code", monospace; font-size: .92em; }
  blockquote { margin: 1rem 0; padding: .25rem 1rem; border-left: 4px solid rgba(127,127,127,.4); opacity: .85; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { border: 1px solid rgba(127,127,127,.35); padding: .4rem .6rem; text-align: left; vertical-align: top; }
  th { background: rgba(127,127,127,.12); }
  hr { border: none; border-top: 1px solid rgba(127,127,127,.35); margin: 2rem 0; }
</style>
</head>
<body>
$body</body>
</html>
''';
}

String _htmlList(ListBlock list) {
  final tag = list.ordered ? 'ol' : 'ul';
  final buf = StringBuffer();
  var depth = -1;
  for (final item in list.items) {
    final level = item.level.clamp(0, depth + 1);
    if (level > depth) {
      for (var d = depth; d < level; d++) {
        buf.write('<$tag>');
      }
    } else {
      buf.write('</li>');
      for (var d = depth; d > level; d--) {
        buf.write('</$tag></li>');
      }
    }
    depth = level;
    buf.write('<li>${_htmlInline(item.spans)}');
  }
  buf.write('</li>');
  for (var d = depth; d > 0; d--) {
    buf.write('</$tag></li>');
  }
  buf.write('</$tag>');
  return buf.toString();
}

String _htmlInline(List<Inline> spans) {
  final buf = StringBuffer();
  for (final s in spans) {
    var t = htmlEscape.convert(s.text).replaceAll('\n', '<br>');
    if (s.code) t = '<code>$t</code>';
    if (s.italic) t = '<em>$t</em>';
    if (s.bold) t = '<strong>$t</strong>';
    if (s.link != null) t = '<a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(s.link!)}">$t</a>';
    buf.write(t);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------------

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // XML 1.0'da geçersiz kontrol karakterlerini at.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

Uint8List writeDocx(Doc doc) {
  final links = <String>[];
  final body = StringBuffer();

  String runs(List<Inline> spans, {bool forceItalic = false, bool mono = false}) {
    final buf = StringBuffer();
    for (final s in spans) {
      final rPr = StringBuffer();
      if (s.link != null) rPr.write('<w:rStyle w:val="Hyperlink"/>');
      if (s.code || mono) rPr.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>');
      if (s.bold) rPr.write('<w:b/>');
      if (s.italic || forceItalic) rPr.write('<w:i/>');
      final props = rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>';

      final content = StringBuffer();
      final lines = s.text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) content.write('<w:br/>');
        final segs = lines[i].split('\t');
        for (var j = 0; j < segs.length; j++) {
          if (j > 0) content.write('<w:tab/>');
          if (segs[j].isNotEmpty) content.write('<w:t xml:space="preserve">${_x(segs[j])}</w:t>');
        }
      }
      final run = '<w:r>$props$content</w:r>';
      if (s.link != null) {
        links.add(s.link!);
        buf.write('<w:hyperlink r:id="rIdLink${links.length}">$run</w:hyperlink>');
      } else {
        buf.write(run);
      }
    }
    return buf.toString();
  }

  String para(String content, {String? style, int indentTwips = 0}) {
    final pPr = StringBuffer();
    if (style != null) pPr.write('<w:pStyle w:val="$style"/>');
    if (indentTwips > 0) pPr.write('<w:ind w:left="$indentTwips" w:hanging="360"/>');
    return '<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}$content</w:p>';
  }

  for (final b in doc.blocks) {
    switch (b) {
      case HeadingBlock():
        body.write(para(runs(b.spans), style: 'Heading${b.level}'));
      case ParagraphBlock():
        body.write(para(runs(b.spans)));
      case ListBlock():
        final counters = <int, int>{};
        for (final item in b.items) {
          counters.removeWhere((lvl, _) => lvl > item.level);
          final n = counters[item.level] = (counters[item.level] ?? 0) + 1;
          final marker = b.ordered ? '$n.\t' : '•\t';
          body.write(para(
            '<w:r><w:t xml:space="preserve">$marker</w:t></w:r>${runs(item.spans)}',
            style: 'ListParagraph',
            indentTwips: 720 + item.level * 360,
          ));
        }
      case CodeBlock():
        for (final line in b.text.split('\n')) {
          body.write(para(runs([Inline(line)], mono: true), style: 'Code'));
        }
      case QuoteBlock():
        body.write(para(runs(b.spans), style: 'Quote'));
      case RuleBlock():
        body.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="AAAAAA"/></w:pBdr></w:pPr></w:p>');
      case TableBlock():
        final cols = b.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
        body.write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/></w:tblPr><w:tblGrid>');
        for (var i = 0; i < cols; i++) {
          body.write('<w:gridCol/>');
        }
        body.write('</w:tblGrid>');
        for (var r = 0; r < b.rows.length; r++) {
          body.write('<w:tr>');
          for (var c = 0; c < cols; c++) {
            final text = c < b.rows[r].length ? b.rows[r][c] : '';
            body.write('<w:tc>${para(runs([Inline(text, bold: r == 0)]))}</w:tc>');
          }
          body.write('</w:tr>');
        }
        body.write('</w:tbl>');
    }
  }

  const wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  const rNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="$wNs" xmlns:r="$rNs"><w:body>$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  final rels = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
  );
  for (var i = 0; i < links.length; i++) {
    rels.write('<Relationship Id="rIdLink${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
        'Target="${_x(links[i])}" TargetMode="External"/>');
  }
  rels.write('</Relationships>');

  final archive = Archive();
  void add(String name, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  add('[Content_Types].xml', _docxContentTypes);
  add('_rels/.rels', _docxRootRels);
  add('word/document.xml', documentXml);
  add('word/_rels/document.xml.rels', rels.toString());
  add('word/styles.xml', _docxStyles);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _docxContentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _docxRootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

String _headingStyle(int level, int halfPoints) => '<w:style w:type="paragraph" w:styleId="Heading$level">'
    '<w:name w:val="heading $level"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="${level <= 2 ? 360 : 240}" w:after="120"/><w:outlineLvl w:val="${level - 1}"/></w:pPr>'
    '<w:rPr><w:b/><w:color w:val="1F3864"/><w:sz w:val="$halfPoints"/></w:rPr></w:style>';

final _docxStyles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/>'
    '<w:sz w:val="22"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    '${_headingStyle(1, 36)}${_headingStyle(2, 30)}${_headingStyle(3, 26)}'
    '${_headingStyle(4, 24)}${_headingStyle(5, 22)}${_headingStyle(6, 22)}'
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:spacing w:after="60"/></w:pPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="567"/><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="BFBFBF"/></w:pBdr></w:pPr>'
    '<w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz w:val="19"/></w:rPr></w:style>'
    '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>'
    '<w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>'
    '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders>'
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '</w:tblBorders><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
    '</w:styles>';
