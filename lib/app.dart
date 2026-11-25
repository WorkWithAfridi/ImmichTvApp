import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'src/app_shell.dart';
import 'src/core/config/app_environment.dart';
import 'src/core/network/immich_dio_factory.dart';
import 'src/core/performance/rebuild_metrics.dart';
import 'src/core/repositories/asset_detail_repository.dart';
import 'src/core/repositories/asset_image_repository.dart';
import 'src/core/repositories/auth_repository.dart';
import 'src/core/repositories/hls_session_repository.dart';
import 'src/core/repositories/media_repository.dart';
import 'src/core/repositories/playback_preferences.dart';
import 'src/core/repositories/server_repository.dart';
import 'src/core/services/server_url_normalizer.dart';
import 'src/features/app_flow/cubit/app_flow_cubit.dart';
import 'src/features/app_flow/cubit/app_flow_state.dart';
import 'src/features/auth/data/immich_auth_repository.dart';
import 'src/features/library/data/immich_asset_detail_repository.dart';
import 'src/features/library/data/immich_asset_image_repository.dart';
import 'src/features/library/data/immich_media_repository.dart';
import 'src/features/viewer/data/immich_hls_session_repository.dart';
import 'src/features/mock/data/mock_asset_detail_repository.dart';
import 'src/features/mock/data/mock_auth_repository.dart';
import 'src/features/mock/data/mock_media_repository.dart';
import 'src/features/mock/data/mock_server_repository.dart';
import 'src/features/onboarding/data/immich_server_capabilities_repository.dart';
import 'src/features/onboarding/data/immich_server_repository.dart';
import 'src/features/remote_pairing/pairing_service.dart';
import 'src/features/remote_pairing/pairing_service_factory.dart';
import 'src/features/remote_pairing/remote_command_controller.dart';
import 'src/features/remote_pairing/tv_remote_actions.dart';
import 'src/platform/storage/platform_playback_preferences.dart';
import 'src/platform/storage/platform_profile_storage.dart';
import 'src/shared/presentation/app_colors.dart';
import 'src/shared/presentation/widgets/performance_overlay.dart';
import 'src/shared/presentation/app_radii.dart';

void runImmichTvApp() {
  runApp(ImmichTvApp());
}

class ImmichTvApp extends StatelessWidget {
  ImmichTvApp({
    super.key,
    AuthRepository? authRepository,
    AssetImageRepository? assetImageRepository,
    ServerRepository? serverRepository,
    MediaRepository? mediaRepository,
    AssetDetailRepository? assetDetailRepository,
    PlaybackPreferences? playbackPreferences,
    HlsSessionRepository? hlsSessionRepository,
    PhonePairingService? phonePairingService,
    RemoteActionHandler? remoteActionHandler,
    bool? useMockServices,
  }) : _environment = AppEnvironment(useMockServices: useMockServices ?? false),
       _playbackPreferences =
           playbackPreferences ?? PlatformPlaybackPreferences.shared,
       _hlsSessionRepository =
           hlsSessionRepository ??
           ImmichHlsSessionRepository(dio: ImmichDioFactory.create()),
       _authRepository =
           authRepository ??
           ((useMockServices ?? false)
               ? MockAuthRepository(profileStorage: PlatformProfileStorage())
               : ImmichAuthRepository(
                   dio: ImmichDioFactory.create(),
                   profileStorage: PlatformProfileStorage(),
                   capabilitiesRepository: ImmichServerCapabilitiesRepository(
                     dio: ImmichDioFactory.create(),
                   ),
                 )),
       _serverRepository =
           serverRepository ??
           ((useMockServices ?? false)
               ? MockServerRepository(normalizer: const ServerUrlNormalizer())
               : ImmichServerRepository(
                   dio: ImmichDioFactory.create(),
                   normalizer: const ServerUrlNormalizer(),
                 )),
       _assetDetailRepository =
           assetDetailRepository ??
           ((useMockServices ?? false)
               ? const MockAssetDetailRepository()
               : ImmichAssetDetailRepository(dio: ImmichDioFactory.create())),
       _assetImageRepository =
           assetImageRepository ?? ImmichAssetImageRepository(),
        _phonePairingService =
            phonePairingService ?? createPhonePairingService(),
        _remoteActionHandler = remoteActionHandler,
       _mediaRepository =
           mediaRepository ??
           ((useMockServices ?? false)
               ? MockMediaRepository()
               : ImmichMediaRepository(
                   dio: ImmichDioFactory.create(),
                   playbackPreferences:
                       playbackPreferences ?? PlatformPlaybackPreferences.shared,
                 )) {
    unawaited(_playbackPreferences.load());
  }

  final AppEnvironment _environment;
  final PlaybackPreferences _playbackPreferences;
  final HlsSessionRepository _hlsSessionRepository;
  late final AuthRepository _authRepository;
  late final AssetDetailRepository _assetDetailRepository;
  late final AssetImageRepository _assetImageRepository;
  late final ServerRepository _serverRepository;
  late final MediaRepository _mediaRepository;
  final PhonePairingService _phonePairingService;
  final RemoteActionHandler? _remoteActionHandler;

