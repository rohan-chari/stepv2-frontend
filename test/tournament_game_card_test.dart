import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/tournament_game_card.dart';

// Styling addendum: the shared TournamentGameCard gives both the races-tab
// featured row and the Public Races screen the same game-piece polish as
// FeaturedRaceCard (BRACKET pill, dark name, coinDark prize). Also guards the
// section-label ghost-text bug (light-on-light) regression on the public screen.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  group('TournamentGameCard', () {
    testWidgets('renders badge, name, meta, filled, prize value and CTA',
        (tester) async {
      await tester.pumpWidget(host(
        TournamentGameCard(
          name: 'DAILY DASH',
          metaLine: '4 RACERS · 1-DAY KNOCKOUTS',
          filledLabel: '3/4 IN',
          prizeLabel: 'CHAMPION WINS',
          prizeValue: 150,
          ctaKey: const Key('cta'),
          ctaLabel: 'JOIN',
          ctaVariant: PillButtonVariant.primary,
          onPressed: () {},
        ),
      ));

      expect(find.text('BRACKET'), findsOneWidget);
      expect(find.text('DAILY DASH'), findsOneWidget);
      expect(find.text('4 RACERS · 1-DAY KNOCKOUTS'), findsOneWidget);
      expect(find.text('3/4 IN'), findsOneWidget);
      expect(find.text('CHAMPION WINS'), findsOneWidget);

      // Name is dark (readable), prize value is the coin treatment.
      expect(
        tester.widget<Text>(find.text('DAILY DASH')).style?.color,
        AppColors.textDark,
      );
      expect(
        tester.widget<Text>(find.text('150')).style?.color,
        AppColors.coinDark,
      );
      expect(find.byKey(const Key('cta')), findsOneWidget);
    });

    testWidgets('prize row hidden when prizeValue is 0', (tester) async {
      await tester.pumpWidget(host(
        TournamentGameCard(
          name: 'FREE BRACKET',
          metaLine: '8 RACERS · 2-DAY KNOCKOUTS',
          filledLabel: '2/8 IN',
          prizeLabel: 'WINNER TAKES',
          prizeValue: 0,
          ctaLabel: 'JOIN',
          ctaVariant: PillButtonVariant.primary,
          onPressed: () {},
        ),
      ));
      expect(find.text('WINNER TAKES'), findsNothing);
      expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
    });
  });

  group('Public Races section labels are dark-on-parchment (bug fix)', () {
    testWidgets('FEATURED / TOURNAMENTS labels use a readable dark color',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
        'auth_backend_user_id': 'user-1',
        'auth_display_name': 'Trail Walker',
        'auth_coins': 500,
        'auth_held_coins': 0,
      });
      final auth = AuthService();
      await auth.restoreSession();

      await tester.pumpWidget(MaterialApp(
        home: PublicRacesScreen(
          authService: auth,
          backendApiService: _FakeApi(),
        ),
      ));
      // Pumped frames (not pumpAndSettle) — the featured card embeds a
      // SpinningCoin whose animation never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));

      final label = tester.widget<Text>(find.text('FEATURED'));
      expect(label.style?.color, AppColors.textDark);
      // Must not be the near-white ghost color that caused the bug.
      expect(label.style?.color, isNot(AppColors.parchmentLight));
    });
  });
}

class _FakeApi extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async =>
      {
        'featured': [
          {
            'id': 'seed1',
            'name': 'Daily Dash',
            'status': 'PENDING',
            'seedId': 'seed-tournament-daily-dash',
            'seedKind': 'DAILY_DASH',
            'bracketSize': 4,
            'matchupDurationDays': 1,
            'championPrizeCoins': 150,
            'acceptedCount': 3,
          },
        ],
        'tournaments': const [],
      };

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async =>
      {'active': const [], 'pending': const [], 'tournaments': const []};
}
