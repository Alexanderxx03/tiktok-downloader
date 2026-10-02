// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

// Global notifier for theme mode
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() {
  runApp(const TikTokDownloaderApp());
}

class TikTokDownloaderApp extends StatelessWidget {
  const TikTokDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'TikTok Downloader',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF0F0F5),
            primaryColor: const Color(0xFFFE2C55),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFE2C55),
              secondary: Color(0xFF25F4EE),
              surface: Colors.white,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0F0F13),
            primaryColor: const Color(0xFFFE2C55),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFE2C55),
              secondary: Color(0xFF25F4EE),
              surface: Color(0xFF1E1E24),
            ),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
        );
      }
    );
  }
}
