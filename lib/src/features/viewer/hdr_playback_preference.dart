import 'package:shared_preferences/shared_preferences.dart';

class HdrPlaybackPreference {
  const HdrPlaybackPreference();

  static const storageKey = 'viewer_hdr_playback_enabled';

  Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(storageKey) ?? false;
  }

  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(storageKey, enabled);
  }
}