  @override
  Widget build(BuildContext context) {
    final appRepositories = <RepositoryProvider>[
      RepositoryProvider<AppEnvironment>.value(value: _environment),
      RepositoryProvider<AuthRepository>.value(value: _authRepository),
      RepositoryProvider<AssetImageRepository>.value(
        value: _assetImageRepository,
      ),
      RepositoryProvider<AssetDetailRepository>.value(
        value: _assetDetailRepository,
      ),
      RepositoryProvider<ServerRepository>.value(value: _serverRepository),
      RepositoryProvider<MediaRepository>.value(value: _mediaRepository),
      RepositoryProvider<PlaybackPreferences>.value(
        value: _playbackPreferences,
      ),
      RepositoryProvider<HlsSessionRepository>.value(
        value: _hlsSessionRepository,
      ),
    ];

    final baseTextTheme = GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.0,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1.02,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.05,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        height: 1.08,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.08,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        height: 1.1,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.12,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        height: 1.18,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.05,
        height: 1.2,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.45,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.05,
        height: 1.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        height: 1.2,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        height: 1.2,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
        height: 1.2,
      ),
    );

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.darkTextPrimary,
        secondary: AppColors.immichPurpleLight,
        onSecondary: AppColors.immichPurpleDeep,
        error: AppColors.immichRed,
        onError: AppColors.darkTextPrimary,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.border,
      canvasColor: AppColors.background,
      textTheme: baseTextTheme,
      primaryTextTheme: baseTextTheme,
    );

    return MultiRepositoryProvider(
      providers: appRepositories,
      child: MaterialApp(
        title: 'Immich TV',
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
          cardTheme: baseTheme.cardTheme.copyWith(
            color: AppColors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.surfaceMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.borderStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.focus, width: 2),
            ),
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            hintStyle: const TextStyle(color: AppColors.textMuted),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.borderStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.actionForeground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: AppColors.primary,
            linearTrackColor: AppColors.darkSurfaceSoft,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
          ),
        ),
        home: RebuildMetrics.isEnabled
            ? ImmichPerformanceOverlay(
                child: _AdaptiveAppEntry(
                  authRepository: _authRepository,
                  phonePairingService: _phonePairingService,
                  remoteActionHandler: _remoteActionHandler,
                ),
              )
            : _AdaptiveAppEntry(
                authRepository: _authRepository,
                phonePairingService: _phonePairingService,
                remoteActionHandler: _remoteActionHandler,
              ),
      ),
    );
  }

}

class _AdaptiveAppEntry extends StatelessWidget {
  const _AdaptiveAppEntry({
    required this.authRepository,
    required this.phonePairingService,
    this.remoteActionHandler,
  });

  final AuthRepository authRepository;
  final PhonePairingService phonePairingService;
  final RemoteActionHandler? remoteActionHandler;

  @override
  Widget build(BuildContext context) {
    return _AdaptiveViewportGate(
      authRepository: authRepository,
      phonePairingService: phonePairingService,
      remoteActionHandler: remoteActionHandler,
    );
  }
}

class _AdaptiveViewportGate extends StatefulWidget {
  const _AdaptiveViewportGate({
    required this.authRepository,
    required this.phonePairingService,
    this.remoteActionHandler,
  });

  final AuthRepository authRepository;
  final PhonePairingService phonePairingService;
  final RemoteActionHandler? remoteActionHandler;

  @override
  State<_AdaptiveViewportGate> createState() => _AdaptiveViewportGateState();
}

class _AdaptiveViewportGateState extends State<_AdaptiveViewportGate>
    with WidgetsBindingObserver {
  late final RemotePlaybackRegistry _playbackRegistry;
  late final RemoteCommandController _remoteController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackRegistry = RemotePlaybackRegistry();
    _remoteController = RemoteCommandController(
      service: widget.phonePairingService,
      actions: widget.remoteActionHandler ??
          FocusRemoteActionHandler(_playbackRegistry),
    )..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remoteController.dispose();
    widget.phonePairingService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _remoteController.setAppActive(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _remoteController.setAppActive(false);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _remoteController.setAppActive(false);
        unawaited(widget.phonePairingService.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppFlowCubit(widget.authRepository)..initialize(),
      child: BlocListener<AppFlowCubit, AppFlowState>(
        listener: (context, state) {
          _remoteController.setSurface(
            switch (state.stage) {
              AppStage.bootstrap => RemoteAppSurface.bootstrap,
              AppStage.onboarding => RemoteAppSurface.onboarding,
              AppStage.profilePicker => RemoteAppSurface.home,
              AppStage.home => RemoteAppSurface.home,
            },
          );
        },
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<PhonePairingService>.value(
              value: widget.phonePairingService,
            ),
            RepositoryProvider<RemoteCommandController>.value(
              value: _remoteController,
            ),
            RepositoryProvider<RemotePlaybackRegistry>.value(
              value: _playbackRegistry,
            ),
          ],
          child: const AppShell(),
        ),
      ),
    );
  }
}
