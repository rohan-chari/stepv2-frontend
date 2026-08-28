import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/utils/funded_exposure_error_copy.dart';
import 'package:step_tracker/widgets/feed_bubble.dart';

class _PendingFriendsApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {
    'friends': <Map<String, dynamic>>[],
    'pending': {
      'incoming': [
        {
          'friendshipId': 'friendship-1',
          'user': {
            'id': 'requester-1',
            'displayName': 'AnjaliRuns',
            'profilePhotoUrl': null,
            'firstName': ' Anjali ',
            'lastName': 'Patel',
          },
        },
        {
          'friendshipId': 'friendship-2',
          'user': {
            'id': 'requester-2',
            'displayName': 'FirstOnly',
            'firstName': 'Maya',
            'lastName': null,
          },
        },
        {
          'friendshipId': 'friendship-3',
          'user': {
            'id': 'requester-3',
            'displayName': 'LastOnly',
            'firstName': null,
            'lastName': 'Chen',
          },
        },
        {
          'friendshipId': 'friendship-4',
          'user': {'id': 'requester-4', 'displayName': 'OldBackend'},
        },
        {
          'friendshipId': 'friendship-5',
          'user': {
            'id': 'requester-5',
            'displayName': 'MalformedName',
            'firstName': 99,
            'lastName': false,
          },
        },
      ],
      'outgoing': <Map<String, dynamic>>[],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchPublicProfile({
    required String identityToken,
    required String userId,
  }) async => const {
    'user': {'id': 'requester-1', 'displayName': 'AnjaliRuns'},
    'stats': <String, dynamic>{},
  };
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_session_token': 'token',
    'auth_backend_user_id': 'viewer',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  test('active competition copy prefers a valid server limit', () {
    expect(
      fundedExposureErrorCopy(
        const ApiException(
          'server fallback',
          statusCode: 409,
          code: 'ACTIVE_COMPETITION_LIMIT',
          details: {'limit': 17, 'current': 17},
        ),
      ),
      'You can have up to 17 active competitions at a time.',
    );
    expect(
      fundedExposureErrorCopy(
        const ApiException(
          'server fallback',
          code: 'ACTIVE_COMPETITION_LIMIT',
          details: {'limit': '20'},
        ),
      ),
      'You’ve reached the active competition limit. Finish or leave an active competition, then try again.',
    );
  });

  test('Decoy public payload stays routable by old and new route seams', () {
    final inbox = InboxDestination.tryParse(const {
      'route': 'race_detail',
      'params': {'raceId': 'race-17'},
    });
    expect(inbox?.route, InboxDestinationRoute.raceDetail);
    expect(inbox?.raceId, 'race-17');
    expect(
      NotificationService(
        isIosForTesting: false,
      ).resolveRoute('POWERUP_USED', const {'raceId': 'race-17'}),
      NotificationRoute.raceDetail,
    );
  });

  testWidgets('race activity renders the complete server sentence', (
    WidgetTester tester,
  ) async {
    const sentence =
        'Jordan used Signal Jammer on Team Sunflower and the entire sentence must stay visible.';
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeedBubble(
            eventType: 'POWERUP_USED',
            powerupType: 'SIGNAL_JAMMER',
            description: sentence,
            actorName: 'Jordan',
            relativeTime: 'now',
          ),
        ),
      ),
    );

    final rich = tester.widget<RichText>(find.byType(RichText).last);
    expect(rich.maxLines, isNull);
    expect(rich.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'incoming request shows real name over handle and reflows actions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final auth = await _auth();
      await tester.pumpWidget(
        MaterialApp(
          home: FriendsTab(
            authService: auth,
            backendApiService: _PendingFriendsApi(),
            onFriendsChanged: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Anjali Patel'), findsOneWidget);
      expect(find.text('@AnjaliRuns'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('@FirstOnly'), findsOneWidget);
      expect(find.text('Chen'), findsOneWidget);
      expect(find.text('@LastOnly'), findsOneWidget);
      expect(find.text('@OldBackend'), findsOneWidget);
      expect(find.text('@MalformedName'), findsOneWidget);
      expect(find.text('ACCEPT'), findsNWidgets(5));
      expect(find.text('DECLINE'), findsNWidgets(5));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('@AnjaliRuns'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('public-profile-sheet')),
        findsOneWidget,
      );
      expect(find.text('Anjali Patel'), findsWidgets);
      expect(find.text('@AnjaliRuns'), findsWidgets);
    },
  );
}
