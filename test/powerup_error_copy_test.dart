import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/powerup_error_copy.dart';

/// B3 — powerup redeem/use rejection copy. The load-bearing property is
/// old-backend compat: an unknown or absent `code` must fall back to the
/// server-provided message, never a raw code and never a swallowed error.
void main() {
  test('known codes are dressed in friendly copy (no raw code shown)', () {
    for (final code in ['SIGNAL_JAMMED', 'RAINSTORM_ACTIVE',
        'NO_ELIGIBLE_TARGETS']) {
      final copy = powerupUseErrorCopy(
        ApiException('server text', statusCode: 409, code: code),
      );
      expect(copy, isNot(contains(code)));
      expect(copy, isNot('server text'));
      expect(copy.trim(), isNotEmpty);
    }
  });

  test('an unknown code falls back to the server message', () {
    final copy = powerupUseErrorCopy(
      ApiException('You cannot do that yet.', statusCode: 400,
          code: 'SOME_FUTURE_CODE'),
    );
    expect(copy, 'You cannot do that yet.');
  });

  test('no code at all (older backend) falls back to the server message', () {
    final copy = powerupUseErrorCopy(
      ApiException('Rainstorm already going.', statusCode: 400),
    );
    expect(copy, 'Rainstorm already going.');
  });

  test('a non-ApiException error degrades to its string form', () {
    expect(powerupUseErrorCopy(StateError('boom')), contains('boom'));
  });
}
