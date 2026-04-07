import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';

void main() {
  test('primary green palette matches the forest theme', () {
    expect(AppColors.pillGreen, AppColors.roofLight);
    expect(AppColors.pillGreenDark, AppColors.roofMid);
    expect(AppColors.pillGreenShadow, AppColors.roofDark);
    expect(AppColors.feedBoost, AppColors.roofLight);
  });
}
