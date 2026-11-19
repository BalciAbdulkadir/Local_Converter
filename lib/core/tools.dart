import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'conversion.dart';

/// Uygulamanın kullandığı harici programlar (cwebp, FFmpeg).
/// External programs used by the app (cwebp, FFmpeg).
class ExternalTools {
  const ExternalTools({this.cwebpPath, this.ffmpegPath, this.ffmpegVersion});

  final String? cwebpPath;
  final String? ffmpegPath;
  final String? ffmpegVersion;

  bool get hasCwebp => cwebpPath != null;
  bool get hasFfmpeg => ffmpegPath != null;

  /// Araçları şu sırayla arar:
  /// 1. Uygulamanın asset klasörü (data/flutter_assets/assets)
  /// 2. Uygulama exe'sinin yanı
  /// 3. Çalışma dizinindeki assets/ klasörü (geliştirme / test)
  /// 4. Sistem PATH'i
  static Future<ExternalTools> detect() async {
    final cwebp = await _find('cwebp.exe', 'cwebp');
    final ffmpeg = await _find('ffmpeg.exe', 'ffmpeg');
    String? version;
    if (ffmpeg != null) {
      try {
        final r = await Process.run(ffmpeg, ['-hide_banner', '-version']);
        final firstLine = (r.stdout as String).split('\n').first;
        final m = RegExp(r'ffmpeg version (\S+)').firstMatch(firstLine);
        // "9.0.2-full_build-www.gyan.dev" → "9.0.2"
        version = m?.group(1)?.split('-').first;
      } catch (_) {
        // Sürüm alınamazsa FFmpeg yine de kullanılabilir.
      }
    }
    return ExternalTools(cwebpPath: cwebp, ffmpegPath: ffmpeg, ffmpegVersion: version);
  }

  static Future<String?> _find(String windowsName, String unixName) async {
    final name = Platform.isWindows ? windowsName : unixName;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.join(exeDir, 'data', 'flutter_assets', 'assets', name),
      p.join(exeDir, name),
      p.join(Directory.current.path, 'assets', name),
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }
    // PATH doğrudan taranır. `where` komutunun çıktısı konsol kod sayfasıyla
    // geldiği için Türkçe karakterli yollar (ör. C:\Users\Abdülkadir) bozuluyordu.
    final pathVar = Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      final d = dir.trim().replaceAll('"', '');
      if (d.isEmpty) continue;
      final candidate = p.join(d, name);
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  String requireFfmpeg() {
    final path = ffmpegPath;
    if (path == null) {
      throw const ConversionException(
        'Bu dönüşüm için FFmpeg gerekli. ffmpeg.exe dosyasını uygulama klasörüne '
        'koyun ya da FFmpeg\'i kurup PATH\'e ekleyin.',
      );
    }
    return path;
  }
}

final _durationRe = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)');

/// FFmpeg'i çalıştırır, ilerlemeyi bildirir ve iptal edilirse süreci sonlandırır.
/// Runs FFmpeg, reports progress, and kills the process when cancelled.
Future<void> runFfmpeg(
  ExternalTools tools,
  List<String> args, {
  required CancelToken cancelToken,
  void Function(double progress)? onProgress,
  String? outputPathToCleanUp,
}) async {
  final exe = tools.requireFfmpeg();
  cancelToken.throwIfCancelled();

  final process = await Process.start(exe, [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-progress',
    'pipe:1',
    '-nostats',
    ...args,
  ]);

  void kill() => process.kill();
  cancelToken.addListener(kill);

  double? totalSeconds;
  final stderrTail = <String>[];

  final stderrDone = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
    if (totalSeconds == null) {
      final m = _durationRe.firstMatch(line);
      if (m != null) {
        totalSeconds = int.parse(m.group(1)!) * 3600 +
            int.parse(m.group(2)!) * 60 +
            double.parse(m.group(3)!);
      }
    }
    stderrTail.add(line);
    if (stderrTail.length > 15) stderrTail.removeAt(0);
  });

  final stdoutDone = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
    if (onProgress == null) return;
    if (line.startsWith('out_time_us=') || line.startsWith('out_time_ms=')) {
      // Not: FFmpeg'de out_time_ms de aslında mikrosaniyedir.
      final us = int.tryParse(line.split('=').last);
      final total = totalSeconds;
      if (us != null && total != null && total > 0) {
        onProgress((us / 1e6 / total).clamp(0.0, 1.0));
      }
    } else if (line == 'progress=end') {
      onProgress(1.0);
    }
  });

  final exitCode = await process.exitCode;
  await Future.wait([stderrDone, stdoutDone]);
  cancelToken.removeListener(kill);

  if (cancelToken.isCancelled) {
    if (outputPathToCleanUp != null) {
      try {
        await File(outputPathToCleanUp).delete();
      } catch (_) {}
    }
    throw const ConversionCancelled();
  }
  if (exitCode != 0) {
    if (outputPathToCleanUp != null) {
      try {
        await File(outputPathToCleanUp).delete();
      } catch (_) {}
    }
    final relevant = stderrTail.where((l) => l.trim().isNotEmpty).toList();
    final detail = relevant.length > 4 ? relevant.sublist(relevant.length - 4) : relevant;
    throw ConversionException('FFmpeg hatası (kod $exitCode): ${detail.join(' | ')}');
  }
}
