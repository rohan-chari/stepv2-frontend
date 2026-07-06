import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/review_prompt_service.dart';

/// Host that lets tests fire the prompt from a real BuildContext with a
/// Scaffold above it (the "not really" branch shows a SnackBar).
class _Host extends StatelessWidget {
  const _Host({required this.service});

  final ReviewPromptService service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => service.recordHappyMomentAndMaybePrompt(context),
            child: const Text('trigger'),
          ),
        ),
      ),
    );
  }
}

void main() {
  final now = DateTime(2026, 7, 6, 12);
  final fourDaysAgoMs = now
      .subtract(const Duration(days: 4))
      .millisecondsSinceEpoch;

  ReviewPromptService buildService({
    required List<int> reviewRequests,
    DateTime? clock,
  }) {
    return ReviewPromptService(
      requestNativeReview: () async => reviewRequests.add(1),
      clock: () => clock ?? now,
    );
  }

  Future<void> trigger(WidgetTester tester) async {
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
  }

  testWidgets('warm-up: no dialog on the first happy moment', (tester) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
    });
    final requests = <int>[];
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: requests)));
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);
    // Second qualifying moment passes every guard.
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsOneWidget);
  });

  testWidgets('warm-up: no dialog within 3 days of first seen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': now
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch,
      'review_prompt_happy_moments': 5,
    });
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: [])));
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);
  });

  testWidgets('yes -> native review requested, never asked again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
      'review_prompt_happy_moments': 2,
    });
    final requests = <int>[];
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: requests)));
    await trigger(tester);
    await tester.tap(find.text('YES!'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('review_prompt_answered'), isTrue);

    // A fresh service (new session) still never re-asks.
    final requests2 = <int>[];
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: requests2)));
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);
    expect(requests2, isEmpty);
  });

  testWidgets('not really -> snackbar, no review, never asked again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
      'review_prompt_happy_moments': 2,
    });
    final requests = <int>[];
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: requests)));
    await trigger(tester);
    await tester.tap(find.text('NOT REALLY'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Thanks for the feedback!'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('review_prompt_answered'), isTrue);
  });

  testWidgets('tap-outside dismiss -> cooldown, not answered', (tester) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
      'review_prompt_happy_moments': 2,
    });
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: [])));
    await trigger(tester);
    await tester.tapAt(const Offset(5, 5)); // barrier
    await tester.pumpAndSettle();
    expect(find.text('ENJOYING BARA?'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('review_prompt_answered'), isNull);
    expect(prefs.getInt('review_prompt_ask_count'), 1);

    // New session 30 days later: still cooling down (60-day window).
    await tester.pumpWidget(
      _Host(
        service: buildService(
          reviewRequests: [],
          clock: now.add(const Duration(days: 30)),
        ),
      ),
    );
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);

    // New session 61 days later: eligible again.
    await tester.pumpWidget(
      _Host(
        service: buildService(
          reviewRequests: [],
          clock: now.add(const Duration(days: 61)),
        ),
      ),
    );
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsOneWidget);
  });

  testWidgets('lifetime cap: no dialog after 3 unanswered asks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
      'review_prompt_happy_moments': 10,
      'review_prompt_ask_count': 3,
      'review_prompt_last_ask_ms': now
          .subtract(const Duration(days: 200))
          .millisecondsSinceEpoch,
    });
    await tester.pumpWidget(_Host(service: buildService(reviewRequests: [])));
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);
  });

  testWidgets('once per session even when guards would pass again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_first_seen_ms': fourDaysAgoMs,
      'review_prompt_happy_moments': 2,
    });
    final service = buildService(reviewRequests: []);
    await tester.pumpWidget(_Host(service: service));
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Same service instance, cooldown hasn't elapsed but even with a mocked
    // future clock the session guard blocks first.
    await trigger(tester);
    expect(find.text('ENJOYING BARA?'), findsNothing);
  });
}
