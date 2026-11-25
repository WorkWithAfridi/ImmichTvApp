import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/presentation/app_colors.dart';
import '../../shared/presentation/app_radii.dart';
import '../../shared/presentation/app_spacing.dart';
import 'pairing_protocol.dart';
import 'pairing_service.dart';

class PhonePairingDialog extends StatefulWidget {
  const PhonePairingDialog({super.key, required this.service});

  final PhonePairingService service;

  @override
  State<PhonePairingDialog> createState() => _PhonePairingDialogState();
}

class _PhonePairingDialogState extends State<PhonePairingDialog> {
  StreamSubscription<PairingSnapshot?>? _subscription;
  PairingConnection? _connection;
  PairingSnapshot? _snapshot;
  PairingServiceFailure? _serviceFailure;
  bool _isStarting = true;
  bool _isChangingApproval = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.service.updates.listen((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(widget.service.stop());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final connection = await widget.service.start();
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
    final phase = _snapshot?.phase;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pair a phone',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Scan this code with a phone on the same home network. The phone can request pairing; this TV must approve it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isStarting)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                )
              else if (_serviceFailure case final failure?)
                _PairingFailureMessage(failure: failure)
              else if (_connection case final connection?) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: QrImageView(
                    data: connection.qrUri.toString(),
                    size: 260,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'QR code to connect a phone to Immich TV',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Or open this address manually:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                for (final uri in connection.manualUris)
                  SelectableText(
                    uri.toString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
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
                      OutlinedButton.icon(
                        onPressed: _isChangingApproval ? null : _deny,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Deny'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: _isChangingApproval ? null : _approve,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Approve phone'),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Pairing preview only. Phone text entry is not enabled yet; you can continue setup with the TV keyboard.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
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
        'Phone approved. Continue setup on the TV.',
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
