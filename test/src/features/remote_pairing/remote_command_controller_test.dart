import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service.dart';
import 'package:immichtv/src/features/remote_pairing/remote_command.dart';
import 'package:immichtv/src/features/remote_pairing/remote_command_controller.dart';
import 'package:immichtv/src/features/remote_pairing/tv_remote_actions.dart';

void main() {
  late _FakePairingService service;
  late _RecordingActions actions;
  late RemoteCommandController controller;

  final activeSnapshot = PairingSnapshot(
    sessionId: 'session-1',
    phase: PairingPhase.active,
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  setUp(() {
    service = _FakePairingService();
    actions = _RecordingActions();
    controller = RemoteCommandController(
      service: service,
      actions: actions,
      maxCommandsPerSecond: 100,
    )..start();
    service.emit(activeSnapshot);
  });

  tearDown(() {
    controller.dispose();
    service.dispose();
  });

  test('maps allowlisted commands to narrow app-level actions', () async {
    final outcomes = <RemoteCommandOutcome>[];
    final subscription = controller.outcomes.listen(outcomes.add);
    addTearDown(subscription.cancel);

    await _send(
      service,
      _cmd(1, RemoteCommandType.navigate, direction: RemoteDirection.right),
    );
    await _send(
      service,
      _cmd(2, RemoteCommandType.select),
    );
    await _send(
      service,
      _cmd(3, RemoteCommandType.textInput, text: 'hello'),
    );
    await _send(
      service,
      _cmd(4, RemoteCommandType.backspace),
    );
    await _send(
      service,
      _cmd(5, RemoteCommandType.clearText),
    );
    await _send(
      service,
      _cmd(6, RemoteCommandType.submitText),
    );

    expect(actions.calls, [
      'navigate:right',
      'select',
      'textInput:hello',
      'backspace',
      'clearText',
      'submitText',
    ]);
    expect(outcomes.every((o) => o == RemoteCommandOutcome.ok), isTrue);
    expect(service.outcomes.every((o) => o == RemoteCommandOutcome.ok), isTrue);
  });

  test('playback commands reach only a registered target', () async {
    final localService = _FakePairingService();
    addTearDown(localService.dispose);
    localService.emit(activeSnapshot);
    final registry = RemotePlaybackRegistry();
    final playbackController = RemoteCommandController(
      service: localService,
      actions: FocusRemoteActionHandler(registry),
    )..start();
    addTearDown(playbackController.dispose);

    expect(
      await _send(localService, _cmd(1, RemoteCommandType.togglePlayback)),
      RemoteCommandOutcome.unavailable,
    );

    registry.register(_FakePlaybackTarget());
    expect(registry.hasTarget, isTrue);
    expect(registry.togglePlayback(), isTrue);
    expect(registry.seekBy(const Duration(seconds: -10)), isTrue);
  });

  test('rejects commands while backgrounded or in bootstrap', () async {
    controller.setAppActive(false);
    expect(
      await _send(service, _cmd(1, RemoteCommandType.back)),
      RemoteCommandOutcome.unavailable,
    );
    controller.setAppActive(true);

    controller.setSurface(RemoteAppSurface.bootstrap);
    expect(
      await _send(service, _cmd(2, RemoteCommandType.back)),
      RemoteCommandOutcome.unavailable,
    );
    expect(actions.calls, isEmpty);
  });

  test('rejects inactive sessions and session mismatches', () async {
    service.emit(
      PairingSnapshot(
        sessionId: 'session-1',
        phase: PairingPhase.expired,
        expiresAt: DateTime.now(),
      ),
    );
    expect(
      await _send(service, _cmd(1, RemoteCommandType.select)),
      RemoteCommandOutcome.invalid,
    );

    service.emit(activeSnapshot);
    final request = service.createRequest(
      _cmd(2, RemoteCommandType.select),
      sessionId: 'another-session',
    );
    expect(await controller.handle(request), RemoteCommandOutcome.invalid);
    expect(actions.calls, isEmpty);
  });

  test('leaves sequence enforcement to the transport and keeps disconnect terminal', () async {
    final first = await _send(
      service,
      _cmd(1, RemoteCommandType.select),
    );
    expect(first, RemoteCommandOutcome.ok);

    // Multiple phones have independent sequence counters, so the app-level
    // controller must not apply a single global watermark. The transport does
    // the per-client replay and gap checking.
    expect(
      await _send(service, _cmd(1, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
    expect(
      await _send(service, _cmd(3, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
    expect(
      await _send(service, _cmd(2, RemoteCommandType.disconnect)),
      RemoteCommandOutcome.ok,
    );
    expect(
      await _send(service, _cmd(3, RemoteCommandType.select)),
      RemoteCommandOutcome.invalid,
    );
  });

  test('commands continue a setup input sequence without a controller gap', () async {
    service.emit(
      PairingSnapshot(
        sessionId: 'session-1',
        phase: PairingPhase.active,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        lastAcceptedSequence: 1,
      ),
    );
    expect(
      await _send(service, _cmd(2, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
    expect(
      await _send(service, _cmd(1, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
  });

  test('status polls do not re-enable a disconnected session', () async {
    expect(
      await _send(service, _cmd(1, RemoteCommandType.disconnect)),
      RemoteCommandOutcome.ok,
    );
    service.emit(activeSnapshot);
    expect(
      await _send(service, _cmd(2, RemoteCommandType.select)),
      RemoteCommandOutcome.invalid,
    );
  });

  test('accepts commands at any sequence after a session snapshot', () async {
    service.emit(
      PairingSnapshot(
        sessionId: 'session-1',
        phase: PairingPhase.active,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        lastAcceptedSequence: 7,
      ),
    );
    expect(
      await _send(service, _cmd(8, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
    expect(
      await _send(service, _cmd(7, RemoteCommandType.select)),
      RemoteCommandOutcome.ok,
    );
  });

  test('enforces a per-second command budget', () async {
    final localService = _FakePairingService();
    addTearDown(localService.dispose);
    localService.emit(activeSnapshot);
    final limited = RemoteCommandController(
      service: localService,
      actions: actions,
      maxCommandsPerSecond: 1,
    )..start();
    addTearDown(limited.dispose);

    final first = limited.handle(
      localService.createRequest(_cmd(1, RemoteCommandType.select)),
    );
    final second = limited.handle(
      localService.createRequest(_cmd(2, RemoteCommandType.select)),
    );
    expect(await first, RemoteCommandOutcome.ok);
    expect(await second, RemoteCommandOutcome.invalid);
  });

  test('ignored actions still acknowledge the command', () async {
    final localService = _FakePairingService();
    addTearDown(localService.dispose);
    localService.emit(activeSnapshot);
    final ignoring = RemoteCommandController(
      service: localService,
      actions: _RecordingActions(returnsFalse: true),
    )..start();
    addTearDown(ignoring.dispose);
    final request = localService.createRequest(
      _cmd(1, RemoteCommandType.select),
    );
    expect(await ignoring.handle(request), RemoteCommandOutcome.ignored);
  });
}

RemoteCommand _cmd(
  int sequence,
  RemoteCommandType type, {
  RemoteDirection? direction,
  String? text,
  int? seconds,
}) {
  return RemoteCommand.fromJson(<String, Object>{
    'v': 1,
    'type': 'remoteCommand',
    'seq': sequence,
    'command': type.name,
    'direction': ?direction?.name,
    'text': ?text,
    'seconds': ?seconds,
  });
}

Future<RemoteCommandOutcome> _send(
  _FakePairingService service,
  RemoteCommand command,
) {
  return service.createRequest(command).outcome;
}

class _FakePairingService implements PhonePairingService {
  final _updates = StreamController<PairingSnapshot?>.broadcast();
  final _commands = StreamController<RemoteCommandRequest>.broadcast();
  final _inputs = StreamController<PhoneOnboardingInput>.broadcast();
  PairingSnapshot? _snapshot;
  RemoteCommandOutcome? lastResolved;
  final outcomes = <RemoteCommandOutcome>[];

  @override
  bool get isSupported => true;

  @override
  PairingSnapshot? get snapshot => _snapshot;

  @override
  Stream<PairingSnapshot?> get updates => _updates.stream;

  @override
  Stream<PhoneOnboardingInput> get onboardingInputs => _inputs.stream;

  @override
  Stream<RemoteCommandRequest> get remoteCommands => _commands.stream;

  @override
  Future<PairingConnection> start({PhonePairingMode mode = PhonePairingMode.setup}) =>
      Future.error(UnimplementedError());

  @override
  PairingSnapshot approve() => throw UnimplementedError();

  @override
  PairingSnapshot deny() => throw UnimplementedError();

  @override
  void resolveRemoteCommand(
    RemoteCommandRequest request,
    RemoteCommandOutcome outcome,
  ) {
    lastResolved = outcome;
    outcomes.add(outcome);
    request.complete(outcome);
  }

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

  RemoteCommandRequest createRequest(
    RemoteCommand command, {
    String sessionId = 'session-1',
  }) {
    final request = RemoteCommandRequest(
      id: '${command.sequence}-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: sessionId,
      command: command,
    );
    _commands.add(request);
    return request;
  }
}

class _RecordingActions implements RemoteActionHandler {
  _RecordingActions({this.returnsFalse = false});

  final bool returnsFalse;
  final List<String> calls = <String>[];

  bool _record(String value) {
    calls.add(value);
    return !returnsFalse;
  }

  @override
  bool navigate(RemoteDirection direction) => _record('navigate:${direction.name}');

  @override
  bool select() => _record('select');

  @override
  bool back() => _record('back');

  @override
  bool insertText(String text) => _record('textInput:$text');

  @override
  bool backspace() => _record('backspace');

  @override
  bool clearText() => _record('clearText');

  @override
  bool submitText() => _record('submitText');

  @override
  bool togglePlayback() => _record('togglePlayback');

  @override
  bool seekBy(int seconds) => _record('seekBy:$seconds');
}

class _FakePlaybackTarget implements RemotePlaybackTarget {
  @override
  bool get isRemotePlaybackAvailable => true;

  @override
  bool get supportsSeek => true;

  @override
  void togglePlayback() {}

  @override
  void seekBy(Duration delta) {}
}
