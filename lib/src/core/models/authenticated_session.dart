import 'package:equatable/equatable.dart';

import 'immich_auth_method.dart';
import 'server_capabilities.dart';
import 'server_config.dart';
import 'user_profile.dart';

class AuthenticatedSession extends Equatable {
  const AuthenticatedSession({
    required this.serverConfig,
    required this.accessToken,
    required this.user,
    this.authMethod = ImmichAuthMethod.password,
    this.capabilities = const ServerCapabilities(),
  });

  final ServerConfig serverConfig;
  final String accessToken;
  final UserProfile user;
  final ImmichAuthMethod authMethod;
  final ServerCapabilities capabilities;

  AuthenticatedSession copyWith({ServerCapabilities? capabilities}) {
    return AuthenticatedSession(
      serverConfig: serverConfig,
      accessToken: accessToken,
      user: user,
      authMethod: authMethod,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverConfig': serverConfig.toJson(),
      'accessToken': accessToken,
      'user': user.toJson(),
      'authMethod': authMethod.storageValue,
      'capabilities': capabilities.toJson(),
    };
  }

  factory AuthenticatedSession.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    return AuthenticatedSession(
      serverConfig: ServerConfig.fromJson(
        json['serverConfig'] as Map<String, dynamic>,
      ),
      accessToken: json['accessToken'] as String,
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      authMethod: ImmichAuthMethod.fromStorageValue(
        json['authMethod'] as String?,
      ),
      capabilities:
          rawCapabilities is Map<String, dynamic>
              ? ServerCapabilities.fromJson(rawCapabilities)
              : const ServerCapabilities(),
    );
  }

  @override
  List<Object?> get props => [
    serverConfig,
    accessToken,
    user,
    authMethod,
    capabilities,
  ];
}
