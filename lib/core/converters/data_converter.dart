import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../conversion.dart';
import '../data/data_codecs.dart';
import '../document/doc_readers.dart' show decodeText;
import '../formats.dart';
import '../tools.dart';

/// JSON, YAML, CSV, TSV, XML ve XLSX arasında dönüşüm; ayrıca HTML tablo çıktısı.
class DataConverter extends Converter {
  static const formats = {Formats.json, Formats.yaml, Formats.csv, Formats.tsv, Formats.xml, Formats.xlsx};
  static const _tabular = {Formats.csv, Formats.tsv, Formats.xlsx};

  @override
  Set<FileFormat> get inputFormats => formats;

  @override
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools) => {...formats, Formats.html};

  @override
  Future<List<String>> convert(ConversionRequest request, ConversionContext context) async {
    final input = request.inputFormat;
    final target = request.target;
    final bytes = await File(request.input).readAsBytes();
    final semicolon = context.options.csvSemicolon;
    final title = p.basenameWithoutExtension(request.input);
    context.onProgress(0.2);

    final result = await Isolate.run(() => convertData(bytes, input, target, semicolon: semicolon, title: title));
    final out = request.primaryOutputPath();
    if (result is String) {
      await File(out).writeAsString(result);
    } else {
      await File(out).writeAsBytes(result as Uint8List);
    }
    context.onProgress(1);
    return [out];
  }
}

/// Saf dönüşüm fonksiyonu (izolatta çalışır, test edilebilir).
/// Dönüş değeri metin formatları için String, XLSX için Uint8List'tir.
Object convertData(
  Uint8List bytes,
  FileFormat input,
  FileFormat target, {
  bool semicolon = false,
  String title = 'Veri',
}) {
  final inputTabular = DataConverter._tabular.contains(input);
  final targetTabular = DataConverter._tabular.contains(target) || target == Formats.html;

  // Tablo → tablo: ham hücreleri koru (tip dönüşümü yapma).
  if (inputTabular && targetTabular) {
    final sheets = _readSheets(bytes, input);
    final first = sheets.values.isEmpty ? <List<Object?>>[] : sheets.values.first;
    switch (target) {
      case Formats.csv:
        return writeDelimited(first, tab: false, semicolon: semicolon);
      case Formats.tsv:
        return writeDelimited(first, tab: true);
      case Formats.html:
        return writeHtmlTable(first, title);
      case Formats.xlsx:
        return writeXlsx({
          for (final e in sheets.entries)
            e.key: [
              for (final r in e.value) [for (final c in r) c is String ? inferScalar(c) : c],
            ],
        });
    }
  }

  final Object? data;
  switch (input) {
    case Formats.json:
      data = readJson(decodeText(bytes));
    case Formats.yaml:
      data = readYaml(decodeText(bytes));
    case Formats.xml:
      data = readXml(decodeText(bytes));
    case Formats.csv:
    case Formats.tsv:
    case Formats.xlsx:
      final sheets = _readSheets(bytes, input);
      data = sheets.length == 1
          ? fromTable(sheets.values.first)
          : {for (final e in sheets.entries) e.key: fromTable(e.value)};
    default:
      throw ConversionException('${input.id} veri olarak okunamıyor.');
  }

  switch (target) {
    case Formats.json:
      return writeJson(data);
    case Formats.yaml:
      return writeYaml(data);
    case Formats.xml:
      return writeXml(data);
    case Formats.csv:
      return writeDelimited(toTable(data), tab: false, semicolon: semicolon);
    case Formats.tsv:
      return writeDelimited(toTable(data), tab: true);
    case Formats.html:
      return writeHtmlTable(toTable(data), title);
    case Formats.xlsx:
      final isMultiSheet = data is Map && data.length > 1 && data.values.every((v) => v is List);
      return writeXlsx(isMultiSheet
          ? {for (final e in data.entries) '${e.key}': toTable(e.value)}
          : {'Sayfa1': toTable(data)});
    default:
      throw ConversionException('Veri ${target.id} formatına yazılamıyor.');
  }
}

Map<String, List<List<Object?>>> _readSheets(Uint8List bytes, FileFormat format) {
  if (format == Formats.xlsx) return readXlsx(bytes);
  return {'Sayfa1': readDelimited(decodeText(bytes), tab: format == Formats.tsv)};
}
