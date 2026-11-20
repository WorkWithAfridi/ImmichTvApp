import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/shared/presentation/app_colors.dart';

void main() {
  test('accent theme is a deep purple family', () {
    expect(AppColors.primary, AppColors.immichPurple);
    expect(AppColors.focus, AppColors.immichPurple);
    expect(AppColors.focusGlow, isNot(AppColors.focus));
    expect(AppColors.info, AppColors.immichPurpleLight);
  });
}
