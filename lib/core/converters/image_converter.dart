import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../conversion.dart';
import '../formats.dart';
import '../tools.dart';
import 'pdf_writer.dart';

/// Görsel → görsel ve görsel → PDF dönüşümleri. Aynı formata dönüşüm de
/// desteklenir (ör. PNG → PNG boyutlandırma, JPG → JPG yeniden sıkıştırma).
/// Image → image and image → PDF conversions.
class ImageConverter extends Converter {
  /// `image` paketinin doğrudan çözebildiği formatlar.
  static const nativeInputs = {
    Formats.png, Formats.jpg, Formats.webp, Formats.bmp, Formats.gif,
    Formats.tiff, Formats.tga, Formats.ico, Formats.psd,
  };

  /// Yalnızca FFmpeg ile çözülebilen formatlar.
  static const ffmpegInputs = {Formats.avif, Formats.heic};

  /// `image` paketinin doğrudan yazabildiği formatlar.
  static const nativeOutputs = {
    Formats.png, Formats.jpg, Formats.bmp, Formats.gif,
    Formats.tiff, Formats.tga, Formats.ico,
  };

  @override
  Set<FileFormat> get inputFormats => {...nativeInputs, ...ffmpegInputs};

  @override
  Set<FileFormat> outputFormatsFor(FileFormat input, ExternalTools tools) {
    if (ffmpegInputs.contains(input) && !tools.hasFfmpeg) return {};
    return {
      ...nativeOutputs,
      if (tools.hasCwebp || tools.hasFfmpeg) Formats.webp,
      if (tools.hasFfmpeg) Formats.avif,
      Formats.pdf,
    };
  }

  @override
  Future<List<String>> convert(ConversionRequest request, ConversionContext context) async {
    final target = request.target;
    final options = context.options;
    final bytes = await loadImageBytes(request.input, context);
    context.cancelToken.throwIfCancelled();
    context.onProgress(0.3);

    if (target == Formats.pdf) {
      final out = request.primaryOutputPath();
      await writeImagesToPdf([bytes], out, options.pdfPageSize, options.maxWidth, options.maxHeight);
      return [out];
    }

    final out = request.primaryOutputPath();
    final spec = ImageEncodeSpec(
      // WEBP ve AVIF önce kayıpsız PNG'ye çevrilip harici araca verilir.
      format: nativeOutputs.contains(target) ? target.id : 'PNG',
      quality: options.imageQuality,
      maxWidth: options.maxWidth,
      maxHeight: options.maxHeight,
    );
    final encoded = await Isolate.run(() => decodeAndEncode(bytes, spec));
    context.cancelToken.throwIfCancelled();
    context.onProgress(0.7);

    if (nativeOutputs.contains(target)) {
      await File(out).writeAsBytes(encoded);
    } else {
      await encodeWithExternalTool(encoded, out, target, context);
    }
    context.onProgress(1);
    return [out];
  }

