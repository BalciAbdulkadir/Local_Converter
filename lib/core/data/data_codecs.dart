import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import '../conversion.dart';

// ---------------------------------------------------------------------------
// Ortak yardımcılar
// ---------------------------------------------------------------------------

final _intRe = RegExp(r'^-?(0|[1-9]\d{0,17})$');
final _doubleRe = RegExp(r'^-?(0|[1-9]\d*)\.\d+([eE][-+]?\d+)?$');

/// Metin hücreleri sayı / mantıksal değere çevirir. "007" gibi baştaki sıfırlı
/// değerler metin olarak kalır.
Object? inferScalar(String s) {
  if (_intRe.hasMatch(s)) return int.parse(s);
  if (_doubleRe.hasMatch(s)) return double.parse(s);
  if (s == 'true') return true;
  if (s == 'false') return false;
  return s;
}

/// İç içe yapıyı "a.b.c" anahtarlarıyla tek seviyeye indirir.
Map<String, Object?> flatten(Object? value, [String prefix = '']) {
  final out = <String, Object?>{};
  if (value is Map) {
    if (value.isEmpty && prefix.isNotEmpty) out[prefix] = '';
    value.forEach((k, v) {
      final key = prefix.isEmpty ? '$k' : '$prefix.$k';
      if (v is Map) {
        out.addAll(flatten(v, key));
      } else if (v is List) {
        out[key] = v.every((e) => e is! Map && e is! List) ? v.join(', ') : jsonEncode(v);
      } else {
        out[key] = v;
      }
    });
  } else {
    out[prefix.isEmpty ? 'value' : prefix] = value;
  }
  return out;
}

/// "a.b.c" anahtarlarını tekrar iç içe yapıya çevirir.
Map<String, Object?> unflatten(Map<String, Object?> flat) {
  final out = <String, Object?>{};
  flat.forEach((key, value) {
    final parts = key.split('.');
    var node = out;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = node[parts[i]];
      if (next is Map<String, Object?>) {
        node = next;
      } else if (next == null) {
        final created = <String, Object?>{};
        node[parts[i]] = created;
        node = created;
      } else {
        // Çakışma: düz anahtarı olduğu gibi bırak.
        node = out;
        out[key] = value;
        return;
      }
    }
    node[parts.last] = value;
  });
  return out;
}

/// Herhangi bir veri yapısını tabloya (başlık + satırlar) çevirir.
List<List<Object?>> toTable(Object? data) {
  // {"kullanicilar": [...]} gibi tek listeli kök nesneleri aç.
  if (data is Map && data.length == 1 && data.values.first is List) {
    data = data.values.first;
  }
  if (data is Map && data.values.isNotEmpty && data.values.every((v) => v is List)) {
    // Birden çok sayfalı (XLSX) veri: ilk sayfa alınır.
    data = data.values.first;
  }
  if (data is! List) data = [data];

  if (data.isNotEmpty && data.every((r) => r is List)) {
    return [for (final r in data) List<Object?>.from(r as List)];
  }

  final rows = [for (final item in data) flatten(item is Map ? item : {'value': item})];
  final headers = <String>[];
  final seen = <String>{};
  for (final r in rows) {
    for (final k in r.keys) {
      if (seen.add(k)) headers.add(k);
    }
  }
  return [
    headers,
    for (final r in rows) [for (final h in headers) r[h]],
  ];
}

/// Tabloyu (ilk satır başlık) nesne listesine çevirir.
List<Map<String, Object?>> fromTable(List<List<Object?>> table) {
  if (table.isEmpty) return [];
  final headers = <String>[];
  final used = <String, int>{};
  for (var i = 0; i < table.first.length; i++) {
    var h = '${table.first[i] ?? ''}'.trim();
    if (h.isEmpty) h = 'sutun${i + 1}';
    final n = used[h] = (used[h] ?? 0) + 1;
    headers.add(n > 1 ? '${h}_$n' : h);
  }
  return [
    for (final row in table.skip(1))
      if (row.any((c) => c != null && '$c'.isNotEmpty))
        unflatten({
          for (var i = 0; i < headers.length; i++)
            headers[i]: i < row.length ? (row[i] is String ? inferScalar(row[i] as String) : row[i]) : null,
        }),
  ];
}

