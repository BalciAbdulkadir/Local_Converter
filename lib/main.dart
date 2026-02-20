import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

/// Uygulamayı başlatır.
/// Starts the application.
void main() {
  runApp(const LocalConverterApp());
}

class LocalConverterApp extends StatelessWidget {
  const LocalConverterApp({super.key});

  @override
  /// Uygulamayın arayüzünü, temasını ve ana ekranını yapılandırır.
  /// Configures the application's interface, theme, and main screen.
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const HomeScreen(),
    );
  }
}
