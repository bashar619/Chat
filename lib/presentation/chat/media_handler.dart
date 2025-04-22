// lib/presentation/chat/media_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:youtube_messenger_app/presentation/chat/Message_bubble.dart';


class VideoBubble extends StatefulWidget {
  final String url;
  const VideoBubble({super.key, required this.url});

  @override
  _VideoBubbleState createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () => _controller.value.isPlaying
          ? _controller.pause()
          : _controller.play(),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }
}

class AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  const AudioBubble({Key? key, required this.url, this.isMe = false}) : super(key: key);

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
    _controller = PageController(initialPage: widget.initialIndex);
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
                ? VideoBubble(url: url)
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