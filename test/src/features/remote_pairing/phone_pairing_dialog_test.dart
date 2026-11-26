import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service.dart';
import 'package:immichtv/src/features/remote_pairing/phone_pairing_dialog.dart';
import 'package:immichtv/src/features/remote_pairing/remote_command.dart';

void main() {
  late _FakePairingService service;

  setUp(() {
    service = _FakePairingService();
  });

  tearDown(() => service.dispose());

  Future<void> openDialog(WidgetTester tester, PhonePairingMode mode) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvButton(
            onPressed: (context) => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => PhonePairingDialog(service: service, mode: mode),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('setup mode shows the QR and connection status', (tester) async {
    await openDialog(tester, PhonePairingMode.setup);
    expect(find.text('Set up with your phone'), findsOneWidget);
    expect(
      find.bySemanticsLabel('QR code to connect a phone to Immich TV'),
      findsOneWidget,
    );
    expect(find.text('Deny'), findsNothing);

    service.emit(_snapshot(PairingPhase.waitingForPhone));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for your phone…'), findsOneWidget);

    service.emit(_snapshot(PairingPhase.active));
    await tester.pumpAndSettle();
    expect(find.text('Connected. Continue on the TV.'), findsOneWidget);
  });

  testWidgets('TV layout hides the manual link and fits the viewport', (
    tester,
  ) async {
    await openDialog(tester, PhonePairingMode.setup);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    expect(find.text('Or open this pairing link on your phone:'), findsNothing);
    expect(find.bySemanticsLabel('QR code to connect a phone to Immich TV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote mode releases the TV UI once a phone connects', (
    tester,
  ) async {
    await openDialog(tester, PhonePairingMode.remote);
    expect(find.text('Phone remote'), findsOneWidget);
    expect(service.lastStartMode, PhonePairingMode.remote);

    service.emit(_snapshot(PairingPhase.active));
    await tester.pumpAndSettle();
    expect(find.text('Use your phone as a remote'), findsNothing);
  });

  testWidgets('unsupported platform explains how to continue', (tester) async {
    service._isSupported = false;
    await openDialog(tester, PhonePairingMode.remote);
    expect(
      find.textContaining('Phone setup isn’t available here'),
      findsOneWidget,
    );
  });
}

PairingSnapshot _snapshot(PairingPhase phase, {String? code}) => PairingSnapshot(
  sessionId: 'session-1',
  phase: phase,
  expiresAt: DateTime.now().add(const Duration(minutes: 3)),
  verificationCode: code,
);

class TvButton extends StatelessWidget {
  const TvButton({super.key, required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => unawaited(onPressed(context)),
        child: const Text('Open'),
      ),
    );
  }
}

class _FakePairingService implements PhonePairingService {
  final _updates = StreamController<PairingSnapshot?>.broadcast();
  final _commands = StreamController<RemoteCommandRequest>.broadcast();
  final _inputs = StreamController<PhoneOnboardingInput>.broadcast();
  PairingSnapshot? _snapshot;
  bool approved = false;
  bool _isSupported = true;
  PhonePairingMode? lastStartMode;

  @override
  bool get isSupported => _isSupported;

  @override
  PairingSnapshot? get snapshot => _snapshot;

  @override
  Stream<PairingSnapshot?> get updates => _updates.stream;

  @override
  Stream<PhoneOnboardingInput> get onboardingInputs => _inputs.stream;

  @override
  Stream<RemoteCommandRequest> get remoteCommands => _commands.stream;

  @override
  Future<PairingConnection> start({
    PhonePairingMode mode = PhonePairingMode.setup,
  }) async {
    lastStartMode = mode;
    final uri = Uri.parse('https://companion.test/phone/');
    final invitation = PairingInvitation(
      sessionId: 'session-1',
      bootstrapToken: 'token',
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
    );
    return PairingConnection(
      invitation: invitation,
      qrUri: uri,
      manualUris: [uri],
      mode: mode,
    );
  }

  @override
  PairingSnapshot approve() {
    approved = true;
    return _snapshot!;
  }

  @override
  PairingSnapshot deny() => _snapshot!;

  @override
  void resolveRemoteCommand(
    RemoteCommandRequest request,
    RemoteCommandOutcome outcome,
  ) => request.complete(outcome);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _updates.close();
    await _commands.close();
    await _inputs.close();
  }

  void emit(PairingSnapshot? snapshot) {
    _snapshot = snapshot;
    _updates.add(snapshot);
  }
}
