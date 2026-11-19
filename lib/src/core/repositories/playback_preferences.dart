/// Persisted playback options that are not tied to a single saved profile.
abstract class PlaybackPreferences {
  bool get hlsEnabled;

  Future<void> load();

  Future<void> setHlsEnabled(bool enabled);
}
