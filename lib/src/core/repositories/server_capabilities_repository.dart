import '../models/authenticated_session.dart';
import '../models/server_capabilities.dart';

abstract class ServerCapabilitiesRepository {
  /// Probes the connected server for version and enabled-feature information.
  ///
  /// Implementations must never throw for an unsupported endpoint: returning
  /// [ServerCapabilities.unknown] keeps sign-in working on older servers.
  Future<ServerCapabilities> fetch(AuthenticatedSession session);
}
