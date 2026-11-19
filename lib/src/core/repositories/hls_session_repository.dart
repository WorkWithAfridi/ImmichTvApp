/// Best-effort lifecycle handling for Immich's Alpha HLS streaming sessions.
abstract class HlsSessionRepository {
  /// Reads the main playlist and extracts the session id embedded in its
  /// variant URLs. Returns null when the server does not expose one.
  Future<String?> resolveSessionId(
    String mainPlaylistUrl, {
    required Map<String, String> headers,
  });

  /// Releases the server-side resources for a streaming session.
  Future<void> endSession({
    required String mainPlaylistUrl,
    required String sessionId,
    required Map<String, String> headers,
  });
}
