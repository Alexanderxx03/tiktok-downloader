import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideTimer;
  double _sliderValue = 0.0;
  bool _isDragging = false;
  
  BoxFit _videoFit = BoxFit.contain;
  String _fitLabel = '';
  Timer? _fitLabelTimer;

  void _toggleVideoFit() {
    _fitLabelTimer?.cancel();
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
        _fitLabel = 'Recortar para llenar';
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
        _fitLabel = 'Estirar a pantalla';
      } else {
        _videoFit = BoxFit.contain;
        _fitLabel = 'Ajustar a pantalla';
      }
    });
    
    _fitLabelTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _fitLabel = '';
        });
      }
    });
    _startHideTimer();
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _controller = VideoPlayerController.file(File(widget.filePath));
    try {
      await _controller.initialize();
      await _controller.setVolume(1.0); // Force maximum volume for playback
      setState(() {
        _initialized = true;
      });
      _controller.play();
      _startHideTimer();
      
      // Add listener to update progress slider
      _controller.addListener(() {
        if (mounted && !_isDragging) {
          final duration = _controller.value.duration.inMilliseconds.toDouble();
          final position = _controller.value.position.inMilliseconds.toDouble();
          if (duration > 0) {
            setState(() {
              _sliderValue = (position / duration).clamp(0.0, 1.0);
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _playPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _hideTimer?.cancel();
      } else {
        _controller.play();
        _startHideTimer();
      }
    });
  }

  void _seekRelative(int seconds) {
    final currentPosition = _controller.value.position;
    final targetPosition = currentPosition + Duration(seconds: seconds);
    final duration = _controller.value.duration;

    if (targetPosition < Duration.zero) {
      _controller.seekTo(Duration.zero);
    } else if (targetPosition > duration) {
      _controller.seekTo(duration);
    } else {
      _controller.seekTo(targetPosition);
    }
    _startHideTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fitLabelTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Video Player
              if (_initialized)
                Center(
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: _videoFit,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFE2C55),
                  ),
                ),

              // Fit label indicator (middle of screen)
              if (_fitLabel.isNotEmpty)
                IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF25F4EE).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _fitLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

              // 2. Play/Pause Overlay Animation (Large centered indicator)
              if (_initialized && !_controller.value.isPlaying && !_showControls)
                IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 60,
                      color: Color(0xFF25F4EE),
                    ),
                  ),
                ),

              // 2.5 Double tap seek detectors
              if (_initialized)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () => _seekRelative(-10),
                        behavior: HitTestBehavior.translucent,
                        child: Container(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () => _seekRelative(10),
                        behavior: HitTestBehavior.translucent,
                        child: Container(),
                      ),
                    ),
                  ],
                ),

              // 3. Immersive Overlay Controls
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [
                      // Dark gradient overlays for top and bottom to make text legible
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 80,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 120,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Top Bar (Back Button & Title)
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Color(0xFF25F4EE)),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom Control Panel
                      Positioned(
                        bottom: 20,
                        left: 15,
                        right: 15,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Progress bar & Duration text
                            if (_initialized)
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(_controller.value.position),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 4,
                                        activeTrackColor: const Color(0xFF25F4EE),
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: const Color(0xFFFE2C55),
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        overlayColor: const Color(0xFFFE2C55).withValues(alpha: 0.2),
                                      ),
                                      child: Slider(
                                        value: _sliderValue,
                                        onChanged: (value) {
                                          _startHideTimer();
                                          setState(() {
                                            _isDragging = true;
                                            _sliderValue = value;
                                          });
                                        },
                                        onChangeEnd: (value) async {
                                          final duration = _controller.value.duration.inMilliseconds.toDouble();
                                          final targetPos = Duration(milliseconds: (value * duration).round());
                                          await _controller.seekTo(targetPos);
                                          setState(() {
                                            _isDragging = false;
                                          });
                                          _startHideTimer();
                                        },
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_controller.value.duration),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),

                            // Controls Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Fit screen toggle (BoxFit)
                                IconButton(
                                  icon: const Icon(Icons.aspect_ratio, color: Color(0xFF25F4EE), size: 28),
                                  onPressed: _toggleVideoFit,
                                  tooltip: 'Cambiar escala de video',
                                ),
                                const SizedBox(width: 20),
                                // Rewind 10s
                                IconButton(
                                  icon: const Icon(Icons.replay_10, color: Colors.white, size: 30),
                                  onPressed: () => _seekRelative(-10),
                                ),
                                const SizedBox(width: 20),
                                // Play / Pause
                                GestureDetector(
                                  onTap: _playPause,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFE2C55),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 35,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                // Fast Forward 10s
                                IconButton(
                                  icon: const Icon(Icons.forward_10, color: Colors.white, size: 30),
                                  onPressed: () => _seekRelative(10),
                                ),
                                const SizedBox(width: 20),
                                // Mute / Unmute
                                IconButton(
                                  icon: Icon(
                                    _controller.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _controller.setVolume(_controller.value.volume > 0 ? 0.0 : 1.0);
                                    });
                                    _startHideTimer();
                                  },
                                  tooltip: 'Silenciar/Sonido',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
