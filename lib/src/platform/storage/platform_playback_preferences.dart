import 'package:shared_preferences/shared_preferences.dart';

import '../../core/repositories/playback_preferences.dart';

class PlatformPlaybackPreferences implements PlaybackPreferences {
  PlatformPlaybackPreferences();

  /// Shared instance used when no explicit instance is injected.
  static final shared = PlatformPlaybackPreferences();

  static const _hlsEnabledKey = 'immichtv.playback.hls.enabled';

  bool _hlsEnabled = false;

  @override
  bool get hlsEnabled => _hlsEnabled;

  @override
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hlsEnabled = prefs.getBool(_hlsEnabledKey) ?? false;
    } catch (_) {
      // Keep the conservative default when preferences are unavailable.
    }
  }

  @override
  Future<void> setHlsEnabled(bool enabled) async {
    _hlsEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hlsEnabledKey, enabled);
    } catch (_) {
      // The in-memory value still applies for this session.
    }
  }
}
