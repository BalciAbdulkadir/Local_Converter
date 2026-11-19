import '../conversion.dart';
import '../formats.dart';
import '../tools.dart';

/// Ses ve video dönüşümleri (FFmpeg ile).
class MediaConverter extends Converter {
  static const audioInputs = {
    Formats.mp3, Formats.wav, Formats.flac, Formats.ogg, Formats.m4a,
    Formats.opus, Formats.wma, Formats.aiff,
  };
  static const videoInputs = {
    Formats.mp4, Formats.mkv, Formats.webm, Formats.mov, Formats.avi,
    Formats.flv, Formats.wmv, Formats.mpeg, Formats.threeGp,
  };
  static const audioOutputs = {Formats.mp3, Formats.wav, Formats.flac, Formats.ogg, Formats.m4a, Formats.opus};
  static const videoOutputs = {Formats.mp4, Formats.mkv, Formats.webm, Formats.mov, Formats.avi, Formats.gif};

  @override
  Set<FileFormat> get inputFormats => {...audioInputs, ...videoInputs};

  @override
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools) {
    if (!tools.hasFfmpeg) return {};
    return {
      ...audioOutputs,
      if (videoInputs.contains(input)) ...videoOutputs,
    };
  }

  @override
  Future<List<String>> convert(ConversionRequest request, ConversionContext context) async {
    final out = request.primaryOutputPath();
    final args = buildFfmpegArgs(request.input, out, request.target, context.options);
    await runFfmpeg(
      context.tools,
      args,
      cancelToken: context.cancelToken,
      onProgress: context.onProgress,
      outputPathToCleanUp: out,
    );
    return [out];
  }
}

/// Hedef formata göre FFmpeg argümanlarını oluşturur.
List<String> buildFfmpegArgs(String input, String output, FileFormat target, ConversionOptions o) {
  final br = '${o.audioBitrateKbps}k';
  final q = o.videoQuality.index; // 0 yüksek, 1 orta, 2 düşük
  final scale = o.videoMaxHeight != null ? "scale=-2:'min(${o.videoMaxHeight},ih)'" : null;
  List<String> vf(String? filter) => filter == null ? [] : ['-vf', filter];

  final codec = switch (target) {
    // --- Ses ---
    Formats.mp3 => ['-vn', '-c:a', 'libmp3lame', '-b:a', br],
    Formats.wav => ['-vn', '-c:a', 'pcm_s16le'],
    Formats.flac => ['-vn', '-c:a', 'flac'],
    Formats.ogg => ['-vn', '-c:a', 'libvorbis', '-b:a', br],
    Formats.m4a => ['-vn', '-c:a', 'aac', '-b:a', br],
    Formats.opus => ['-vn', '-c:a', 'libopus', '-b:a', br],
    // --- Video ---
    Formats.mp4 || Formats.mov || Formats.mkv => [
        ...vf(scale),
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '${[18, 23, 28][q]}', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', br,
        if (target == Formats.mp4) ...['-movflags', '+faststart'],
      ],
    Formats.webm => [
        ...vf(scale),
        '-c:v', 'libvpx-vp9', '-crf', '${[28, 33, 38][q]}', '-b:v', '0', '-row-mt', '1', '-deadline', 'good', '-cpu-used', '4',
        '-c:a', 'libopus', '-b:a', br,
      ],
    Formats.avi => [
        ...vf(scale),
        '-c:v', 'mpeg4', '-q:v', '${[3, 5, 8][q]}', '-c:a', 'libmp3lame', '-b:a', br,
      ],
    Formats.gif => [
        '-vf',
        [
          'fps=${o.gifFps}',
          o.videoMaxHeight != null ? "scale=-2:'min(${o.videoMaxHeight},ih)':flags=lanczos" : "scale='min(480,iw)':-2:flags=lanczos",
          'split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4',
        ].join(','),
        '-loop', '0', '-an',
      ],
    _ => throw ConversionException('${target.id} için FFmpeg ayarı yok.'),
  };

  return ['-i', input, ...codec, output];
}
