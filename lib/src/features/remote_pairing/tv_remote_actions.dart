import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'remote_command.dart';

/// Reads an optional repository so feature widgets can still be pumped in
/// isolation (for example in widget tests) without the full app provider tree.
T? maybeRemoteRepository<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Narrow app-level actions a paired phone is allowed to invoke.
///
/// Implementations must translate these into existing focus/intent/controller
/// actions. They must never accept raw key events, routes, or API calls.
abstract interface class RemoteActionHandler {
  bool navigate(RemoteDirection direction);
  bool select();
  bool back();
  bool insertText(String text);
  bool backspace();
  bool clearText();
  bool submitText();
  bool togglePlayback();
  bool seekBy(int seconds);
}

/// A player that opts in to remote playback commands while it is active.
abstract interface class RemotePlaybackTarget {
  bool get isRemotePlaybackAvailable;
  bool get supportsSeek => true;
  void togglePlayback();
  void seekBy(Duration delta);
}

/// Registry so the remote controller can reach only an active player.
class RemotePlaybackRegistry {
  final Set<RemotePlaybackTarget> _targets = <RemotePlaybackTarget>{};

  bool get hasTarget => _targets.isNotEmpty;

  void register(RemotePlaybackTarget target) => _targets.add(target);

  void unregister(RemotePlaybackTarget target) => _targets.remove(target);

  bool togglePlayback() {
    final target = _activeTarget;
    if (target == null) return false;
    target.togglePlayback();
    return true;
  }

  bool seekBy(Duration delta) {
    final target = _activeTarget;
    if (target == null || !target.supportsSeek) return false;
    target.seekBy(delta);
    return true;
  }

  RemotePlaybackTarget? get _activeTarget {
    for (final target in _targets) {
      if (target.isRemotePlaybackAvailable) return target;
    }
    return null;
  }
}

/// Default TV action adapter built on Flutter focus, intents, and controllers.
class FocusRemoteActionHandler implements RemoteActionHandler {
  const FocusRemoteActionHandler(this._playback);

  final RemotePlaybackRegistry _playback;

  FocusNode? get _focus => FocusManager.instance.primaryFocus;
  BuildContext? get _context => _focus?.context;

  @override
  bool navigate(RemoteDirection direction) {
    final focus = _focus;
    final context = focus?.context;
    if (focus == null || context == null) return false;
    final policy = FocusTraversalGroup.maybeOf(context);
    if (policy == null) return false;
    return policy.inDirection(focus, switch (direction) {
      RemoteDirection.up => TraversalDirection.up,
      RemoteDirection.down => TraversalDirection.down,
      RemoteDirection.left => TraversalDirection.left,
      RemoteDirection.right => TraversalDirection.right,
    });
  }

  @override
  bool select() {
    final context = _context;
    if (context == null) return false;
    return Actions.invoke(context, const ActivateIntent()) != null;
  }

  @override
  bool back() {
    final context = _context;
    if (context == null) return false;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.canPop()) return false;
    unawaited(navigator.maybePop());
    return true;
  }

  @override
  bool insertText(String text) {
    final controller = _textController;
    if (controller == null) return false;
    final value = controller.value;
    final start = value.selection.baseOffset.clamp(0, value.text.length);
    final end = value.selection.extentOffset.clamp(0, value.text.length);
    // Never let a phone payload grow a field beyond the app's own limits.
    const maxLength = 4096;
    final allowed = maxLength - (value.text.length - (end - start));
    if (allowed <= 0) return false;
    final insertion = text.length > allowed ? text.substring(0, allowed) : text;
    controller.value = TextEditingValue(
      text: '${value.text.substring(0, start)}$insertion${value.text.substring(end)}',
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    return true;
  }

  @override
  bool backspace() {
    final controller = _textController;
    if (controller == null) return false;
    final value = controller.value;
    if (!value.selection.isValid) return false;
    var start = value.selection.baseOffset.clamp(0, value.text.length);
    var end = value.selection.extentOffset.clamp(0, value.text.length);
    if (start == end) {
      if (start == 0) return false;
      start = start - 1;
    }
    controller.value = TextEditingValue(
      text: '${value.text.substring(0, start)}${value.text.substring(end)}',
      selection: TextSelection.collapsed(offset: start),
    );
    return true;
  }

  @override
  bool clearText() {
    final controller = _textController;
    if (controller == null || controller.text.isEmpty) return false;
    controller.clear();
    return true;
  }

  @override
  bool submitText() {
    final context = _context;
    if (context == null) return false;
    final field = context.findAncestorWidgetOfExactType<TextField>();
    if (field?.controller != null && field?.onSubmitted != null) {
      field!.onSubmitted!(field.controller!.text);
      return true;
    }
    return select();
  }

  @override
  bool togglePlayback() => _playback.togglePlayback();

  @override
  bool seekBy(int seconds) => _playback.seekBy(Duration(seconds: seconds));

  TextEditingController? get _textController {
    final context = _context;
    if (context == null) return null;
    final editable = context.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null) return editable.controller;
    return context.findAncestorWidgetOfExactType<TextField>()?.controller;
  }
}
