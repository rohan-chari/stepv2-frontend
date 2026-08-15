import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
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

  testWidgets('ItemSlot states keep a consistent visible shell size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ItemSlot(
                state: ItemSlotState.empty,
                shellKey: Key('empty-shell'),
              ),
              ItemSlot(
                state: ItemSlotState.held,
                powerupType: 'LEG_CRAMP',
                shellKey: Key('held-shell'),
              ),
              ItemSlot(
                state: ItemSlotState.mysteryBox,
                shellKey: Key('mystery-shell'),
              ),
            ],
          ),
        ),
      ),
    );

    final emptySize = tester.getSize(find.byKey(const Key('empty-shell')));
    final heldSize = tester.getSize(find.byKey(const Key('held-shell')));
    final mysterySize = tester.getSize(find.byKey(const Key('mystery-shell')));

    expect(heldSize, equals(emptySize));
    expect(mysterySize, equals(emptySize));
  });

  testWidgets('ItemSlot held powerups use a distinct shell fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ItemSlot(
                state: ItemSlotState.held,
                powerupType: 'LEG_CRAMP',
                shellKey: Key('held-shell'),
              ),
            ],
          ),
        ),
      ),
    );

    final heldShell = tester.widget<Container>(
      find.byKey(const Key('held-shell')),
    );
    final decoration = heldShell.decoration! as BoxDecoration;

    expect(decoration.color, AppColors.parchmentLight);
  });

  testWidgets('ItemSlot shells are not taller than they are wide', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ItemSlot(
                state: ItemSlotState.held,
                powerupType: 'LEG_CRAMP',
                shellKey: Key('held-shell'),
              ),
              ItemSlot(
                state: ItemSlotState.empty,
                shellKey: Key('empty-shell'),
              ),
              ItemSlot(
                state: ItemSlotState.mysteryBox,
                shellKey: Key('mystery-shell'),
              ),
            ],
          ),
        ),
      ),
    );

    final heldSize = tester.getSize(find.byKey(const Key('held-shell')));

    expect(heldSize.width, greaterThan(heldSize.height));
  });
}
