import 'package:equatable/equatable.dart';

enum SettingsStatus { idle, loading, saving, failure }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.idle,
    this.profileId,
    this.pinEnabled = false,
    this.isLoaded = false,
    this.errorMessage,
    this.message,
  });

  final SettingsStatus status;
  final String? profileId;
  final bool pinEnabled;
  final bool isLoaded;
  final String? errorMessage;
  final String? message;

  bool get isBusy =>
      status == SettingsStatus.loading || status == SettingsStatus.saving;

  SettingsState copyWith({
    SettingsStatus? status,
    String? profileId,
    bool? pinEnabled,
    bool? isLoaded,
    String? errorMessage,
    String? message,
    bool clearProfileId = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      profileId: clearProfileId ? null : (profileId ?? this.profileId),
      pinEnabled: pinEnabled ?? this.pinEnabled,
      isLoaded: isLoaded ?? this.isLoaded,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    status,
    profileId,
    pinEnabled,
    isLoaded,
    errorMessage,
    message,
  ];
}
