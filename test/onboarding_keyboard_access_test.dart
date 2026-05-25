import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/display_name_screen.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  testWidgets('DisplayNameScreen keeps continue button reachable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: DisplayNameScreen(authService: AuthService())),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('CONTINUE')).dy, lessThan(360));
  });

  testWidgets('DisplayNameScreen centers the prompt and dismisses keyboard', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: DisplayNameScreen(authService: AuthService())),
    );

    final prompt = find.text('This is how friends will find you');
    final input = find.byType(TextField);

    expect(tester.getCenter(prompt).dy, inInclusiveRange(200, 460));
    expect(tester.getCenter(input).dy, inInclusiveRange(250, 520));

    await tester.showKeyboard(input);
    await tester.pump();

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    expect(editable.widget.focusNode.hasFocus, isFalse);
  });
}
