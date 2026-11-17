import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/repositories/auth_repository.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required AuthRepository authRepository,
    required AuthenticatedSession session,
  }) : _authRepository = authRepository,
       _session = session,
       super(const SettingsState());

  final AuthRepository _authRepository;
  final AuthenticatedSession _session;

  Future<void> load() async {
    emit(state.copyWith(status: SettingsStatus.loading, clearError: true));
    try {
      final profiles = await _authRepository.getSavedProfiles();
      for (final profile in profiles) {
        if (profile.email.toLowerCase() == _session.user.email.toLowerCase() &&
            profile.serverConfig.serverUrl.toString() ==
                _session.serverConfig.serverUrl.toString()) {
          emit(
            state.copyWith(
              status: SettingsStatus.idle,
              profileId: profile.id,
              pinEnabled: profile.pinEnabled,
              isLoaded: true,
            ),
          );
          return;
        }
      }
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          isLoaded: true,
          errorMessage: 'This profile is no longer saved on this device.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          isLoaded: true,
          errorMessage: _messageFor(error),
        ),
      );
    }
  }

  Future<bool> setPinEnabled(bool enabled, {String? pin}) async {
    final profileId = state.profileId;
    if (profileId == null) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          errorMessage: 'This profile is no longer saved on this device.',
        ),
      );
      return false;
    }

    emit(state.copyWith(status: SettingsStatus.saving, clearError: true));
    try {
      await _authRepository.setProfilePin(
        profileId: profileId,
        enabled: enabled,
        pin: pin,
      );
      emit(
        state.copyWith(
          status: SettingsStatus.idle,
          pinEnabled: enabled,
          clearMessage: true,
          message: enabled ? 'PIN protection is on.' : 'PIN protection is off.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          errorMessage: _messageFor(error),
        ),
      );
      return false;
    }
  }

  void clearMessage() {
    if (state.message != null || state.errorMessage != null) {
      emit(state.copyWith(clearMessage: true, clearError: true));
    }
  }

  String _messageFor(Object error) {
    return error is AppException
        ? error.message
        : 'We could not update this setting right now.';
  }
}
