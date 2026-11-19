import 'dart:io';

import 'package:flutter/material.dart';

import '../core/formats.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(value < 10 ? 1 : 0);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}

IconData iconForFormat(FileFormat f) {
  if (f == Formats.pdf) return Icons.picture_as_pdf_outlined;
  return switch (f.category) {
    FormatCategory.image => Icons.image_outlined,
    FormatCategory.document => Icons.description_outlined,
    FormatCategory.data => Icons.table_chart_outlined,
    FormatCategory.audio => Icons.audiotrack_outlined,
    FormatCategory.video => Icons.movie_outlined,
  };
}

IconData iconForCategory(FormatCategory c) => switch (c) {
      FormatCategory.image => Icons.image_outlined,
      FormatCategory.document => Icons.description_outlined,
      FormatCategory.data => Icons.table_chart_outlined,
      FormatCategory.audio => Icons.audiotrack_outlined,
      FormatCategory.video => Icons.movie_outlined,
    };

Color colorForCategory(FormatCategory c, ColorScheme scheme) => switch (c) {
      FormatCategory.image => const Color(0xFF4FC3F7),
      FormatCategory.document => const Color(0xFFFFB74D),
      FormatCategory.data => const Color(0xFF81C784),
      FormatCategory.audio => const Color(0xFFBA68C8),
      FormatCategory.video => const Color(0xFFE57373),
    };

/// Dosyayı Windows Gezgini'nde seçili olarak gösterir.
Future<void> revealInExplorer(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    await Process.run('xdg-open', [File(path).parent.path]);
  }
}

/// Dosyayı varsayılan uygulamasıyla açar.
Future<void> openWithDefaultApp(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}
