import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/modal_action_button.dart';

void main() {
  testWidgets('dialog actions use yellow secondary and green primary accents', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: AlertDialog(
          actions: [
            const ModalActionButton(
              label: 'Cancel',
              variant: ModalActionVariant.secondary,
              onPressed: null,
            ),
            const ModalActionButton(label: 'Confirm', onPressed: null),
          ],
        ),
      ),
    );

    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(
      buttons.elementAt(0).style?.foregroundColor?.resolve({}),
      AppColors.pillGoldDark,
    );
    expect(
      buttons.elementAt(1).style?.foregroundColor?.resolve({}),
      AppColors.pillGreenDark,
    );
  });
}
