import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const LocalConverterApp());
}

class LocalConverterApp extends StatelessWidget {
  const LocalConverterApp({super.key, this.home});

  /// Testlerde farklı bir ana ekran vermek için.
  final Widget? home;

  /// Uygulamanın arayüzünü, temasını ve ana ekranını yapılandırır.
  /// Configures the application's interface, theme, and main screen.
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5B7CFA),
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF16161F));

    return MaterialApp(
      title: 'Local Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(backgroundColor: scheme.surface, elevation: 0, scrolledUnderElevation: 0),
        chipTheme: const ChipThemeData(showCheckmark: false),
      ),
      home: home ?? const HomeScreen(),
    );
  }
}
