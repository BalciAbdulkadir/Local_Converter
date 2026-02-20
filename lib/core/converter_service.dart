import 'dart:io';
import 'dart:isolate';
import 'package:cross_file/cross_file.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'dart:typed_data';

class ConverterService {
  Future<void> convertFiles(
    List<XFile> files,
    String targetFormat,
    Function(int current, int total, String message) onProgress,
  ) async {
    int totalFiles = files.length;

    for (int i = 0; i < totalFiles; i++) {
      var xFile = files[i];
      final originalPath = xFile.path;
      final file = File(originalPath);

      if (!await file.exists()) continue;

      onProgress(i, totalFiles, '${xFile.name} işleniyor...');

      final lastDotIndex = originalPath.lastIndexOf('.');
      final pathWithoutExtension = lastDotIndex != -1
          ? originalPath.substring(0, lastDotIndex)
          : originalPath;
      final newPath =
          '${pathWithoutExtension}_converted.${targetFormat.toLowerCase()}';

      try {
        if (targetFormat == 'PDF') {
          await _convertToPdf(file, newPath);
        } else if (targetFormat == 'WEBP') {
          // EXE dosyasını çağırıyoruz (Process.run)
          await _convertToWebpViaProcess(originalPath, newPath);
        } else {
          // PNG ve JPG için klasik Isolate (arka plan) motorumuz
          final bytes = await file.readAsBytes();
          final convertedBytes = await Isolate.run(
            () => _convertImageIsolate(bytes, targetFormat),
          );

          if (convertedBytes != null) {
            await File(newPath).writeAsBytes(convertedBytes);
          } else {
            throw Exception("Dönüştürme motoru boş döndü amk!");
          }
        }

        onProgress(i + 1, totalFiles, '${xFile.name} tamamlandı!');
      } catch (e) {
        onProgress(i + 1, totalFiles, 'HATA - ${xFile.name}: $e');
      }
    }
  }

  // --- HACKER YOLU: cwebp.exe Entegrasyonu ---
  Future<void> _convertToWebpViaProcess(
    String inputPath,
    String outputPath,
  ) async {
    // Flutter derlendikten sonra asset'leri 'data/flutter_assets' içine atar.
    // Windows'ta çalışırken exe'nin tam yolunu dinamik olarak bulmalıyız.
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final exePath = '$executableDir\\data\\flutter_assets\\assets\\cwebp.exe';

    if (!await File(exePath).exists()) {
      throw Exception("cwebp.exe bulunamadı! Yol: $exePath");
    }

    // Terminal komutunu gizlice çalıştır
    final result = await Process.run(exePath, [
      '-q', '80', // Kalite ayarı
      inputPath,
      '-o', outputPath,
    ]);

    if (result.exitCode != 0) {
      throw Exception("WEBP dönüştürme patladı: ${result.stderr}");
    }
  }

  // --- KLASİK METODLAR ---
  Future<void> _convertToPdf(File imageFile, String outputPath) async {
    final pdf = pw.Document();
    final imageBytes = await imageFile.readAsBytes();
    final pdfImage = pw.MemoryImage(imageBytes);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(child: pw.Image(pdfImage));
        },
      ),
    );

    await File(outputPath).writeAsBytes(await pdf.save());
  }

  static Uint8List? _convertImageIsolate(Uint8List bytes, String targetFormat) {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return null;

    switch (targetFormat) {
      case 'JPG':
        return img.encodeJpg(decodedImage, quality: 90);
      case 'PNG':
        return img.encodePng(decodedImage);
      default:
        return null;
    }
  }
}
