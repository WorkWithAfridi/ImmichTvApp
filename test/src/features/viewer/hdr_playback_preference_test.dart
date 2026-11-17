import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/viewer/hdr_playback_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults HDR playback to off', () async {
    const preference = HdrPlaybackPreference();

    expect(await preference.load(), isFalse);
  });

  test('remembers HDR playback until it is disabled', () async {
    const preference = HdrPlaybackPreference();

    await preference.save(true);
    expect(await preference.load(), isTrue);

    await preference.save(false);
    expect(await preference.load(), isFalse);
  });
}
