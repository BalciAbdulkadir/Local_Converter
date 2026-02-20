import 'dart:io';
import 'dart:isolate';
import 'package:cross_file/cross_file.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'dart:typed_data';

class ConverterService {
  /// Seçilen dosyaları hedef formata dönüştürür ve ilerleme bilgisi sağlar.
  /// Converts selected files to target format and provides progress information.
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
        } else {
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

  /// Resim dosyasını PDF formatına dönüştürür.
  /// Converts image file to PDF format.
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

  /// Resim baytlarını istenen formata dönüştürür (Isolate içinde çalışır, UI'yi engellemez).
  /// Converts image bytes to desired format (runs in Isolate, doesn't block UI).
  static Uint8List? _convertImageIsolate(Uint8List bytes, String targetFormat) {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return null;

    switch (targetFormat) {
      case 'JPG':
        return img.encodeJpg(decodedImage, quality: 90);
      case 'PNG':
        return img.encodePng(decodedImage);
      case 'BMP':
        return img.encodeBmp(decodedImage);
      default:
        return null;
    }
  }
}
