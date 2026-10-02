import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class VideoDownloadVariant {
  final String label;
  final String url;
  final int? contentLength;

  const VideoDownloadVariant({
    required this.label,
    required this.url,
    this.contentLength,
  });
}

class TikTokService {
  final Dio _dio = Dio();

  /// Fetches video details from TikWM API
  Future<Map<String, dynamic>?> getVideoDetails(String url) async {
    try {
      final response = await _dio.get(
        'https://www.tikwm.com/api/',
        queryParameters: {
          'url': url,
          'hd': 1,
        },
      );

      if (response.data['code'] == 0) {
        return response.data['data'];
      } else {
        throw Exception(response.data['msg'] ?? 'Error fetching video details');
      }
    } catch (e) {
      rethrow;
    }
  }

  String? _stringValue(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _resolveTikwmUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return 'https://www.tikwm.com$url';
    }
    return 'https://www.tikwm.com/$url';
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  /// Picks the no-watermark variant with the most source data.
  ///
  /// TikWM's `hdplay` label only describes resolution. In motion-heavy videos
  /// it can have a much lower bitrate than `play`, producing visible blocking
  /// despite the larger dimensions. The API-provided sizes are more reliable
  /// than CDN HEAD requests, which frequently omit Content-Length on mobile.
  Future<VideoDownloadVariant> selectBestVideoVariant(
    Map<String, dynamic> data,
  ) async {
    final hdUrl = _stringValue(data['hdplay']);
    final standardUrl = _stringValue(data['play']);
    final hdSize = _intValue(data['hd_size']);
    final standardSize = _intValue(data['size']);

    if (hdUrl != null && standardUrl != null) {
      final useStandard =
          hdSize != null && standardSize != null && standardSize > hdSize;
      if (useStandard) {
        return VideoDownloadVariant(
          label: 'Máximo bitrate sin marca de agua',
          url: _resolveTikwmUrl(standardUrl),
          contentLength: standardSize,
        );
      }
      return VideoDownloadVariant(
        label: 'HD sin marca de agua',
        url: _resolveTikwmUrl(hdUrl),
        contentLength: hdSize,
      );
    }

    if (hdUrl != null) {
      return VideoDownloadVariant(
        label: 'HD sin marca de agua',
        url: _resolveTikwmUrl(hdUrl),
        contentLength: hdSize,
      );
    }

    if (standardUrl != null) {
      return VideoDownloadVariant(
        label: 'Estándar sin marca de agua',
        url: _resolveTikwmUrl(standardUrl),
        contentLength: standardSize,
      );
    }

    final fallbackUrl = _stringValue(data['wmplay']);
    if (fallbackUrl != null) {
      return VideoDownloadVariant(
        label: 'Con marca de agua',
        url: _resolveTikwmUrl(fallbackUrl),
        contentLength: _intValue(data['wm_size']),
      );
    }

    throw Exception('No se encontró una URL de video descargable');
  }

  /// Downloads the video from the given URL and saves it to the gallery
  Future<String> downloadAndSaveVideo(
    String videoUrl,
    String title, {
    void Function(double)? onProgress,
    bool muteAudio = false,
    bool normalizeAudio = true,
  }) async {
    try {
      // 1. Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final fileName = 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final filePath = '${tempDir.path}/$fileName';

      // 2. Download the file
      await _dio.download(
        videoUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      String finalSourcePath = filePath;

      // 2.5 Process audio only when explicitly requested.
      if (muteAudio) {
        final mutedFilePath = '${tempDir.path}/muted_$fileName';
        try {
          // Preserve metadata but drop audio stream
          final command =
              "-i '$filePath' -map 0:v -c copy -map_metadata 0 -movflags use_metadata_tags -y '$mutedFilePath'";
          final session = await FFmpegKit.execute(command);
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            finalSourcePath = mutedFilePath;
          }
        } catch (_) {}
      } else if (normalizeAudio) {
        // Match the perceived loudness of in-app playback while stream-copying
        // the video. Only the audio track is encoded again.
        final normalizedFilePath = '${tempDir.path}/normalized_$fileName';
        try {
          final command = "-i '$filePath' -map 0 -c copy -c:a aac -b:a 256k "
              "-af \"loudnorm=I=-14:TP=-1.0:LRA=11\" -map_metadata 0 "
              "-movflags use_metadata_tags -y '$normalizedFilePath'";
          final session = await FFmpegKit.execute(command);
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            finalSourcePath = normalizedFilePath;
          }
        } catch (_) {}
      }

      // 3. Save to gallery
      try {
        await ImageGallerySaverPlus.saveFile(finalSourcePath);
      } catch (_) {}

      // 4. Copy to permanent documents directory for local playback
      final docDir = await getApplicationDocumentsDirectory();
      final permanentPath = '${docDir.path}/$fileName';
      await File(finalSourcePath).copy(permanentPath);

      // 5. Clean up temporary download files
      try {
        final tempFile = File(filePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (muteAudio) {
          final mutedFile = File('${tempDir.path}/muted_$fileName');
          if (await mutedFile.exists()) {
            await mutedFile.delete();
          }
        } else if (normalizeAudio) {
          final normalizedFile = File('${tempDir.path}/normalized_$fileName');
          if (await normalizedFile.exists()) {
            await normalizedFile.delete();
          }
        }
      } catch (_) {}

      return permanentPath;
    } catch (e) {
      rethrow;
    }
  }

