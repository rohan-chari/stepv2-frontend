import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';
import 'package:step_tracker/widgets/step_milestones_section.dart';

// Home section order: SETUP, then "Today's coins", then "Suggested Races".
//
// Today's coins moves every day whether or not the user is in a race, so it
// outranks the race rail. The StaggerIn indices must follow the visual order
// or the bounce-in cascade plays out of sequence, so that is asserted too.

class _FakeApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

Future<AuthService> _authService(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'SwiftCapybara07',
    'auth_profile_photo_url': 'https://example.test/photo.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-07-01T00:00:00.000Z',
    'auth_onboarding_v3_enabled': true,
  });
  final authService = AuthService(backendApiService: api);
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(AuthService authService, BackendApiService api) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 4461, date: DateTime(2026, 7, 27)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'SwiftCapybara07',
        authService: authService,
        backendApiService: api,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
        raceCard: const {'state': 'EMPTY'},
      ),
    ),
  );
}

/// Home hosts repeating tickers that never settle, so pump in bounded steps.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; without this the activation-event writes hang silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets("Today's coins renders above Suggested Races", (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeApi();
    final authService = await _authService(api);

    await tester.pumpWidget(_buildHome(authService, api));
    await _flush(tester);

    final coins = find.text("Today's coins");
    final races = find.text('Suggested Races');
    expect(coins, findsOneWidget);
    expect(races, findsWidgets);

    expect(
      tester.getTopLeft(coins).dy,
      lessThan(tester.getTopLeft(races.first).dy),
    );
  });

  testWidgets("Today's coins breathes above and hugs Suggested Races below", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeApi();
    final authService = await _authService(api);

    await tester.pumpWidget(_buildHome(authService, api));
    await _flush(tester);

    final section = tester.getRect(find.byType(StepMilestonesSection));
    final coins = tester.getRect(find.text("Today's coins"));
    final races = tester.getRect(find.text('Suggested Races'));

    // The quick-actions row above ends flush, so this inset is the entire gap
    // under the EXTRA SPIN / SHOP buttons. It used to be 6 and read as a
    // collision.
    final aboveHeader = coins.top - section.top;
    expect(aboveHeader, greaterThan(16));

    // ...and the RACES header sits close to the card it follows rather than
    // floating midway between the two sections.
    final belowCard = races.top - section.bottom;
    expect(belowCard, lessThan(14));

    // The asymmetry is the point: more air above the section than below it.
    expect(aboveHeader, greaterThan(belowCard));
  });

  testWidgets('the stagger cascade still runs in visual order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeApi();
    final authService = await _authService(api);

    await tester.pumpWidget(_buildHome(authService, api));
    await _flush(tester);

    // Walk every StaggerIn on the page top-to-bottom; its index must never
    // decrease, otherwise the intro animation plays out of order.
    final staggers = tester
        .widgetList<StaggerIn>(find.byType(StaggerIn))
        .toList();
    final byPosition = <MapEntry<double, int>>[];
    for (final widget in staggers) {
      final finder = find.byWidget(widget);
      if (finder.evaluate().isEmpty) continue;
      byPosition.add(MapEntry(tester.getTopLeft(finder).dy, widget.index));
    }
    byPosition.sort((a, b) => a.key.compareTo(b.key));
    final indices = byPosition.map((e) => e.value).toList();
    for (var i = 1; i < indices.length; i++) {
      expect(
        indices[i],
        greaterThanOrEqualTo(indices[i - 1]),
        reason: 'StaggerIn indices must ascend down the page: $indices',
      );
    }
  });
}
