import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/presentation/app_breakpoints.dart';
import '../../shared/presentation/app_colors.dart';
import '../../shared/presentation/app_durations.dart';
import '../../shared/presentation/app_focus_decoration.dart';
import '../../shared/presentation/app_radii.dart';
import '../../shared/presentation/app_spacing.dart';
import '../../shared/presentation/widgets/tv_focusable.dart';
import 'pairing_protocol.dart';
import 'pairing_service.dart';

class PhonePairingDialog extends StatefulWidget {
  const PhonePairingDialog({
    super.key,
    required this.service,
    this.mode = PhonePairingMode.setup,
    this.onInputReceived,
  });

  final PhonePairingService service;
  final PhonePairingMode mode;

  /// Only used in setup mode. The TV remains the sign-in authority.
  final Future<void> Function(PhoneOnboardingInput input)? onInputReceived;

  @override
  State<PhonePairingDialog> createState() => _PhonePairingDialogState();
}

class _PhonePairingDialogState extends State<PhonePairingDialog> {
  StreamSubscription<PairingSnapshot?>? _subscription;
  StreamSubscription<PhoneOnboardingInput>? _inputSubscription;
  PairingConnection? _connection;
  PairingSnapshot? _snapshot;
  PairingServiceFailure? _serviceFailure;
  bool _isStarting = true;
  bool _isChangingApproval = false;
  bool _remoteConnected = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.service.updates.listen(_onSnapshot);
    _inputSubscription = widget.service.onboardingInputs.listen(_receiveInput);
    unawaited(_start());
  }

  void _onSnapshot(PairingSnapshot? snapshot) {
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
    if (widget.mode == PhonePairingMode.remote &&
        snapshot?.phase == PairingPhase.active &&
        !_remoteConnected) {
      _remoteConnected = true;
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputSubscription?.cancel();
    super.dispose();
  }

  Future<void> _receiveInput(PhoneOnboardingInput input) async {
    final onInputReceived = widget.onInputReceived;
    if (onInputReceived == null) return;
    try {
      await onInputReceived(input);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _serviceFailure = PairingServiceFailure.listenerFailed);
    }
  }

  Future<void> _start() async {
    if (!widget.service.isSupported) {
      setState(() {
        _serviceFailure = PairingServiceFailure.unsupportedPlatform;
        _isStarting = false;
      });
      return;
    }
    try {
      final connection = await widget.service.start(mode: widget.mode);
      if (!mounted) {
        await widget.service.stop();
        return;
      }
      setState(() {
        _connection = connection;
        _snapshot = widget.service.snapshot;
        _isStarting = false;
      });
    } on PairingServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _serviceFailure = error.failure;
        _isStarting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serviceFailure = PairingServiceFailure.listenerFailed;
        _isStarting = false;
      });
    }
  }

  Future<void> _approve() async {
    await _changeApproval(widget.service.approve);
  }

  Future<void> _deny() async {
    await _changeApproval(widget.service.deny);
  }

  Future<void> _changeApproval(PairingSnapshot Function() action) async {
    setState(() => _isChangingApproval = true);
    try {
      final snapshot = action();
      if (mounted) setState(() => _snapshot = snapshot);
    } on PairingProtocolException {
      if (mounted) {
        setState(() {
          _serviceFailure = PairingServiceFailure.listenerFailed;
          _snapshot = widget.service.snapshot;
        });
      }
    } finally {
      if (mounted) setState(() => _isChangingApproval = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final isWide = viewport.width >= AppBreakpoints.tablet;
    final dialogWidth = (viewport.width - (isWide ? 96 : 40))
        .clamp(360.0, isWide ? 1180.0 : 720.0)
        .toDouble();
    final qrSize = isWide
        ? (viewport.height * 0.42).clamp(240.0, 420.0).toDouble()
        : (viewport.width * 0.52).clamp(200.0, 300.0).toDouble();

    final content = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildQrPanel(theme, qrSize)),
              SizedBox(width: AppSpacing.xl),
              Expanded(child: _buildDetails(theme)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQrPanel(theme, qrSize),
              const SizedBox(height: AppSpacing.lg),
              _buildDetails(theme),
            ],
          );

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: viewport.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? AppSpacing.xl : AppSpacing.lg),
          child: content,
        ),
      ),
    );
  }

  Widget _buildQrPanel(ThemeData theme, double qrSize) {
    if (_isStarting) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.focus),
          ),
        ),
      );
    }
    if (_serviceFailure case final failure?) {
      return _PairingFailureMessage(failure: failure);
    }
    final connection = _connection;
    if (connection == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: EdgeInsets.all(qrSize >= 320 ? AppSpacing.lg : AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: QrImageView(
          data: connection.qrUri.toString(),
          size: qrSize,
          backgroundColor: Colors.white,
          semanticsLabel: 'QR code to connect a phone to Immich TV',
        ),
      ),
    );
  }

  Widget _buildDetails(ThemeData theme) {
    final phase = _snapshot?.phase;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          widget.mode == PhonePairingMode.remote
              ? 'Use your phone as a remote'
              : 'Set up with your phone',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.mode == PhonePairingMode.remote
              ? 'Scan the code with your phone. Both devices need to be on the same home network. Scanning connects immediately; more than one phone can control this TV.'
              : 'Scan the code with your phone. Both devices need to be on the same home network. Scanning connects immediately, with no approval step.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!_isStarting && _serviceFailure == null)
          _PairingStatus(snapshot: _snapshot),
        if (phase == PairingPhase.approvalPending) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Confirm the code on the phone matches this TV before approving.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PairingButton(
                label: 'Deny',
                icon: Icons.close_rounded,
                onPressed: _deny,
                enabled: !_isChangingApproval,
              ),
              const SizedBox(width: AppSpacing.sm),
              _PairingButton(
                label: 'Approve phone',
                icon: Icons.check_rounded,
                onPressed: _approve,
                enabled: !_isChangingApproval,
                primary: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          widget.mode == PhonePairingMode.remote
              ? 'Commands go directly to this TV over your local network and only work while this app is open. You can revoke phones at any time from Settings.'
              : 'Your setup details go directly to this TV over your local network. Sign-in and profile saving stay on this TV.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PairingButton(
          label: 'Close',
          icon: Icons.close_rounded,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

class _PairingStatus extends StatelessWidget {
  const _PairingStatus({required this.snapshot});

  final PairingSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = snapshot?.phase;
    final (message, color) = switch (phase) {
      PairingPhase.waitingForPhone => (
        'Waiting for a phone to scan…',
        AppColors.textSecondary,
      ),
      PairingPhase.approvalPending => (
        'Phone request. Verify the code, then approve or deny.',
        AppColors.focus,
      ),
      PairingPhase.active => (
        'Phone connected. Continue on the TV.',
        const Color(0xFF80E0B8),
      ),
      PairingPhase.expired => (
        'This pairing request expired. Close and start again.',
        const Color(0xFFFFB36E),
      ),
      PairingPhase.revoked => (
        'This pairing request was closed.',
        AppColors.textSecondary,
      ),
      PairingPhase.stopped ||
      null => ('Pairing is stopped.', AppColors.textSecondary),
    };

    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (snapshot?.verificationCode case final code?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            code,
            semanticsLabel: 'Pairing code $code',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.textPrimary,
              letterSpacing: 7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _PairingFailureMessage extends StatelessWidget {
  const _PairingFailureMessage({required this.failure});

  final PairingServiceFailure failure;

  @override
  Widget build(BuildContext context) {
    final message = switch (failure) {
      PairingServiceFailure.unsupportedPlatform =>
        'Phone pairing is not supported on this platform. Continue with the device keyboard.',
      PairingServiceFailure.noLocalNetwork =>
        'The TV has no usable private IPv4 network address. Connect it to the same Wi-Fi or wired network as your phone, then try again.',
      PairingServiceFailure.companionUnavailable =>
        'Phone setup is not configured for this build. Continue on the TV or contact the app maintainer.',
      PairingServiceFailure.listenerFailed =>
        'The TV could not start its local pairing service. Check the local network permission and try again.',
    };
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _PairingButton extends StatelessWidget {
  const _PairingButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      builder: (_, state) {
        return AnimatedContainer(
          duration: AppDurations.normal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: state.isFocused,
            isActive: state.isActive,
            isSelected: primary,
            backgroundColor: primary
                ? AppColors.primary
                : AppColors.backgroundElevated,
            activeBackgroundColor: primary
                ? AppColors.primary
                : AppColors.surfaceMuted,
            selectedBackgroundColor: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: primary ? AppColors.actionForeground : AppColors.textPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: primary
                      ? AppColors.actionForeground
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
