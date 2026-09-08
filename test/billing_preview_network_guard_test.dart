import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview explicitly shadows every API call its real screens make', () {
    final preview = File(
      'lib/preview/preview_billing_api.dart',
    ).readAsStringSync();
    final inherited = File(
      'lib/demo/demo_race_api_service.dart',
    ).readAsStringSync();
    final calls = <String>{};
    for (final path in [
      'lib/screens/tabs/shop_tab.dart',
      'lib/screens/tabs/profile_tab.dart',
      'lib/screens/get_coins_screen.dart',
      'lib/screens/race_detail_screen.dart',
      'lib/widgets/step_calendar.dart',
      'lib/services/rewarded_coins_controller.dart',
      'lib/services/race_chat_service.dart',
      'lib/services/race_feed_service.dart',
      'lib/services/race_stream_coordinator.dart',
    ]) {
      final source = File(path).readAsStringSync();
      calls.addAll(
        RegExp(
          r'(?:_api|api|_backendApiService|widget.backendApiService)\.([a-zA-Z0-9_]+)\(',
        ).allMatches(source).map((m) => m.group(1) ?? ''),
      );
    }
    expect(calls.length, greaterThan(35));
    final declarations = RegExp(
      r'@override\s+(?:Future<[^;{]+>|void|bool)\s+([a-zA-Z0-9_]+)\s*\(',
    ).allMatches('$preview\n$inherited').map((m) => m.group(1)).toSet();
    expect(
      calls.difference(declarations),
      isEmpty,
      reason: 'An inherited real transport call would break preview isolation.',
    );
    expect(preview, isNot(contains('super.')));
  });
}