// ---------------------------------------------------------------------------
// JSON
// ---------------------------------------------------------------------------

Object? readJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw ConversionException('Geçersiz JSON: ${e.message}');
  }
}

String writeJson(Object? data) => '${const JsonEncoder.withIndent('  ').convert(data)}\n';

// ---------------------------------------------------------------------------
// YAML
// ---------------------------------------------------------------------------

Object? readYaml(String text) {
  try {
    final docs = loadYamlDocuments(text).map((d) => _plain(d.contents.value)).toList();
    if (docs.isEmpty) return null;
    return docs.length == 1 ? docs.first : docs;
  } on YamlException catch (e) {
    throw ConversionException('Geçersiz YAML: ${e.message}');
  }
}

Object? _plain(Object? v) {
  if (v is YamlMap) return {for (final e in v.entries) '${e.key}': _plain(e.value)};
  if (v is YamlList) return [for (final e in v) _plain(e)];
  if (v is Map) return {for (final e in v.entries) '${e.key}': _plain(e.value)};
  if (v is List) return [for (final e in v) _plain(e)];
  return v;
}

String writeYaml(Object? data) {
  final buf = StringBuffer();
  _yamlNode(data, 0, buf, inline: false);
  final s = buf.toString();
  return s.endsWith('\n') ? s : '$s\n';
}

final _yamlPlainSafe = RegExp(r'^[A-Za-z0-9_çğıöşüÇĞİÖŞÜ][A-Za-z0-9_ .\-/çğıöşüÇĞİÖŞÜ]*$');
const _yamlReserved = {'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~', 'y', 'n'};

String _yamlScalar(Object? v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  final s = '$v';
  final looksLikeNumber = num.tryParse(s) != null;
  if (s.isNotEmpty &&
      _yamlPlainSafe.hasMatch(s) &&
      !looksLikeNumber &&
      !_yamlReserved.contains(s.toLowerCase()) &&
      s.trim() == s) {
    return s;
  }
  // JSON tırnaklı metinler geçerli YAML'dır.
  return jsonEncode(s);
}

String _yamlKey(String k) => _yamlScalar(k);

void _yamlNode(Object? v, int indent, StringBuffer buf, {required bool inline}) {
  final pad = '  ' * indent;
  if (v is Map) {
    if (v.isEmpty) {
      buf.writeln(inline ? ' {}' : '{}');
      return;
    }
    if (inline) buf.writeln();
    v.forEach((k, val) {
      buf.write('$pad${_yamlKey('$k')}:');
      if ((val is Map && val.isNotEmpty) || (val is List && val.isNotEmpty)) {
        _yamlNode(val, val is List ? indent : indent + 1, buf, inline: true);
      } else if (val is Map || val is List) {
        buf.writeln(val is Map ? ' {}' : ' []');
      } else if (val is String && val.contains('\n')) {
        buf.writeln(' |-');
        for (final line in val.split('\n')) {
          buf.writeln('$pad  $line');
        }
      } else {
        buf.writeln(' ${_yamlScalar(val)}');
      }
    });
  } else if (v is List) {
    if (v.isEmpty) {
      buf.writeln(inline ? ' []' : '[]');
      return;
    }
    if (inline) buf.writeln();
    for (final item in v) {
      if (item is Map && item.isNotEmpty) {
        // "- anahtar: değer" biçimi: ilk satır tire ile, kalanlar hizalı.
        final inner = StringBuffer();
        _yamlNode(item, indent + 1, inner, inline: false);
        final lines = inner.toString().split('\n');
        buf.writeln('$pad- ${lines.first.trimLeft()}');
        for (final l in lines.skip(1)) {
          if (l.isNotEmpty) buf.writeln(l);
        }
      } else if (item is List && item.isNotEmpty) {
        buf.write('$pad-');
        _yamlNode(item, indent + 1, buf, inline: true);
      } else if (item is Map || item is List) {
        buf.writeln('$pad- ${item is Map ? '{}' : '[]'}');
      } else {
        buf.writeln('$pad- ${_yamlScalar(item)}');
      }
    }
  } else {
    buf.writeln(_yamlScalar(v));
  }
}

