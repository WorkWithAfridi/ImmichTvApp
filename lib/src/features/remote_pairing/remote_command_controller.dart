import 'dart:async';

import 'pairing_protocol.dart';
import 'pairing_service.dart';
import 'remote_command.dart'
    show RemoteCommandOutcome, RemoteCommandRequest, RemoteCommandSequence, RemoteCommandType;
import 'tv_remote_actions.dart';

/// Foreground surface the remote is allowed to act on.
enum RemoteAppSurface { bootstrap, onboarding, home, viewer, slideshow, background }

/// Validates and dispatches phone commands to a narrow app-level handler.
///
/// The controller never sees raw key events, routes, or Immich API calls: it
/// only maps the allowlisted [RemoteCommandType] values to [RemoteActionHandler]
/// methods, and only while an active foreground session exists.
class RemoteCommandController {
  RemoteCommandController({
    required this.service,
    required this.actions,
    this.maxCommandsPerSecond = 20,
  });

  final PhonePairingService service;
  final RemoteActionHandler actions;
  final int maxCommandsPerSecond;

  final StreamController<RemoteCommandOutcome> _outcomes =
      StreamController<RemoteCommandOutcome>.broadcast();
  StreamSubscription<PairingSnapshot?>? _snapshotSubscription;
  StreamSubscription<RemoteCommandRequest>? _commandSubscription;
  final RemoteCommandSequence _sequence = RemoteCommandSequence();
  final List<DateTime> _recentCommands = <DateTime>[];
  RemoteAppSurface _surface = RemoteAppSurface.home;
  String? _lastSessionId;
  bool _sessionDisconnected = false;
  bool _appActive = true;
  bool _started = false;

  Stream<RemoteCommandOutcome> get outcomes => _outcomes.stream;
  RemoteAppSurface get surface => _surface;
  bool get appActive => _appActive;

  void start() {
    if (_started) return;
    _started = true;
    _snapshotSubscription = service.updates.listen(_onSnapshot);
    _commandSubscription = service.remoteCommands.listen(
      (request) => unawaited(handle(request)),
    );
  }

  void setSurface(RemoteAppSurface surface) => _surface = surface;

  /// App lifecycle hook: backgrounded apps must not accept remote commands.
  void setAppActive(bool active) {
    _appActive = active;
    if (!active) _recentCommands.clear();
  }

  Future<RemoteCommandOutcome> handle(RemoteCommandRequest request) async {
    final outcome = _decide(request);
    service.resolveRemoteCommand(request, outcome);
    if (!_outcomes.isClosed) _outcomes.add(outcome);
    return outcome;
  }

  RemoteCommandOutcome _decide(RemoteCommandRequest request) {
    final command = request.command;
    if (!_appActive ||
        _surface == RemoteAppSurface.background ||
        _surface == RemoteAppSurface.bootstrap) {
      return RemoteCommandOutcome.unavailable;
    }
    final snapshot = service.snapshot;
    if (snapshot == null ||
        snapshot.phase != PairingPhase.active ||
        snapshot.sessionId != request.sessionId ||
        _sessionDisconnected) {
      return RemoteCommandOutcome.invalid;
    }
    if (!_consumeCommandBudget()) return RemoteCommandOutcome.invalid;
    // The transport owns per-client sequence validation and replay rejection.
    // A single global watermark here would reject valid commands from a second
    // phone (and commands that continue a setup input's sequence).
    _sequence.advanceTo(command.sequence);
    if (command.type == RemoteCommandType.disconnect) {
      _sessionDisconnected = true;
    }

    return switch (command.type) {
      RemoteCommandType.navigate =>
        actions.navigate(command.direction!) ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.select =>
        actions.select() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.back =>
        actions.back() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.textInput =>
        actions.insertText(command.text!) ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.backspace =>
        actions.backspace() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.clearText =>
        actions.clearText() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.submitText =>
        actions.submitText() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.ignored,
      RemoteCommandType.togglePlayback =>
        actions.togglePlayback() ? RemoteCommandOutcome.ok : RemoteCommandOutcome.unavailable,
      RemoteCommandType.seekBy =>
        actions.seekBy(command.seekSeconds!) ? RemoteCommandOutcome.ok : RemoteCommandOutcome.unavailable,
      RemoteCommandType.disconnect => RemoteCommandOutcome.ok,
    };
  }

  void _onSnapshot(PairingSnapshot? snapshot) {
    if (snapshot == null) {
      _sequence.reset(0);
      _lastSessionId = null;
      return;
    }
    if (_lastSessionId != snapshot.sessionId) {
      // A new pairing session starts a fresh command sequence.
      _lastSessionId = snapshot.sessionId;
      _sessionDisconnected = false;
      _sequence.reset(snapshot.lastAcceptedSequence);
    } else if (snapshot.phase == PairingPhase.active) {
      // Onboarding input and status polls advance the watermark; keep a
      // terminal disconnect intact while doing so.
      _sequence.advanceTo(snapshot.lastAcceptedSequence);
    }
    if (snapshot.phase == PairingPhase.expired ||
        snapshot.phase == PairingPhase.revoked ||
        snapshot.phase == PairingPhase.stopped) {
      _recentCommands.clear();
    }
  }

  bool _consumeCommandBudget() {
    final now = DateTime.now();
    _recentCommands.removeWhere(
      (time) => now.difference(time) >= const Duration(seconds: 1),
    );
    if (_recentCommands.length >= maxCommandsPerSecond) return false;
    _recentCommands.add(now);
    return true;
  }

  void dispose() {
    _snapshotSubscription?.cancel();
    _commandSubscription?.cancel();
    _outcomes.close();
    _started = false;
  }
}
