import '../models/authenticated_session.dart';
import '../models/saved_profile.dart';
import '../models/server_config.dart';

abstract class AuthRepository {
  Future<AuthenticatedSession> signIn({
    required ServerConfig serverConfig,
    required String email,
    required String password,
  });

  Future<AuthenticatedSession> signInWithApiKey({
    required ServerConfig serverConfig,
    required String apiKey,
  });

  Future<List<SavedProfile>> getSavedProfiles();

  /// Saves a profile. [pin] is optional; omitting it creates a profile that
  /// can be reopened without entering a PIN.
  Future<void> saveProfile({
    required AuthenticatedSession session,
    String? password,
    String? apiKey,
    String? pin,
  });

  Future<AuthenticatedSession> signInWithSavedProfile({
    required String profileId,
    String? pin,
  });

  /// Enables or disables PIN protection for an existing saved profile.
  /// A new [pin] is required when [enabled] is true.
  Future<void> setProfilePin({
    required String profileId,
    required bool enabled,
    String? pin,
  });

  Future<void> signOut();
}