// ---------------------------------------------------------------------------
// CSV / TSV
// ---------------------------------------------------------------------------

List<List<Object?>> readDelimited(String text, {required bool tab}) {
  final codec = tab ? Csv(fieldDelimiter: '\t', autoDetect: false) : Csv();
  return codec.decode(text).map((r) => r.map((c) => c?.toString()).toList()).toList();
}

String writeDelimited(List<List<Object?>> table, {required bool tab, bool semicolon = false}) {
  final codec = Csv(
    fieldDelimiter: tab ? '\t' : (semicolon ? ';' : ','),
    lineDelimiter: '\r\n',
    // UTF-8 BOM: Excel'in Türkçe karakterleri doğru göstermesi için.
    addBom: !tab,
  );
  return codec.encode([
    for (final r in table) [for (final c in r) c ?? ''],
  ]);
}

// ---------------------------------------------------------------------------
// XML
// ---------------------------------------------------------------------------

Object? readXml(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw ConversionException('Geçersiz XML: ${e.message}');
  }
  final root = doc.rootElement;
  final value = _xmlElement(root);
  // Bu uygulamanın yazdığı <root> sarmalayıcısını geri aç.
  if (root.name.local == 'root') {
    if (value is Map && value.length == 1 && value.containsKey('item')) {
      final item = value['item'];
      return item is List ? item : [item];
    }
    return value;
  }
  return {root.name.local: value};
}

Object? _xmlElement(XmlElement el) {
  final map = <String, Object?>{};
  for (final a in el.attributes) {
    map['@${a.name.local}'] = inferScalar(a.value);
  }
  // Aynı adla tekrar eden alt öğeler listeye dönüştürülür.
  final listKeys = <String>{};
  for (final c in el.childElements) {
    final key = c.name.local;
    final value = _xmlElement(c);
    if (listKeys.contains(key)) {
      (map[key] as List).add(value);
    } else if (map.containsKey(key)) {
      map[key] = [map[key], value];
      listKeys.add(key);
    } else {
      map[key] = value;
    }
  }

  final text = el.children
      .where((n) => n is XmlText || n is XmlCDATA)
      .map((n) => n.value ?? '')
      .join()
      .trim();
  if (map.isEmpty) return text.isEmpty ? null : inferScalar(text);
  if (text.isNotEmpty) map['#text'] = inferScalar(text);
  return map;
}

String writeXml(Object? data) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  if (data is Map && data.length == 1 && data.values.first is Map) {
    // Tek kök öğeli veri: {"katalog": {...}} → <katalog>...</katalog>
    final k = data.keys.first;
    builder.element(_xmlName('$k'), nest: () => _xmlValue(builder, data.values.first));
  } else {
    builder.element('root', nest: () {
      if (data is List) {
        for (final item in data) {
          builder.element('item', nest: () => _xmlValue(builder, item));
        }
      } else {
        _xmlValue(builder, data);
      }
    });
  }
  return '${builder.buildDocument().toXmlString(pretty: true, indent: '  ')}\n';
}

