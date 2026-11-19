import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_converter/core/converters/data_converter.dart';
import 'package:local_converter/core/data/data_codecs.dart';
import 'package:local_converter/core/formats.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

const _people = [
  {'ad': 'Ayşe', 'yaş': 30, 'adres': {'şehir': 'İzmir', 'posta': '035'}, 'aktif': true},
  {'ad': 'Çağrı', 'yaş': 25, 'adres': {'şehir': 'Muğla', 'posta': '048'}, 'aktif': false},
];

void main() {
  group('tablo yardımcıları', () {
    test('inferScalar baştaki sıfırları metin olarak bırakır', () {
      expect(inferScalar('42'), 42);
      expect(inferScalar('-3.5'), -3.5);
      expect(inferScalar('007'), '007');
      expect(inferScalar('true'), true);
      expect(inferScalar('abc'), 'abc');
    });

    test('flatten / unflatten simetrik', () {
      final flat = flatten(_people.first);
      expect(flat['adres.şehir'], 'İzmir');
      expect(unflatten(flat), _people.first);
    });

    test('{liste: [...]} kökü tabloya açılır', () {
      final t = toTable({'kisiler': _people});
      expect(t.first, ['ad', 'yaş', 'adres.şehir', 'adres.posta', 'aktif']);
      expect(t.length, 3);
    });
  });

  group('dönüşümler', () {
    final json = jsonEncode(_people);

    test('JSON → CSV → JSON veriyi korur', () {
      final csvText = convertData(_b(json), Formats.json, Formats.csv) as String;
      expect(csvText.startsWith('﻿'), isTrue, reason: 'Excel için BOM');
      expect(csvText, contains('Ayşe'));
      final back = jsonDecode(convertData(_b(csvText), Formats.csv, Formats.json) as String);
      expect(back, _people);
    });

    test('noktalı virgüllü CSV', () {
      final csvText = convertData(_b(json), Formats.json, Formats.csv, semicolon: true) as String;
      expect(csvText.split('\r\n').first, contains(';'));
      final back = jsonDecode(convertData(_b(csvText), Formats.csv, Formats.json) as String);
      expect(back, _people);
    });

    test('JSON → YAML → JSON', () {
      final yamlText = convertData(_b(json), Formats.json, Formats.yaml) as String;
      final back = jsonDecode(convertData(_b(yamlText), Formats.yaml, Formats.json) as String);
      expect(back, _people);
    });

    test('YAML zor metinleri tırnaklar', () {
      final data = {
        'a': 'yes',
        'b': '123',
        'c': ': iki nokta',
        'd': 'satır1\nsatır2',
        'e': '',
        'f': [],
        'g': {},
        'h': [
          [1, 2],
          {'x': null},
        ],
      };
      final yamlText = writeYaml(data);
      expect(readYaml(yamlText), data);
    });

    test('JSON → XML → JSON', () {
      final xmlText = convertData(_b(json), Formats.json, Formats.xml) as String;
      expect(xmlText, contains('<item>'));
      final back = jsonDecode(convertData(_b(xmlText), Formats.xml, Formats.json) as String);
      expect(back, _people);
    });

    test('XML öznitelikleri ve tekrar eden öğeler', () {
      const xml = '<katalog><kitap id="1"><ad>A</ad></kitap><kitap id="2"><ad>B</ad></kitap></katalog>';
      final data = readXml(xml);
      expect(data, {
        'katalog': {
          'kitap': [
            {'@id': 1, 'ad': 'A'},
            {'@id': 2, 'ad': 'B'},
          ],
        },
      });
      expect(readXml(writeXml(data)), data);
    });

    test('JSON → XLSX → JSON', () {
      final xlsx = convertData(_b(json), Formats.json, Formats.xlsx) as Uint8List;
      final back = jsonDecode(convertData(xlsx, Formats.xlsx, Formats.json) as String);
      expect(back, _people);
    });

    test('CSV → XLSX → CSV ham hücreleri korur', () {
      const csvText = 'kod,fiyat,not\r\n007,1.50,"virgül, içeren"\r\n';
      final xlsx = convertData(_b(csvText), Formats.csv, Formats.xlsx) as Uint8List;
      final sheets = readXlsx(xlsx);
      expect(sheets.values.first[1], ['007', 1.5, 'virgül, içeren']);
      final back = convertData(xlsx, Formats.xlsx, Formats.tsv) as String;
      expect(back.split('\r\n')[1], '007\t1.5\tvirgül, içeren');
    });

    test('CSV → HTML tablo', () {
      final html = convertData(_b('a,b\r\n<1>,2\r\n'), Formats.csv, Formats.html) as String;
      expect(html, contains('<th>a</th>'));
      expect(html, contains('&lt;1&gt;'));
    });

    test('geçersiz JSON anlaşılır hata verir', () {
      expect(
        () => convertData(_b('{bozuk'), Formats.json, Formats.yaml),
        throwsA(predicate((e) => e.toString().contains('Geçersiz JSON'))),
      );
    });
  });
}
