import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_converter/core/conversion.dart';
import 'package:local_converter/core/conversion_service.dart';
import 'package:local_converter/core/converter_registry.dart';
import 'package:local_converter/core/formats.dart';
import 'package:local_converter/core/tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late ExternalTools tools;
  final service = ConversionService();

  setUpAll(() async {
    tools = await ExternalTools.detect();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lc_test_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<List<JobUpdate>> run(List<String> inputs, FileFormat target, [ConversionOptions? options]) async {
    final finals = List<JobUpdate?>.filled(inputs.length, null);
    await service.runBatch(
      inputs: inputs,
      target: target,
      options: options ?? const ConversionOptions(),
      tools: tools,
      cancelToken: CancelToken(),
      onUpdate: (i, u) {
        if (u.status != JobStatus.running) finals[i] = u;
      },
    );
    return finals.cast<JobUpdate>();
  }

  String makePng({int w = 400, int h = 300, bool alpha = true}) {
    final image = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(image, x1: 50, y1: 50, x2: 200, y2: 200, color: img.ColorRgba8(220, 40, 40, 255));
    final path = p.join(tmp.path, 'resim.png');
    File(path).writeAsBytesSync(img.encodePng(image));
    return path;
  }

  group('kayıt defteri', () {
    test('ortak hedefler kesişimdir', () {
      final r = ConverterRegistry();
      final outs = r.commonOutputs([Formats.png, Formats.jpg], tools);
      expect(outs, containsAll([Formats.bmp, Formats.pdf]));
      expect(r.commonOutputs([Formats.png, Formats.mp3], tools), isEmpty);
      expect(r.commonOutputs([Formats.csv], tools), contains(Formats.xlsx));
      expect(r.commonOutputs([Formats.pdf], tools), containsAll([Formats.png, Formats.txt, Formats.docx]));
      // MP4 + MOV seçiliyken ikisi de hedef olarak sunulur (yeniden kodlama).
      if (tools.hasFfmpeg) {
        expect(r.commonOutputs([Formats.mp4, Formats.mov], tools), containsAll([Formats.mp4, Formats.mov]));
      }
      expect(r.outputsFor(Formats.docx, tools), isNot(contains(Formats.docx)));
      expect(r.outputsFor(Formats.csv, tools), contains(Formats.csv));
    });

    test('tüm katalog formatları bir dönüştürücü tarafından okunur', () {
      final r = ConverterRegistry();
      for (final f in Formats.all) {
        expect(r.isKnownInput(f), isTrue, reason: f.id);
      }
    });
  });

  group('görsel', () {
    for (final target in [Formats.jpg, Formats.bmp, Formats.gif, Formats.tiff, Formats.tga, Formats.ico]) {
      test('PNG → ${target.id}', () async {
        final src = makePng();
        final [result] = await run([src], target);
        expect(result.status, JobStatus.done, reason: result.error);
        final decoded = img.decodeImage(File(result.outputs.single).readAsBytesSync());
        expect(decoded, isNotNull);
        expect(p.extension(result.outputs.single), '.${target.extension}');
      });
    }

    test('boyutlandırma en-boy oranını korur', () async {
      final src = makePng(w: 1000, h: 500);
      // Aynı formata dönüşüm (PNG → PNG) boyutlandırma için kullanılabilir.
      final [r] = await run([src], Formats.png, const ConversionOptions(maxWidth: 200, maxHeight: 200));
      expect(r.status, JobStatus.done, reason: r.error);
      expect(p.basename(r.outputs.single), 'resim (1).png', reason: 'kaynağın üzerine yazılmaz');
      final out = img.decodeImage(File(r.outputs.single).readAsBytesSync())!;
      expect([out.width, out.height], [200, 100]);
    });

    test('şeffaf PNG → JPG beyaz zemine oturur', () async {
      final src = makePng();
      final [r] = await run([src], Formats.jpg);
      final out = img.decodeImage(File(r.outputs.single).readAsBytesSync())!;
      final px = out.getPixel(5, 5);
      expect(px.r, greaterThan(240));
    });

    test('mevcut çıktının üzerine yazmaz', () async {
      final src = makePng();
      final [a] = await run([src], Formats.bmp);
      final [b] = await run([src], Formats.bmp);
      expect(p.basename(a.outputs.single), 'resim.bmp');
      expect(p.basename(b.outputs.single), 'resim (1).bmp');
    });

    test('birden çok görsel tek PDF\'te birleşir', () async {
      final a = makePng();
      final b = p.join(tmp.path, 'ikinci.png');
      File(a).copySync(b);
      final results = await run([a, b], Formats.pdf, const ConversionOptions(mergeIntoSinglePdf: true));
      expect(results.every((r) => r.status == JobStatus.done), isTrue, reason: results.first.error);
      final out = results.first.outputs.single;
      expect(p.basename(out), 'resim_birlesik.pdf');
      expect(String.fromCharCodes(File(out).readAsBytesSync().sublist(0, 5)), '%PDF-');
    });

    test('PNG → WEBP (cwebp veya FFmpeg)', () async {
      if (!tools.hasCwebp && !tools.hasFfmpeg) return markTestSkipped('cwebp/FFmpeg yok');
      final [r] = await run([makePng()], Formats.webp);
      expect(r.status, JobStatus.done, reason: r.error);
      final bytes = File(r.outputs.single).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
    });

    test('PNG → AVIF → PNG (FFmpeg)', () async {
      if (!tools.hasFfmpeg) return markTestSkipped('FFmpeg yok');
      final [r] = await run([makePng()], Formats.avif);
      expect(r.status, JobStatus.done, reason: r.error);
      final [back] = await run([r.outputs.single], Formats.png);
      expect(back.status, JobStatus.done, reason: back.error);
      expect(img.decodePng(File(back.outputs.single).readAsBytesSync())!.width, 400);
    });
  });

  group('ses / video (FFmpeg)', () {
    late String wav;
    late String video;

    setUp(() async {
      if (!tools.hasFfmpeg) return;
      wav = p.join(tmp.path, 'ton.wav');
      video = p.join(tmp.path, 'klip.mp4');
      await Process.run(tools.ffmpegPath!, ['-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', wav]);
      await Process.run(tools.ffmpegPath!, [
        '-y', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=15',
        '-f', 'lavfi', '-i', 'sine=duration=2', '-shortest', '-pix_fmt', 'yuv420p', video,
      ]);
    });

    for (final target in [Formats.mp3, Formats.flac, Formats.ogg, Formats.m4a, Formats.opus]) {
      test('WAV → ${target.id}', () async {
        if (!tools.hasFfmpeg) return markTestSkipped('FFmpeg yok');
        final progress = <double>[];
        await service.runBatch(
          inputs: [wav],
          target: target,
          options: const ConversionOptions(),
          tools: tools,
          cancelToken: CancelToken(),
          onUpdate: (i, u) {
            if (u.status == JobStatus.failed) fail(u.error!);
            progress.add(u.progress);
          },
        );
        expect(progress.last, 1.0);
        expect(File(p.join(tmp.path, 'ton.${target.extension}')).lengthSync(), greaterThan(1000));
      });
    }

    for (final target in [Formats.webm, Formats.mkv, Formats.avi, Formats.gif, Formats.mp3]) {
      test('MP4 → ${target.id}', () async {
        if (!tools.hasFfmpeg) return markTestSkipped('FFmpeg yok');
        final [r] = await run([video], target, const ConversionOptions(videoMaxHeight: 120));
        expect(r.status, JobStatus.done, reason: r.error);
        expect(File(r.outputs.single).lengthSync(), greaterThan(1000));
      });
    }

    test('iptal FFmpeg sürecini durdurur ve yarım dosyayı siler', () async {
      if (!tools.hasFfmpeg) return markTestSkipped('FFmpeg yok');
      final long = p.join(tmp.path, 'uzun.mp4');
      await Process.run(tools.ffmpegPath!, [
        '-y', '-f', 'lavfi', '-i', 'testsrc=duration=120:size=1280x720:rate=30', '-c:v', 'libx264',
        '-preset', 'ultrafast', long,
      ]);
      final token = CancelToken();
      JobUpdate? last;
      final f = service.runBatch(
        inputs: [long],
        target: Formats.webm,
        options: const ConversionOptions(),
        tools: tools,
        cancelToken: token,
        onUpdate: (i, u) => last = u,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      token.cancel();
      await f;
      expect(last!.status, JobStatus.cancelled);
      expect(File(p.join(tmp.path, 'uzun.webm')).existsSync(), isFalse);
    });
  });
}