void _xmlValue(XmlBuilder b, Object? v) {
  if (v is Map) {
    v.forEach((k, val) {
      final key = '$k';
      if (key.startsWith('@')) {
        b.attribute(_xmlName(key.substring(1)), val ?? '');
      }
    });
    v.forEach((k, val) {
      final key = '$k';
      if (key.startsWith('@')) return;
      if (key == '#text') {
        b.text('${val ?? ''}');
      } else if (val is List) {
        for (final item in val) {
          b.element(_xmlName(key), nest: () => _xmlValue(b, item));
        }
      } else {
        b.element(_xmlName(key), nest: () => _xmlValue(b, val));
      }
    });
  } else if (v is List) {
    for (final item in v) {
      b.element('item', nest: () => _xmlValue(b, item));
    }
  } else if (v != null) {
    b.text('$v');
  }
}

String _xmlName(String s) {
  var n = s.replaceAll(RegExp(r'[^A-Za-z0-9_.\-çğıöşüÇĞİÖŞÜ]'), '_');
  if (n.isEmpty || RegExp(r'^[0-9.\-]').hasMatch(n) || n.toLowerCase().startsWith('xml')) n = '_$n';
  return n;
}

// ---------------------------------------------------------------------------
// XLSX (harici paket olmadan, OOXML elle okunur/yazılır)
// ---------------------------------------------------------------------------

/// Çalışma kitabındaki tüm sayfaları {sayfaAdı: tablo} olarak okur.
Map<String, List<List<Object?>>> readXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ConversionException('XLSX dosyası açılamadı (bozuk ya da parola korumalı olabilir).');
  }
  String? read(String name) {
    final f = archive.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  XmlDocument? parse(String name) {
    final s = read(name);
    return s == null ? null : XmlDocument.parse(s);
  }

  // Paylaşılan metinler.
  final shared = <String>[];
  final sst = parse('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in sst.rootElement.childElements.where((e) => e.name.local == 'si')) {
      shared.add(si.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((t) => t.innerText).join());
    }
  }

  // Sayfa adları → dosya yolları.
  final workbook = parse('xl/workbook.xml');
  final rels = parse('xl/_rels/workbook.xml.rels');
  if (workbook == null) throw const ConversionException('Geçerli bir Excel dosyası değil.');
  final relTargets = <String, String>{};
  if (rels != null) {
    for (final r in rels.rootElement.childElements) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null) {
        relTargets[id] = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
  }

  final result = <String, List<List<Object?>>>{};
  final sheets = workbook.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sheet').toList();
  for (var i = 0; i < sheets.length; i++) {
    final s = sheets[i];
    final name = s.getAttribute('name') ?? 'Sayfa${i + 1}';
    final rid = s.attributes.where((a) => a.name.local == 'id').firstOrNull?.value ?? '';
    final path = relTargets[rid] ?? 'xl/worksheets/sheet${i + 1}.xml';
    final sheetXml = parse(path);
    if (sheetXml == null) continue;
    result[name] = _readSheet(sheetXml, shared);
  }
  return result;
}

