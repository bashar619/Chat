// lib/presentation/chat/media_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:youtube_messenger_app/presentation/chat/video_controller_cache.dart';

class VideoBubble extends StatefulWidget {
  final String url;
  const VideoBubble({Key? key, required this.url}) : super(key: key);

  @override
  _VideoBubbleState createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble>
    with AutomaticKeepAliveClientMixin {
  late final VideoPlayerController _ctrl;
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true; // Keep state alive

  @override
  void initState() {
    super.initState();
    VideoControllerCache.getController(widget.url).then((c) {
      if (!mounted) return;
      _ctrl = c;
      setState(() => _isInitialized = true);
    });
  }

  @override
  void dispose() {
  super.dispose();
  }

  void _togglePlay() {
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isInitialized) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _ctrl.value.aspectRatio,
            child: VideoPlayer(_ctrl),
          ),
          IconButton(
            iconSize: 48,
            icon: Icon(
              _ctrl.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white,
            ),
            onPressed: _togglePlay,
          ),
        ],
      ),
    );
  }
}

/// Full-screen video viewer
class FullScreenVideoPage extends StatefulWidget {
  final String url;
  final Duration initialPosition;
  final bool autoPlay;
  const FullScreenVideoPage({
    Key? key,
    required this.url,
    required this.initialPosition,
    this.autoPlay = false,
  }) : super(key: key);

  @override
  _FullScreenVideoPageState createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  late final VideoPlayerController _ctrl;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        _ctrl.seekTo(widget.initialPosition);
        if (widget.autoPlay) _ctrl.play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);
  void _togglePlay() => setState(() {
        _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            Center(
              child: _ctrl.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _ctrl.value.aspectRatio,
                      child: VideoPlayer(_ctrl),
                    )
                  : const CircularProgressIndicator(),
            ),
            if (_showControls && _ctrl.value.isInitialized) ...[
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Center(
                child: IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  icon: Icon(
                    _ctrl.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: _togglePlay,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  _ctrl,
                  allowScrubbing: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  const AudioBubble({Key? key, required this.url, this.isMe = false})
      : super(key: key);

  @override
  _AudioBubbleState createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  late final AudioPlayer _player;
  Duration _total = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;
  late StreamSubscription<PlayerState> _playerStateSubscription;
  late StreamSubscription<Duration> _durationSubscription;
  late StreamSubscription<Duration> _positionSubscription;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    // Setup listeners with subscription tracking
    _playerStateSubscription = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });

    _durationSubscription = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });

    _positionSubscription = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _loadAudioDuration();
  }

  Future<void> _loadAudioDuration() async {
    try {
      await _player.setSource(UrlSource(widget.url));
      await Future.delayed(const Duration(milliseconds: 100));
      final duration = await _player.getDuration();

      if (duration != null && mounted) {
        setState(() {
          _total = duration;
        });
      }
      await _player.stop();
    } catch (e) {
      // Handle error
    }
  }

  @override
  void dispose() {
    // Cancel all subscriptions first
    _playerStateSubscription.cancel();
    _durationSubscription.cancel();
    _positionSubscription.cancel();

    // Then dispose the player
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).primaryColor;
    final progressColor = Theme.of(context).primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          IconButton(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            iconSize: 28,
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_outline,
              color: iconColor,
            ),
            onPressed: () {
              if (_state == PlayerState.playing) {
                _player.pause();
              } else {
                _player.play(UrlSource(widget.url));
              }
            },
          ),
          const SizedBox(width: 8),
          // Start time
          Text(
            _format(_position),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          // Waveform (static bars for now)
          Expanded(
            child: Container(
              height: 32,
              alignment: Alignment.center,
              child: CustomPaint(
                painter: _WaveformProgressPainter(
                  progress: _total.inMilliseconds == 0
                      ? 0
                      : _position.inMilliseconds / _total.inMilliseconds,
                  playedColor: Theme.of(context).primaryColor,
                  unplayedColor: Colors.grey[300]!,
                ),
                size: const Size(double.infinity, 32),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // End time
          Text(
            _format(_total),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class FullMediaViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const FullMediaViewer({
    Key? key,
    required this.urls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  _FullMediaViewerState createState() => _FullMediaViewerState();
}

class _FullMediaViewerState extends State<FullMediaViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: widget.initialIndex,
      keepPage: true, // Cache pages
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (context, i) {
          final url = widget.urls[i];
          final isVideo = url.toLowerCase().endsWith('.mp4');
          return Center(
            child: isVideo
                ? VideoBubble(key: ValueKey(url), url: url)
                : Image.network(url, fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}

class _WaveformProgressPainter extends CustomPainter {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _WaveformProgressPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = 20;
    final barWidth = size.width / (barCount * 1.5);
    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 1.5 + barWidth / 2;
      final barHeight = size.height * (0.3 + 0.7 * (i % 2 == 0 ? 0.7 : 0.4));
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      final barProgress = (i + 1) / barCount;
      final color = barProgress <= progress ? playedColor : unplayedColor;

      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class VideoRecorderPage extends StatefulWidget {
  final CameraController controller;
  const VideoRecorderPage({Key? key, required this.controller})
      : super(key: key);

  @override
  _VideoRecorderPageState createState() => _VideoRecorderPageState();
}

class _VideoRecorderPageState extends State<VideoRecorderPage> {
  bool _isRecording = false;
  CameraController get _ctrl => widget.controller;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final file = await _ctrl.stopVideoRecording();
      setState(() => _isRecording = false);
      Navigator.of(context).pop(file.path);
    } else {
      await _ctrl.prepareForVideoRecording();
      await _ctrl.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(_ctrl),
          ),
          // Top bar
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Center recording indicator
          if (_isRecording)
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '● REC',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            ),
          // Bottom controls
          SafeArea(
            bottom: true,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: GestureDetector(
                  onTap: _toggleRecording,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.red : Colors.white,
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.videocam,
                      size: 36,
                      color: _isRecording ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
