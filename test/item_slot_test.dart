import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/spinning_face.dart';

void main() {
  testWidgets('ItemSlot held powerups render without spinning', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ItemSlot(state: ItemSlotState.held, powerupType: 'LEG_CRAMP'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ItemSlot), findsOneWidget);
    expect(find.byType(PowerupIcon), findsOneWidget);
    expect(find.byType(SpinningFace), findsNothing);
  });
}
