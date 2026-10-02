import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_downloader/services/tiktok_service.dart';

void main() {
  group('TikTokService.selectBestVideoVariant', () {
    final service = TikTokService();

    test('prefers the higher-bitrate standard variant for motion', () async {
      final variant = await service.selectBestVideoVariant({
        'hdplay': '/video-hd.mp4',
        'hd_size': 1000,
        'play': '/video-standard.mp4',
        'size': 2000,
      });

      expect(variant.label, 'Máximo bitrate sin marca de agua');
      expect(variant.url, 'https://www.tikwm.com/video-standard.mp4');
      expect(variant.contentLength, 2000);
    });

    test('prefers HD when it contains at least as much source data', () async {
      final variant = await service.selectBestVideoVariant({
        'hdplay': '/video-hd.mp4',
        'hd_size': 3000,
        'play': '/video-standard.mp4',
        'size': 2000,
      });

      expect(variant.label, 'HD sin marca de agua');
      expect(variant.url, 'https://www.tikwm.com/video-hd.mp4');
      expect(variant.contentLength, 3000);
    });

    test('falls back to the standard no-watermark variant', () async {
      final variant = await service.selectBestVideoVariant({
        'play': 'https://cdn.example.com/video.mp4',
        'size': '2048',
      });

      expect(variant.label, 'Estándar sin marca de agua');
      expect(variant.url, 'https://cdn.example.com/video.mp4');
      expect(variant.contentLength, 2048);
    });

    test('uses the watermarked variant only as a last resort', () async {
      final variant = await service.selectBestVideoVariant({
        'wmplay': '/video-watermarked.mp4',
        'wm_size': 4096,
      });

      expect(variant.label, 'Con marca de agua');
      expect(variant.contentLength, 4096);
    });
  });
}