List<List<Object?>> _readSheet(XmlDocument sheet, List<String> shared) {
  final rows = <int, Map<int, Object?>>{};
  var maxCol = -1;
  var autoRow = 0;
  for (final row in sheet.descendants.whereType<XmlElement>().where((e) => e.name.local == 'row')) {
    final rowIndex = (int.tryParse(row.getAttribute('r') ?? '') ?? (autoRow + 1)) - 1;
    autoRow = rowIndex + 1;
    var autoCol = 0;
    for (final c in row.childElements.where((e) => e.name.local == 'c')) {
      final ref = c.getAttribute('r');
      final col = ref != null ? _colIndex(ref) : autoCol;
      autoCol = col + 1;
      final type = c.getAttribute('t');
      final v = c.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText;
      Object? value;
      switch (type) {
        case 's':
          final idx = int.tryParse(v ?? '');
          value = idx != null && idx < shared.length ? shared[idx] : '';
        case 'inlineStr':
          value = c.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((t) => t.innerText).join();
        case 'b':
          value = v == '1';
        case 'str':
        case 'e':
          value = v;
        default:
          value = v == null ? null : (num.tryParse(v) ?? v);
          if (value is double && value == value.truncateToDouble() && value.abs() < 1e15) value = value.toInt();
      }
      if (value != null) {
        (rows[rowIndex] ??= {})[col] = value;
        if (col > maxCol) maxCol = col;
      }
    }
  }
  if (rows.isEmpty) return [];
  final lastRow = rows.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (var r = 0; r <= lastRow; r++) [for (var c = 0; c <= maxCol; c++) rows[r]?[c]],
  ];
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch >= 65 && ch <= 90) {
      n = n * 26 + (ch - 64);
    } else if (ch >= 97 && ch <= 122) {
      n = n * 26 + (ch - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

String _colName(int index) {
  var n = index + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _xe(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Tabloları (sayfa adı → satırlar) XLSX olarak yazar; ilk satır kalın başlık olur.
Uint8List writeXlsx(Map<String, List<List<Object?>>> sheets) {
  final archive = Archive();
  void add(String name, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  final names = <String>[];
  for (final raw in sheets.keys) {
    var n = raw.replaceAll(RegExp(r'[\\/*?:\[\]]'), '_');
    if (n.isEmpty) n = 'Sayfa';
    if (n.length > 31) n = n.substring(0, 31);
    var unique = n;
    var i = 2;
    while (names.contains(unique)) {
      unique = '${n.substring(0, n.length.clamp(0, 28))} $i';
      i++;
    }
    names.add(unique);
  }

  final sheetList = sheets.values.toList();
  for (var s = 0; s < sheetList.length; s++) {
    final rows = sheetList[s];
    final buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    if (rows.isNotEmpty) {
      buf.write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');
    }
    buf.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      buf.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        if (v == null || (v is String && v.isEmpty)) continue;
        final ref = '${_colName(c)}${r + 1}';
        final style = r == 0 ? ' s="1"' : '';
        if (v is num && v.isFinite) {
          buf.write('<c r="$ref"$style><v>$v</v></c>');
        } else if (v is bool) {
          buf.write('<c r="$ref"$style t="b"><v>${v ? 1 : 0}</v></c>');
        } else {
          buf.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_xe('$v')}</t></is></c>');
        }
      }
      buf.write('</row>');
    }
    buf.write('</sheetData></worksheet>');
    add('xl/worksheets/sheet${s + 1}.xml', buf.toString());
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var s = 0; s < sheetList.length; s++) '<Override PartName="/xl/worksheets/sheet${s + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var s = 0; s < names.length; s++) '<sheet name="${_xe(names[s])}" sheetId="${s + 1}" r:id="rId${s + 1}"/>'].join()}'
        '</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var s = 0; s < names.length; s++) '<Relationship Id="rId${s + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${s + 1}.xml"/>'].join()}'
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '</styleSheet>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// ---------------------------------------------------------------------------
// HTML tablo çıktısı
// ---------------------------------------------------------------------------

String writeHtmlTable(List<List<Object?>> table, String title) {
  const esc = HtmlEscape(HtmlEscapeMode.element);
  final buf = StringBuffer();
  for (var r = 0; r < table.length; r++) {
    final tag = r == 0 ? 'th' : 'td';
    buf.writeln('    <tr>${table[r].map((c) => '<$tag>${esc.convert('${c ?? ''}')}</$tag>').join()}</tr>');
  }
  return '''<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<title>${esc.convert(title)}</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: "Segoe UI", system-ui, sans-serif; margin: 2rem; }
  table { border-collapse: collapse; font-size: 14px; }
  th, td { border: 1px solid rgba(127,127,127,.35); padding: .35rem .6rem; text-align: left; }
  th { background: rgba(127,127,127,.15); position: sticky; top: 0; }
  tr:nth-child(even) td { background: rgba(127,127,127,.06); }
</style>
</head>
<body>
  <table>
$buf  </table>
</body>
</html>
''';
}
