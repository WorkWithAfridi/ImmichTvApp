import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/shared/presentation/widgets/immich_logo.dart';

void main() {
  test('flower painter draws visible colored petals on a transparent canvas',
      () async {
    const size = 200.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const painter = ImmichFlowerPainter(
      petalScales: [1, 1, 1, 1, 1, 1, 1, 1],
      rotation: 0,
      centerScale: 1,
    );
    painter.paint(canvas, const ui.Size(size, size));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = byteData!.buffer.asUint8List();

    // A petal sits above the center; sample it directly.
    final index = ((size / 2).toInt() * size.toInt() * 4) +
        ((size * 0.28).toInt() * 4);
    final red = pixels[index];
    final green = pixels[index + 1];
    final blue = pixels[index + 2];
    final alpha = pixels[index + 3];

    expect(alpha, greaterThan(0));
    expect(red + green + blue, greaterThan(0));
  });
}
