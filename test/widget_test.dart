import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_downloader/main.dart';
import 'package:tiktok_downloader/screens/splash_screen.dart';

void main() {
  testWidgets('TikTok Downloader UI test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TikTokDownloaderApp());

    // Verify that the splash screen is initially displayed
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Watermark Remover'), findsOneWidget);

    // Pump and settle to let the splash screen finish its animation and transition (2200ms + 600ms)
    await tester.pumpAndSettle(const Duration(milliseconds: 3000));

    // Verify that the title is present in the AppBar
    expect(find.text('TikTok Saver'), findsAtLeast(1));

    // Verify that the download button is present
    expect(find.text('Buscar'), findsOneWidget);

    // Verify that the text field is present
    expect(find.byType(TextField), findsOneWidget);
  });
}
