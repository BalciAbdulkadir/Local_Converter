import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_converter/core/formats.dart';
import 'package:local_converter/core/tools.dart';
import 'package:local_converter/main.dart';
import 'package:local_converter/screens/home_screen.dart';
import 'package:local_converter/state/converter_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('lc_widget_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final path = p.join(tmp.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  String png(String name) => write(name, img.encodePng(img.Image(width: 8, height: 8)));

  ConverterController controller() => ConverterController(detectTools: () async => const ExternalTools());

  group('ConverterController', () {
    test('desteklenmeyen ve yinelenen dosyaları ayıklar', () async {
      final c = controller();
      await c.init();
      final a = png('a.png');
      final bad = write('x.exe', [0]);
      final r = c.addPaths([a, a, bad]);
      expect(r.added, 1);
      expect(r.duplicates, 1);
      expect(r.unsupported, ['x.exe']);
    });

    test('klasörleri alt klasörleriyle tarar', () async {
      final c = controller();
      await c.init();
      Directory(p.join(tmp.path, 'alt')).createSync();
      png('a.png');
      png(p.join('alt', 'b.png'));
      write('not.exe', [0]);
      final r = c.addPaths([tmp.path]);
      expect(r.added, 2);
      expect(r.unsupported, isEmpty, reason: 'klasördeki tanınmayan dosyalar sessizce atlanır');
    });

    test('farklı türlerde ortak hedef yoksa liste boştur', () async {
      final c = controller();
      await c.init();
      c.addPaths([png('a.png'), write('v.json', '{}'.codeUnits)]);
      expect(c.availableTargets, isEmpty);
    });

    test('görsel + belge birlikte PDF\'te birleştirilebilir', () async {
      final c = controller();
      await c.init();
      c.addPaths([png('a.png'), write('n.md', '# Başlık'.codeUnits)]);
      expect(c.availableTargets, contains(Formats.pdf));
      c.setTarget(Formats.pdf);
      expect(c.canMerge, isTrue);
    });

    test('FFmpeg yoksa ses dosyaları için uyarı verir', () async {
      final c = controller();
      await c.init();
      c.addPaths([write('s.mp3', [0, 1, 2])]);
      expect(c.missingFfmpeg, isTrue);
      expect(c.availableTargets, isEmpty);
    });
  });

  testWidgets('dosya ekle → hedef seç → dönüştür akışı', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = controller();
    await tester.pumpWidget(LocalConverterApp(home: HomeScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Dosyaları veya klasörleri buraya sürükleyin'), findsOneWidget);
    expect(find.text('Hedef format seçin'), findsOneWidget);

    final src = png('resim.png');
    c.addPaths([src]);
    await tester.pumpAndSettle();
    expect(find.text('resim.png'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'BMP'), findsOneWidget);
    // Aynı formata dönüşüm (boyutlandırma için) de sunulur.
    expect(find.widgetWithText(ChoiceChip, 'PNG'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'BMP'));
    await tester.pumpAndSettle();
    expect(find.text('1 dosyayı BMP formatına dönüştür'), findsOneWidget);

    await tester.runAsync(() => c.start());
    await tester.pumpAndSettle();
    expect(find.text('1 başarılı'), findsOneWidget);
    expect(File(p.join(tmp.path, 'resim.bmp')).existsSync(), isTrue);
  });
}
