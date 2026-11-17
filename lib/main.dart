import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    imageCache.maximumSize = 40;
    imageCache.maximumSizeBytes = 32 << 20;
  } else {
    imageCache.maximumSize = 72;
    imageCache.maximumSizeBytes = 64 << 20;
  }
  unawaited(_enableWakelockIfSupported());
  runImmichTvApp();
}

Future<void> _enableWakelockIfSupported() async {
  try {
    await WakelockPlus.enable();
  } catch (_) {
    // Mobile browsers can reject wake-lock requests during startup. Rendering
    // the app is more important; native platforms can still enable it.
  }
}
