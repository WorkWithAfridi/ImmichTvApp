import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/authenticated_session.dart';
import '../../../core/models/saved_profile.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/services/review_prompt_service.dart';
import 'app_flow_state.dart';

class AppFlowCubit extends Cubit<AppFlowState> {
  static const _minimumBootstrapDuration = Duration(milliseconds: 1500);

  AppFlowCubit(
    this._authRepository, {
    required ReviewPromptService reviewPromptService,
  }) : _reviewPromptService = reviewPromptService,
       super(const AppFlowState.bootstrap());

  final AuthRepository _authRepository;
  final ReviewPromptService _reviewPromptService;

  Future<void> initialize() async {
    final startedAt = DateTime.now();
    await _recordAppBoot();
    final profiles = await _authRepository.getSavedProfiles();
    final elapsed = DateTime.now().difference(startedAt);
    final remainingDelay = _minimumBootstrapDuration - elapsed;
    if (!remainingDelay.isNegative) {
      await Future<void>.delayed(remainingDelay);
    }
    if (profiles.isEmpty) {
      emit(const AppFlowState.onboarding());
      return;
    }

    emit(AppFlowState.profilePicker(profiles));
  }

  Future<void> completeSignIn(AuthenticatedSession session) async {
    await _recordSuccessfulLogin();
    emit(AppFlowState.home(session, profiles: await _loadProfilesOrFallback()));
  }

  void showOnboarding() {
    emit(AppFlowState.onboarding(profiles: state.profiles));
  }

  void showProfilePicker() {
    emit(AppFlowState.profilePicker(state.profiles));
  }

  Future<void> refreshProfiles() async {
    final profiles = await _authRepository.getSavedProfiles();
    if (profiles.isEmpty) {
      emit(const AppFlowState.onboarding());
      return;
    }

    emit(AppFlowState.profilePicker(profiles));
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    await refreshProfiles();
  }

  Future<List<SavedProfile>> _loadProfilesOrFallback() async {
    try {
      return await _authRepository.getSavedProfiles();
    } catch (_) {
      return state.profiles;
    }
  }

  Future<void> _recordAppBoot() async {
    try {
      await _reviewPromptService.registerAppBoot();
    } catch (_) {}
  }

  Future<void> _recordSuccessfulLogin() async {
    try {
      await _reviewPromptService.registerSuccessfulLogin();
    } catch (_) {}
  }
}
