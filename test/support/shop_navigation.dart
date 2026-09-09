import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> closeShopMembership(WidgetTester tester) async {
  final close = find.byKey(const Key('shop-membership-close'));
  if (close.evaluate().isEmpty) return;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(close);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> selectShopCategory(WidgetTester tester, String category) async {
  await closeShopMembership(tester);
  final target = find.byKey(Key('shop-category-$category'));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}
