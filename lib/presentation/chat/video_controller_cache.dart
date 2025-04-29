// lib/presentation/chat/video_controller_cache.dart
import 'package:video_player/video_player.dart';

/// A simple global cache of VideoPlayerControllers so they
/// survive any widget rebuilds.
class VideoControllerCache {
  static final Map<String, VideoPlayerController> _cache = {};

  /// Get (or create) a controller for [url].  The first time

  static Future<VideoPlayerController> getController(String url) async {
    if (_cache.containsKey(url)) return _cache[url]!;

    final ctrl = VideoPlayerController.network(url);
    await ctrl.initialize();
    _cache[url] = ctrl;
    return ctrl;
  }

  /// Dispose all controllers (e.g. when leaving the chat screen permanently).
  static Future<void> disposeAll() async {
    for (final c in _cache.values) {
      await c.dispose();
    }
    _cache.clear();
  }
}
