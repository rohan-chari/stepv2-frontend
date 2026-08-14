import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/spinning_crate.dart';
import 'package:step_tracker/widgets/spinning_face.dart';

void main() {
  testWidgets('unopened mystery boxes shimmer and jiggle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MysteryBoxButton(onTap: null))),
      ),
    );

    final shimmer = tester.widget<ShineSweep>(find.byType(ShineSweep));
    final jiggle = tester.widget<WobbleBadge>(find.byType(WobbleBadge));

    expect(shimmer.period, const Duration(milliseconds: 3200));
    expect(jiggle.period, const Duration(milliseconds: 3200));
    expect(find.byType(CrateIcon), findsOneWidget);
    expect(find.byType(SpinningCrate), findsNothing);
  });

  testWidgets('unopened-box motion freezes and restarts with reduced motion', (
    tester,
  ) async {
    final disabled = ValueNotifier<bool>(true);
    addTearDown(disabled.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: disabled,
          builder: (context, reduceMotion, _) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: const Scaffold(
              body: Center(child: MysteryBoxButton(onTap: null)),
            ),
          ),
        ),
      ),
    );

    Finder jiggleTransform() => find.descendant(
      of: find.byType(WobbleBadge),
      matching: find.byType(Transform),
    );
    Finder shimmerBar() => find.descendant(
      of: find.byType(ShineSweep),
      matching: find.byType(Align),
    );
    List<double> matrix() => List<double>.of(
      tester.widget<Transform>(jiggleTransform()).transform.storage,
    );

    final frozen = matrix();
    expect(shimmerBar(), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(matrix(), frozen);

    disabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(matrix(), isNot(frozen));
    expect(shimmerBar(), findsOneWidget);

    disabled.value = true;
    await tester.pump();
    final refrozen = matrix();
    expect(shimmerBar(), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(matrix(), refrozen);
  });

  testWidgets('held and empty slots do not use unopened-box motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ItemSlot(state: ItemSlotState.empty),
              ItemSlot(state: ItemSlotState.held, powerupType: 'LEG_CRAMP'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ShineSweep), findsNothing);
    expect(find.byType(WobbleBadge), findsNothing);
  });

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

  testWidgets('ItemSlot empty and held states keep one visible shell size', (
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
            ],
          ),
        ),
      ),
    );

    final emptySize = tester.getSize(find.byKey(const Key('empty-shell')));
    final heldSize = tester.getSize(find.byKey(const Key('held-shell')));

    expect(heldSize, equals(emptySize));
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
            ],
          ),
        ),
      ),
    );

    final heldSize = tester.getSize(find.byKey(const Key('held-shell')));

    expect(heldSize.width, greaterThan(heldSize.height));
  });

  testWidgets('MysteryBoxButton is a large standalone crate without ItemSlot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MysteryBoxButton(onTap: () => taps++, crateSize: 68),
          ),
        ),
      ),
    );

    expect(find.byType(MysteryBoxButton), findsOneWidget);
    expect(find.byType(ItemSlot), findsNothing);
    expect(tester.widget<CrateIcon>(find.byType(CrateIcon)).size, 68);
    expect(
      tester.getSemantics(find.byType(MysteryBoxButton)),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: 'Open mystery box',
      ),
    );
    await tester.tap(find.byType(MysteryBoxButton));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('MysteryBoxButton grows for enlarged accessibility text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const Scaffold(
              body: Center(child: MysteryBoxButton(onTap: null, crateSize: 68)),
            ),
          ),
        ),
      ),
    );

    expect(find.text('OPEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
