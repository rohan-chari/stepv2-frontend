import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/powerup_error_copy.dart';

/// Spec §6 nicety — a Drill Sergeant rejected because the target is asleep gets
/// a sleepy 😴 toast, while the server's human-readable message is preserved.
/// POWERUPS_DISABLED just surfaces the server message through the standard path.
void main() {
  test('TARGET_ASLEEP is dressed with a sleepy emoji, keeping the message', () {
    final copy = powerupUseErrorCopy(
      ApiException(
        'That rival is likely asleep — Drill Sergeant is blocked from 10PM to 7AM their time.',
        statusCode: 400,
        code: 'TARGET_ASLEEP',
      ),
    );
    expect(copy, contains('😴'));
    expect(copy, contains('asleep'));
    expect(copy, isNot(contains('TARGET_ASLEEP')));
  });

  test('POWERUPS_DISABLED surfaces the server message through the toast', () {
    final copy = powerupUseErrorCopy(
      ApiException(
        'Powerups are disabled in this race.',
        statusCode: 400,
        code: 'POWERUPS_DISABLED',
      ),
    );
    expect(copy, contains('disabled'));
    expect(copy, isNot(contains('POWERUPS_DISABLED')));
  });
}
