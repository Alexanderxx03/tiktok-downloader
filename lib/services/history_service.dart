import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DownloadedVideo {
  final String id;
  final String title;
  final String url;
  final String videoUrl;
  final String filePath;
  final DateTime downloadedAt;
  final String? thumbnailPath;
  final String? duration;
  final String? fileSize;

  DownloadedVideo({
    required this.id,
    required this.title,
    required this.url,
    required this.videoUrl,
    required this.filePath,
    required this.downloadedAt,
    this.thumbnailPath,
    this.duration,
    this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'videoUrl': videoUrl,
      'filePath': filePath,
      'downloadedAt': downloadedAt.toIso8601String(),
      'thumbnailPath': thumbnailPath,
      'duration': duration,
      'fileSize': fileSize,
    };
  }

  factory DownloadedVideo.fromJson(Map<String, dynamic> json) {
    return DownloadedVideo(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      videoUrl: json['videoUrl'] as String,
      filePath: json['filePath'] as String,
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
      duration: json['duration'] as String?,
      fileSize: json['fileSize'] as String?,
    );
  }
}

class HistoryService {
  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/download_history.json');
  }

  Future<List<DownloadedVideo>> getHistory() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        return [];
      }
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents) as List<dynamic>;
      return jsonList
          .map((json) => DownloadedVideo.fromJson(json as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt)); // Newest first
    } catch (e) {
      return [];
    }
  }

  Future<void> saveHistory(List<DownloadedVideo> history) async {
    try {
      final file = await _localFile;
      final jsonList = history.map((video) => video.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> addVideo(DownloadedVideo video) async {
    final history = await getHistory();
    // Prevent duplicate entries of the same video
    history.removeWhere((item) => item.filePath == video.filePath || item.id == video.id);
    history.insert(0, video);
    await saveHistory(history);
  }

  Future<void> deleteVideo(String id) async {
    final history = await getHistory();
    history.removeWhere((item) => item.id == id);
    await saveHistory(history);
  }
}
