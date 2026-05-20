import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/friend_picker_screen.dart';
import 'package:step_tracker/widgets/arcade_page.dart';
import 'package:step_tracker/widgets/retro_card.dart';

void main() {
  testWidgets('FriendPickerScreen starts friend list below the page header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FriendPickerScreen(
          friends: [
            {'id': 'friend-1', 'displayName': 'Hill Climber'},
            {'id': 'friend-2', 'displayName': 'Trail Walker'},
          ],
        ),
      ),
    );

    final headerHeight = const ArcadePageBackground().headerHeight;
    final firstCardTop = tester.getTopLeft(find.byType(RetroCard).first).dy;

    expect(firstCardTop, greaterThanOrEqualTo(headerHeight));
  });
}
