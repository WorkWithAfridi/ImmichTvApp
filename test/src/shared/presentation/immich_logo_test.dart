import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/shared/presentation/widgets/immich_logo.dart';

void main() {
  testWidgets('animated splash logo renders through its bloom animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: ImmichLogo(
            size: 160,
            duration: Duration(milliseconds: 200),
          ),
        ),
      ),
    );

    expect(find.byType(ImmichLogo), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