  /// Downloads a file from the given URL to a temporary file path
  Future<String> downloadToTempFile(
    String url,
    String prefix,
    String ext, {
    void Function(double)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}.$ext';
      final filePath = '${tempDir.path}/$fileName';

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  /// Downloads an image from the given URL and saves it to the gallery
  Future<String> downloadAndSaveImage(
    String imageUrl,
    String title, {
    void Function(double)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      String ext = 'jpg';
      if (imageUrl.contains('.png')) ext = 'png';
      if (imageUrl.contains('.webp')) ext = 'webp';

      final fileName =
          'tiktok_img_${DateTime.now().millisecondsSinceEpoch}_${imageUrl.hashCode}.$ext';
      final filePath = '${tempDir.path}/$fileName';

      await _dio.download(
        imageUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      final result = await ImageGallerySaverPlus.saveFile(filePath);

      if (result['isSuccess']) {
        return result['filePath'];
      } else {
        throw Exception('Failed to save image to gallery');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Downloads an audio file from the given URL and saves it to public downloads directory or app storage
  Future<String> downloadAndSaveAudio(
    String audioUrl,
    String title, {
    void Function(double)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      String ext = 'mp3';
      if (audioUrl.contains('.m4a')) ext = 'm4a';
      if (audioUrl.contains('.mp4')) ext = 'm4a';

      // Clean title for a safe filename
      final safeTitle = title
          .replaceAll(RegExp(r'[^\w\s\-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final fileName =
          'tiktok_audio_${DateTime.now().millisecondsSinceEpoch}_$safeTitle.$ext';
      final tempPath = '${tempDir.path}/$fileName';

      // 1. Download to temporary file
      await _dio.download(
        audioUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      // 2. Determine target path and copy the file
      String finalPath = '';
      if (Platform.isAndroid) {
        // Try saving to public Downloads folder first
        final publicDownloadsDir = Directory('/storage/emulated/0/Download');
        if (await publicDownloadsDir.exists()) {
          try {
            finalPath = '${publicDownloadsDir.path}/$fileName';
            await File(tempPath).copy(finalPath);
            return finalPath;
          } catch (e) {
            // Access denied or failed, fallback to external storage dir
          }
        }

        // Fallback to app's external files directory
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final downloadDir = Directory('${extDir.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          finalPath = '${downloadDir.path}/$fileName';
          await File(tempPath).copy(finalPath);
          return finalPath;
        }
      }

      // Fallback for iOS / Desktop / Android if others fail: Application Documents Directory
      final docDir = await getApplicationDocumentsDirectory();
      finalPath = '${docDir.path}/$fileName';
      await File(tempPath).copy(finalPath);
      return finalPath;
    } catch (e) {
      rethrow;
    }
  }

  /// Downloads and saves a thumbnail image to the application documents directory
  Future<String> downloadAndSaveThumbnail(String imageUrl, String id) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final fileName = 'thumb_$id.jpg';
      final filePath = '${docDir.path}/$fileName';

      await _dio.download(imageUrl, filePath);
      return filePath;
    } catch (_) {
      return '';
    }
  }

  /// Preprocesses an image by scaling and padding it to 1080x1920 using FFmpeg.
  Future<String> _preprocessImageForSlideshow(
      String inputPath, int index) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/preprocessed_${index}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Scale to fit 1080x1920 while preserving aspect ratio, and pad with black color to fill remaining space.
      final command =
          "-i '$inputPath' -vf \"scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2\" -y '$outputPath'";

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      }
    } catch (_) {
      // Fallback to original image path if pre-processing fails
    }
    return inputPath;
  }

  /// Compiles a list of image paths and an audio path into a single MP4 video file and saves it to the gallery.
  Future<String> compileSlideshowToVideo(
    List<String> imagePaths,
    String? audioPath,
    String title, {
    double? audioDuration,
  }) async {
    final List<String> preprocessedPaths = [];
    try {
      final tempDir = await getTemporaryDirectory();

      // 1. Pre-process all images to standard 1080x1920
      for (int i = 0; i < imagePaths.length; i++) {
        final processedPath =
            await _preprocessImageForSlideshow(imagePaths[i], i);
        preprocessedPaths.add(processedPath);
      }

      final txtFile = File('${tempDir.path}/slideshow_input.txt');

      // Calculate duration per slide to fit the audio track exactly.
      // Fallback to 3.0 seconds per slide if audioDuration is null/invalid.
      double durationPerSlide = 3.0;
      if (audioDuration != null &&
          audioDuration > 0 &&
          preprocessedPaths.isNotEmpty) {
        durationPerSlide = audioDuration / preprocessedPaths.length;
      }

      // Write the concat input file for FFmpeg.
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < preprocessedPaths.length; i++) {
        sb.writeln("file '${preprocessedPaths[i]}'");
        sb.writeln("duration $durationPerSlide");
      }
      // FFmpeg concat demuxer requires repeating the last file to define its duration
      if (preprocessedPaths.isNotEmpty) {
        sb.writeln("file '${preprocessedPaths.last}'");
      }

      await txtFile.writeAsString(sb.toString());

      final outputFileName =
          'tiktok_slideshow_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final outputPath = '${tempDir.path}/$outputFileName';

      // Run FFmpeg to compile the images and audio.
      // -crf 18 ensures visually lossless high-quality video encoding
      // -preset faster ensures quick compilation on-device
      final String command = audioPath != null && audioPath.isNotEmpty
          ? "-f concat -safe 0 -i '${txtFile.path}' -i '$audioPath' "
              "-c:v libx264 -crf 18 -preset faster -pix_fmt yuv420p -profile:v baseline -level 3.0 "
              "-vf \"scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=30\" "
              "-filter:a \"volume=2.0\" -c:a aac -shortest -y '$outputPath'"
          : "-f concat -safe 0 -i '${txtFile.path}' "
              "-c:v libx264 -crf 18 -preset faster -pix_fmt yuv420p -profile:v baseline -level 3.0 "
              "-vf \"scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=30\" -y '$outputPath'";

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      // Clean up the temporary concat input file
      try {
        if (await txtFile.exists()) {
          await txtFile.delete();
        }
      } catch (_) {}

      if (ReturnCode.isSuccess(returnCode)) {
        // Save the compiled video to the gallery
        try {
          await ImageGallerySaverPlus.saveFile(outputPath);
        } catch (_) {
          // Continue even if gallery saving fails (permission issues, etc.)
        }

        // Copy to permanent documents directory for local playback
        final docDir = await getApplicationDocumentsDirectory();
        final permanentFileName =
            'tiktok_slideshow_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final permanentPath = '${docDir.path}/$permanentFileName';
        await File(outputPath).copy(permanentPath);

        // Clean up temporary compilation file
        try {
          final tempFile = File(outputPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}

        return permanentPath;
      } else {
        final failStackTrace = await session.getFailStackTrace();
        final logs = await session.getLogsAsString();
        throw Exception(
            'FFmpeg compilation failed: $failStackTrace\nLogs: $logs');
      }
    } catch (e) {
      rethrow;
    } finally {
      // Clean up the temporary pre-processed images to save disk space
      for (final path in preprocessedPaths) {
        if (!imagePaths.contains(path)) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
    }
  }
}