  /// Görsel dosyasını okur; AVIF/HEIC ise önce FFmpeg ile PNG'ye çevirir.
  static Future<Uint8List> loadImageBytes(String path, ConversionContext context) async {
    final format = Formats.fromPath(path);
    if (!ffmpegInputs.contains(format)) return File(path).readAsBytes();

    final tmpDir = await Directory.systemTemp.createTemp('lc_img_');
    try {
      final tmp = p.join(tmpDir.path, 'decoded.png');
      await runFfmpeg(
        context.tools,
        ['-i', path, '-frames:v', '1', '-update', '1', tmp],
        cancelToken: context.cancelToken,
      );
      return await File(tmp).readAsBytes();
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  /// PNG verisini cwebp veya FFmpeg ile WEBP/AVIF'e çevirir.
  static Future<void> encodeWithExternalTool(
    Uint8List png,
    String out,
    FileFormat target,
    ConversionContext context,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('lc_img_');
    try {
      final tmp = p.join(tmpDir.path, 'source.png');
      await File(tmp).writeAsBytes(png);
      final q = context.options.imageQuality;

      if (target == Formats.webp && context.tools.hasCwebp) {
        final r = await Process.run(context.tools.cwebpPath!, ['-quiet', '-q', '$q', tmp, '-o', out]);
        if (r.exitCode != 0) {
          throw ConversionException('cwebp hatası: ${r.stderr}'.trim());
        }
      } else if (target == Formats.webp) {
        await runFfmpeg(
          context.tools,
          ['-i', tmp, '-c:v', 'libwebp', '-quality', '$q', '-frames:v', '1', out],
          cancelToken: context.cancelToken,
          outputPathToCleanUp: out,
        );
      } else if (target == Formats.avif) {
        // Kalite (1-100) → AV1 CRF (63-0).
        final crf = (63 - (q / 100 * 63)).round().clamp(0, 63);
        await runFfmpeg(
          context.tools,
          [
            '-i', tmp, '-c:v', 'libaom-av1', '-still-picture', '1', '-cpu-used', '6',
            '-crf', '$crf', '-pix_fmt', 'yuv420p', '-frames:v', '1', out,
          ],
          cancelToken: context.cancelToken,
          outputPathToCleanUp: out,
        );
      } else {
        throw ConversionException('${target.id} için kodlayıcı yok.');
      }
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }
}

/// İzolatlar arasında taşınabilen kodlama ayarları.
class ImageEncodeSpec {
  const ImageEncodeSpec({required this.format, required this.quality, this.maxWidth, this.maxHeight});
  final String format;
  final int quality;
  final int? maxWidth;
  final int? maxHeight;
}

/// Ham görsel verisini çözer, boyutlandırır ve hedef formatta kodlar.
/// Arayüzü dondurmamak için izolat içinde çağrılmalıdır.
Uint8List decodeAndEncode(Uint8List bytes, ImageEncodeSpec spec) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ConversionException('Görsel okunamadı; dosya bozuk ya da desteklenmeyen bir alt türde olabilir.');
  }
  return encodeImage(decoded, spec);
}

/// Çözülmüş bir görseli [spec]'e göre kodlar.
Uint8List encodeImage(img.Image source, ImageEncodeSpec spec) {
  final keepAnimation = spec.format == 'GIF' && source.numFrames > 1;
  var image = keepAnimation ? source : img.Image.from(source, noAnimation: true);
  image = img.bakeOrientation(image);
  image = resizeToFit(image, spec.maxWidth, spec.maxHeight);

  switch (spec.format) {
    case 'JPG':
      return img.encodeJpg(flattenOnWhite(image), quality: spec.quality.clamp(1, 100));
    case 'PNG':
      return img.encodePng(image);
    case 'BMP':
      return img.encodeBmp(image);
    case 'GIF':
      return img.encodeGif(image);
    case 'TIFF':
      return img.encodeTiff(image, singleFrame: true);
    case 'TGA':
      return img.encodeTga(image);
    case 'ICO':
      // ICO en fazla 256x256 olabilir.
      return img.encodeIco(resizeToFit(image, 256, 256), singleFrame: true);
    default:
      throw ConversionException('Desteklenmeyen görsel formatı: ${spec.format}');
  }
}

/// En-boy oranını koruyarak görseli verilen sınırlara sığdırır (büyütmez).
img.Image resizeToFit(img.Image image, int? maxWidth, int? maxHeight) {
  final mw = maxWidth ?? image.width;
  final mh = maxHeight ?? image.height;
  if (image.width <= mw && image.height <= mh) return image;
  final scale = [mw / image.width, mh / image.height].reduce((a, b) => a < b ? a : b);
  return img.copyResize(
    image,
    width: (image.width * scale).round().clamp(1, 1 << 20),
    height: (image.height * scale).round().clamp(1, 1 << 20),
    interpolation: img.Interpolation.average,
  );
}

/// Şeffaf pikselleri beyaz zemine yerleştirir (JPG şeffaflık desteklemez).
img.Image flattenOnWhite(img.Image image) {
  if (!image.hasAlpha) return image;
  final bg = img.Image(width: image.width, height: image.height, numChannels: 3);
  img.fill(bg, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(bg, image);
}
