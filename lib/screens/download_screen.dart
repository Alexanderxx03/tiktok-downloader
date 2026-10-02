import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart'; // Import themeNotifier
import '../services/tiktok_service.dart';
import '../services/cobalt_service.dart';
import '../services/history_service.dart';
import 'video_player_screen.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TikTokService _tiktokService = TikTokService();
  final CobaltService _cobaltService = CobaltService();
  final HistoryService _historyService = HistoryService();

  bool _isLoading = false;
  bool _isSearching = false;
  Map<String, dynamic>? _previewData;
  String? _statusMessage;
  double _downloadProgress = 0.0;
  List<DownloadedVideo> _downloadHistory = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _historyService.getHistory();
    setState(() {
      _downloadHistory = history;
    });
  }

  Future<void> _deleteFromHistory(DownloadedVideo video) async {
    try {
      final file = File(video.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      if (video.thumbnailPath != null) {
        final thumbFile = File(video.thumbnailPath!);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }
    } catch (_) {}

    await _historyService.deleteVideo(video.id);
    _loadHistory();
    _showMessage('Video eliminado del historial', isError: false);
  }

  String _formatDurationSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '0:00';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _getFileSizeString(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes < 1024) return '$bytes B';
        if (bytes < 1024 * 1024)
          return '${(bytes / 1024).toStringAsFixed(1)} KB';
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (_) {}
    return '0.0 MB';
  }

  Future<void> _copyPathToClipboard(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _showMessage('Ruta copiada al portapapeles', isError: false);
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
      });
      _showMessage('Enlace pegado con éxito', isError: false);
    } else {
      _showMessage('No hay texto en el portapapeles');
    }
  }

  Future<void> _shareFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(filePath)],
          text: 'Descargado con TikTok Downloader');
    } else {
      _showMessage('El archivo no existe');
    }
  }

  Future<void> _handleSearch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showMessage('Por favor, pega un enlace de TikTok');
      return;
    }

    setState(() {
      _isSearching = true;
      _previewData = null;
      _statusMessage = 'Buscando video...';
    });

    try {
      final data = await _tiktokService.getVideoDetails(url);
      if (data != null) {
        setState(() {
          _previewData = data;
        });
      }
    } catch (e) {
      _showMessage(
          'Error al buscar: Verifica que el enlace sea válido y público.');
    } finally {
      setState(() {
        _isSearching = false;
        _statusMessage = null;
      });
    }
  }

  Future<void> _handleDownload(
      {bool isAudioOnly = false, bool muteAudio = false}) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showMessage('Por favor, pega un enlace de TikTok');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Procesando...';
      _downloadProgress = 0.0;
    });

    try {
      // 1. Request Permissions
      if (await _requestPermissions()) {
        // We already have the preview data
        final data = _previewData;
        if (data != null) {
          final title = data['title'] ?? 'TikTok Video';

          if (isAudioOnly) {
            setState(() {
              _statusMessage = 'Descargando audio...';
            });
            String? audioUrl;
            if (data['music_info'] != null && data['music_info'] is Map) {
              audioUrl = data['music_info']['play']?.toString();
            } else if (data['music'] != null) {
              audioUrl = data['music'].toString();
            } else if (data['play'] != null) {
              audioUrl = data['play'].toString();
            }

            if (audioUrl == null || audioUrl.isEmpty) {
              _showMessage('No se encontró audio para este video');
              setState(() {
                _isLoading = false;
              });
              return;
            }

            final savedPath = await _tiktokService.downloadAndSaveAudio(
              audioUrl,
              title,
              onProgress: (progress) {
                setState(() {
                  _downloadProgress = progress;
                  _statusMessage = 'Descargando: ${(progress * 100).toInt()}%';
                });
              },
            );

            // Save history
            final recordId = DateTime.now().millisecondsSinceEpoch.toString();
            String thumbPath = '';
            if (data['cover'] != null) {
              try {
                thumbPath = await _tiktokService.downloadAndSaveThumbnail(
                    data['cover'].toString(), recordId);
              } catch (_) {}
            }

            final videoRecord = DownloadedVideo(
              id: recordId,
              title: '$title (Audio)',
              url: url,
              videoUrl: audioUrl,
              filePath: savedPath,
              downloadedAt: DateTime.now(),
              thumbnailPath: thumbPath,
              duration: _formatDurationSeconds(
                  int.tryParse(data['duration']?.toString() ?? '0')),
              fileSize: _getFileSizeString(savedPath),
            );
            await _historyService.addVideo(videoRecord);
            await _loadHistory();
            _showMessage('¡Audio guardado con éxito!', isError: false);
            setState(() {
              _previewData = null;
              _urlController.clear();
              _isLoading = false;
            });
            return;
          }

          // Check if it is a slideshow (images post)
          if (data['images'] != null &&
              data['images'] is List &&
              (data['images'] as List).isNotEmpty) {
            final List<dynamic> imageUrls = data['images'] as List<dynamic>;

            setState(() {
              _statusMessage =
                  'Detectado carrusel de fotos (${imageUrls.length} fotos)...';
            });

            // 1. Download images to temporary files
            List<String> tempImagePaths = [];
            for (int i = 0; i < imageUrls.length; i++) {
              final String imageUrl = imageUrls[i].toString();
              setState(() {
                _statusMessage =
                    'Descargando foto ${i + 1} de ${imageUrls.length}...';
                _downloadProgress = (i + 1) /
                    (imageUrls.length +
                        2); // Save remaining slots for audio and FFmpeg
              });

              try {
                final tempPath = await _tiktokService.downloadToTempFile(
                  imageUrl,
                  'slide_temp',
                  'jpg',
                );
                tempImagePaths.add(tempPath);
              } catch (e) {
                // Continue
              }
            }

            if (tempImagePaths.isEmpty) {
              throw Exception(
                  'No se pudo descargar ninguna imagen del carrusel');
            }

            // 2. Download the audio file to a temporary file
            String? audioUrl;
            double? audioDuration;
            if (data['music_info'] != null && data['music_info'] is Map) {
              final musicInfo = data['music_info'] as Map;
              if (musicInfo['play'] != null) {
                audioUrl = musicInfo['play'].toString();
              }
              if (musicInfo['duration'] != null) {
                audioDuration =
                    double.tryParse(musicInfo['duration'].toString());
              }
            } else if (data['music'] != null && data['music'] is String) {
              audioUrl = data['music'].toString();
            } else if (data['play'] != null && data['play'] is String) {
              audioUrl = data['play'].toString();
            }

            String tempAudioPath = '';
            if (audioUrl != null) {
              setState(() {
                _statusMessage = 'Descargando audio de fondo...';
                _downloadProgress =
                    (imageUrls.length + 1) / (imageUrls.length + 2);
              });
              try {
                tempAudioPath = await _tiktokService.downloadToTempFile(
                  audioUrl,
                  'audio_temp',
                  'mp3',
                );
              } catch (e) {
                // Continue
              }
            }

            // 3. Compile the images and audio into an MP4 video using FFmpeg
            setState(() {
              _statusMessage = 'Generando video del carrusel (procesando)...';
              _downloadProgress = 1.0;
            });

            final String compiledVideoPath =
                await _tiktokService.compileSlideshowToVideo(
              tempImagePaths,
              tempAudioPath.isNotEmpty ? tempAudioPath : null,
              title,
              audioDuration: audioDuration,
            );

            // 4. Clean up temporary files
            for (final path in tempImagePaths) {
              try {
                final file = File(path);
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (_) {}
            }
            if (tempAudioPath.isNotEmpty) {
              try {
                final file = File(tempAudioPath);
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (_) {}
            }

            // 5. Save to history
            final recordId = DateTime.now().millisecondsSinceEpoch.toString();

            // Copy the first image as thumbnail
            String thumbPath = '';
            if (tempImagePaths.isNotEmpty) {
              try {
                final docDir = await getApplicationDocumentsDirectory();
                final thumbFile = File('${docDir.path}/thumb_$recordId.jpg');
                await File(tempImagePaths[0]).copy(thumbFile.path);
                thumbPath = thumbFile.path;
              } catch (_) {}
            }

            final slideDuration = audioDuration != null && audioDuration > 0
                ? audioDuration.round()
                : (imageUrls.length * 3);
            final durationStr = _formatDurationSeconds(slideDuration);

            String sizeStr = '0.0 MB';
            try {
              final compiledFile = File(compiledVideoPath);
              if (await compiledFile.exists()) {
                final bytes = await compiledFile.length();
                sizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
              }
            } catch (_) {}

            final historyRecord = DownloadedVideo(
              id: recordId,
              title: '$title (Carrusel)',
              url: url,
              videoUrl: audioUrl ?? '',
              filePath: compiledVideoPath,
              downloadedAt: DateTime.now(),
              thumbnailPath: thumbPath,
              duration: durationStr,
              fileSize: sizeStr,
            );
            await _historyService.addVideo(historyRecord);
            await _loadHistory();

            _showMessage('¡Carrusel descargado en tu galería!', isError: false);
            setState(() {
              _previewData = null;
              _urlController.clear();
            });
          } else {
            // Standard single Video post
            setState(() {
              _statusMessage = 'Evaluando calidad disponible...';
            });

            String videoUrl;
            String variantLabel;
            try {
              final cobaltDownload =
                  await _cobaltService.getHighestQualityVideo(url);
              videoUrl = cobaltDownload.url;
              variantLabel = 'máxima calidad (Cobalt)';
            } on CobaltException {
              final fallback =
                  await _tiktokService.selectBestVideoVariant(data);
              videoUrl = fallback.url;
              variantLabel = '${fallback.label} (respaldo)';
            }

            setState(() {
              _statusMessage = 'Descargando $variantLabel...';
            });

            // 3. Download and Save
            final savedPath = await _tiktokService.downloadAndSaveVideo(
              videoUrl,
              title,
              muteAudio: muteAudio,
              normalizeAudio: !muteAudio,
              onProgress: (progress) {
                setState(() {
                  _downloadProgress = progress;
                  _statusMessage = 'Descargando: ${(progress * 100).toInt()}%';
                });
              },
            );

            // 4. Save to history
            final recordId = DateTime.now().millisecondsSinceEpoch.toString();

            // Download thumbnail
            String thumbPath = '';
            final coverUrl = data['cover'];
            if (coverUrl != null) {
              try {
                thumbPath = await _tiktokService.downloadAndSaveThumbnail(
                  coverUrl.toString(),
                  recordId,
                );
              } catch (_) {}
            }

            final rawDuration = data['duration'];
            int? durationSec;
            if (rawDuration != null) {
              durationSec = int.tryParse(rawDuration.toString());
            }
            final durationStr = _formatDurationSeconds(durationSec);

            String sizeStr = '0.0 MB';
            try {
              final videoFile = File(savedPath);
              if (await videoFile.exists()) {
                final bytes = await videoFile.length();
                sizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
              }
            } catch (_) {}

            final videoRecord = DownloadedVideo(
              id: recordId,
              title: title,
              url: url,
              videoUrl: videoUrl,
              filePath: savedPath,
              downloadedAt: DateTime.now(),
              thumbnailPath: thumbPath,
              duration: durationStr,
              fileSize: sizeStr,
            );
            await _historyService.addVideo(videoRecord);
            await _loadHistory();

            _showMessage('¡Video guardado con éxito en la galería!',
                isError: false);
            setState(() {
              _previewData = null;
              _urlController.clear();
            });
          }
        }
      } else {
        _showMessage('Se requieren permisos de almacenamiento');
      }
    } catch (e) {
      _showMessage('Error al descargar: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _downloadProgress = 0.0;
      });
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final plugin = DeviceInfoPlugin();
      final androidInfo = await plugin.androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return await Permission.photos.request().isGranted ||
            await Permission.videos.request().isGranted;
      } else {
        return await Permission.storage.request().isGranted;
      }
    }
    return await Permission.photos.request().isGranted;
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError
            ? const Color(0xFFFE2C55)
            : const Color(0xFF25F4EE).withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Widget currentBody = _currentIndex == 0
        ? Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: _buildDownloaderCard(theme, isDark),
            ),
          )
        : _buildHistorySection(theme, isDark);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFE2C55), Color(0xFF25F4EE)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFE2C55).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.cloud_download,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'TikTok Saver',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: isDark ? Colors.amber : Colors.grey.shade800),
            onPressed: () {
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 8),
        ],
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF13131A),
                    const Color(0xFF0F0F13),
                    const Color(0xFF1A1A24)
                  ]
                : [
                    const Color(0xFFF0F0F5),
                    const Color(0xFFFFFFFF),
                    const Color(0xFFE8E8F0)
                  ],
          ),
        ),
        child: SafeArea(
          child: currentBody,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: const Color(0xFFFE2C55),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_download_outlined),
            activeIcon: Icon(Icons.cloud_download),
            label: 'Descargar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library_outlined),
            activeIcon: Icon(Icons.video_library),
            label: 'Descargas',
          ),
        ],
      ),
    );
  }

  Widget _buildDownloaderCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E26).withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFE2C55).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Descargar Videos y Audio',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.bodyLarge?.color,
                letterSpacing: -0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
            decoration: InputDecoration(
              hintText: 'Pega el enlace de TikTok aquí...',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF13131A) : const Color(0xFFF8F8FA),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF2C2C35)
                        : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFFFE2C55), width: 2),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste, color: Color(0xFF25F4EE)),
                tooltip: 'Pegar desde el portapapeles',
                onPressed: _pasteFromClipboard,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_previewData == null)
            ElevatedButton(
              onPressed: _isSearching ? null : _handleSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFE2C55),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
              child: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Buscar',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          if (_previewData != null) ...[
            // Preview Card
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF13131A) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C2C35)
                        : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  if (_previewData!['cover'] != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _previewData!['cover'],
                        width: 60,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 60, height: 80, child: Icon(Icons.image)),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _previewData!['title'] ?? 'Video',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.textTheme.bodyLarge?.color),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${_previewData!['author']?['unique_id'] ?? 'usuario'}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => setState(() => _previewData = null),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleDownload(isAudioOnly: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFE2C55),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Video',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleDownload(
                            isAudioOnly: false, muteAudio: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Sin Audio',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleDownload(isAudioOnly: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25F4EE),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Audio (MP3)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 20),
            Text(
              _statusMessage ?? 'Procesando...',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                backgroundColor:
                    isDark ? const Color(0xFF13131A) : Colors.grey.shade200,
                color: const Color(0xFF25F4EE),
                minHeight: 8,
              ),
            ),
            if (_downloadProgress > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${(_downloadProgress * 100).toInt()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Videos Descargados',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isDark ? const Color(0xFF2C2C35) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_downloadHistory.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF25F4EE)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _downloadHistory.isEmpty
              ? _buildEmptyHistoryPlaceholder()
              : GridView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: _downloadHistory.length,
                  itemBuilder: (context, index) {
                    final video = _downloadHistory[index];
                    return _buildGridHistoryItem(video, theme, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyHistoryPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.video_library_outlined,
          size: 60,
          color: Colors.grey.withOpacity(0.5),
        ),
        const SizedBox(height: 15),
        Text(
          'No hay descargas guardadas',
          style: TextStyle(
              fontSize: 15,
              color: Colors.grey.withOpacity(0.8),
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        Text(
          '¡Los videos que descargues aparecerán aquí!',
          style: TextStyle(fontSize: 12, color: Colors.grey.withOpacity(0.5)),
        ),
      ],
    );
  }

  Widget _buildThumbnail(DownloadedVideo video) {
    if (video.thumbnailPath != null && video.thumbnailPath!.isNotEmpty) {
      final file = File(video.thumbnailPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholderThumbnail(),
        );
      }
    }
    return _buildPlaceholderThumbnail();
  }

  Widget _buildPlaceholderThumbnail() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            Color(0xFF13131A),
            Color(0xFF2C2C35),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.play_circle_outline,
          color: Color(0xFF25F4EE),
          size: 32,
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(DownloadedVideo video) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            '¿Eliminar archivo?',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Se eliminará "${video.title}" permanentemente de la aplicación y de la galería.',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child:
                  const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFE2C55),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteFromHistory(video);
              },
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridHistoryItem(
      DownloadedVideo video, ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () {
        final file = File(video.filePath);
        if (file.existsSync()) {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  VideoPlayerScreen(
                filePath: video.filePath,
                title: video.title,
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                const curve = Curves.easeInOut;
                var tween = Tween(begin: begin, end: end)
                    .chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
            ),
          );
        } else {
          _showMessage(
              'El archivo de video ya no existe en el almacenamiento.');
        }
      },
      onLongPress: () => _copyPathToClipboard(video.filePath),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail wrapper
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(video),
                  // Dark semi-transparent overlay
                  Container(
                    color: Colors.black.withOpacity(0.15),
                  ),
                  // Play button in center
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  // Share button overlay (top left)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: GestureDetector(
                      onTap: () => _shareFile(video.filePath),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25F4EE).withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: const Icon(
                          Icons.share_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  // Delete button overlay (top right)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _showDeleteConfirmDialog(video),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFFE2C55),
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Title text
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 2),
          // Weight (file size) and duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                video.fileSize ?? _getFileSizeString(video.filePath),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 10,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    video.duration ?? '0:00',
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
