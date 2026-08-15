import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/discoverable_identity_flow.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _IdentityApi extends BackendApiService {
  bool collide = false;
  bool rejectLastNameOnce = false;
  String suggestedDisplayName = 'NathanChari';
  Map<String, dynamic>? pageOneBody;
  Map<String, dynamic>? pageTwoBody;

  @override
  Future<Map<String, dynamic>> updateDiscoverableName({
    required String identityToken,
    required String firstName,
    String? lastName,
  }) async {
    pageOneBody = {'firstName': firstName, 'lastName': lastName};
    if (rejectLastNameOnce) {
      rejectLastNameOnce = false;
      throw const ApiException(
        'Last name is invalid.',
        statusCode: 400,
        code: 'INVALID_LAST_NAME',
      );
    }
    return {
      'user': {
        'id': 'me',
        'firstName': firstName,
        'lastName': lastName,
        'nameSetupOnboardingRequired': true,
        'nameSetupCompletedAt': null,
      },
      'suggestedDisplayName': suggestedDisplayName,
    };
  }

  @override
  Future<Map<String, dynamic>> updateDisplayName({
    required String identityToken,
    required String? displayName,
    bool completeDiscoverableNameSetup = false,
  }) async {
    pageTwoBody = {
      'displayName': displayName,
      'completeDiscoverableNameSetup': completeDiscoverableNameSetup,
    };
    if (collide) {
      throw const ApiException(
        'That display name is already taken.',
        statusCode: 409,
        code: 'DISPLAY_NAME_TAKEN',
        details: {'suggestedDisplayName': 'NathanChari27'},
      );
    }
    return {
      'user': {
        'id': 'me',
        'displayName': displayName,
        'firstName': 'Nathan',
        'lastName': 'Chari',
        'nameSetupOnboardingRequired': true,
        'nameSetupCompletedAt': '2026-08-11T20:00:00.000Z',
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_backend_user_id': 'me',
      'auth_display_name': 'ExistingHandle',
    });
  });

  testWidgets('identity header and card fit a narrow phone with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _IdentityApi();
    final auth = AuthService(backendApiService: api);
    await auth.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: DiscoverableIdentityFlow(
          authService: auth,
          backendApiService: api,
        ),
      ),
    );

    final viewport = tester.getRect(find.byType(Scaffold));
    final header = tester.getRect(
      find.byKey(const Key('identity-step-header')),
    );
    final card = tester.getRect(find.byKey(const Key('identity-page-1')));
    expect(viewport.contains(header.topLeft), isTrue);
    expect(header.right, lessThanOrEqualTo(viewport.right));
    expect(header.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(viewport.contains(card.topLeft), isTrue);
    expect(card.right, lessThanOrEqualTo(viewport.right));
    expect(find.text('NAME SETUP · 1 OF 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real two-page flow preserves existing handle and completes setup',
    (tester) async {
      final api = _IdentityApi();
      final auth = AuthService(backendApiService: api);
      await auth.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverableIdentityFlow(
            authService: auth,
            backendApiService: api,
            initialFirstName: 'Nathan',
            initialLastName: 'Chari',
          ),
        ),
      );

      expect(find.byKey(const Key('identity-step-header')), findsOneWidget);
      expect(find.text('NAME SETUP · 1 OF 2'), findsOneWidget);
      expect(find.byKey(const Key('identity-step-dots')), findsNothing);
      expect(find.text('Help friends find you'), findsOneWidget);
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name (optional)'), findsOneWidget);
      await tester.tap(find.text("THAT'S ME"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Choose your race name'), findsOneWidget);
      expect(find.text('NAME SETUP · 2 OF 2'), findsOneWidget);
      final raceName = tester.widget<TextField>(
        find.byKey(const Key('identity-race-name-field')),
      );
      expect(raceName.controller?.text, 'ExistingHandle');
      await tester.tap(find.text('CONFIRM RACE NAME'));
      await tester.pump();

      expect(api.pageTwoBody, {
        'displayName': 'ExistingHandle',
        'completeDiscoverableNameSetup': true,
      });
      expect(auth.nameSetupCompletedAt, isNotNull);
    },
  );

  testWidgets('editing a name clears stale server validation', (tester) async {
    final api = _IdentityApi()..rejectLastNameOnce = true;
    final auth = AuthService(backendApiService: api);
    await auth.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverableIdentityFlow(
          authService: auth,
          backendApiService: api,
          initialFirstName: 'Rohan',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('identity-last-name-field')),
      'Ci',
    );
    await tester.tap(find.text("THAT'S ME"));
    await tester.pump();
    expect(find.text('Check your last name and try again.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('identity-last-name-field')),
      'C',
    );
    await tester.pump();
    expect(find.text('Check your last name and try again.'), findsNothing);
  });

  testWidgets('collision keeps page two open and applies server suggestion', (
    tester,
  ) async {
    final api = _IdentityApi()..collide = true;
    final auth = AuthService(backendApiService: api);
    await auth.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverableIdentityFlow(
          authService: auth,
          backendApiService: api,
          initialFirstName: 'Nathan',
          initialLastName: 'Chari',
        ),
      ),
    );
    await tester.tap(find.text("THAT'S ME"));
    await tester.pump();
    await tester.tap(find.text('CONFIRM RACE NAME'));
    await tester.pump();

    expect(find.text('That race name was just taken.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('identity-race-name-field')))
          .controller
          ?.text,
      'NathanChari27',
    );
  });

  testWidgets('saved page-one state resumes directly on race-name page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_backend_user_id': 'me',
      'auth_identity_state_user_id': 'me',
      'auth_identity_supported': true,
      'auth_first_name': 'Nathan',
      'auth_last_name': 'Chari',
      'auth_name_setup_onboarding_required': true,
    });
    final api = _IdentityApi();
    final auth = AuthService(backendApiService: api);
    await auth.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverableIdentityFlow(
          authService: auth,
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose your race name'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('identity-race-name-field')))
          .controller
          ?.text,
      'NathanChari',
    );
    await tester.tap(find.byKey(const Key('identity-back')));
    await tester.pump();
    expect(find.text('Help friends find you'), findsOneWidget);
  });

  testWidgets(
    'required new-account cohort uses the server suggestion over generated fallback',
    (tester) async {
      final api = _IdentityApi()..suggestedDisplayName = 'NathanChari42';
      final auth = AuthService(backendApiService: api);
      await auth.restoreSession();
      await auth.syncFromBackendUser(const {
        'id': 'me',
        'displayName': 'GeneratedOtter88',
        'firstName': null,
        'lastName': null,
        'nameSetupOnboardingRequired': true,
        'nameSetupCompletedAt': null,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverableIdentityFlow(
            authService: auth,
            backendApiService: api,
            initialFirstName: 'Nathan',
            initialLastName: 'Chari',
          ),
        ),
      );
      await tester.tap(find.text("THAT'S ME"));
      await tester.pump();

      expect(find.text('Choose your race name'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('identity-race-name-field')),
            )
            .controller
            ?.text,
        'NathanChari42',
      );
    },
  );

  testWidgets(
    'required cohort resume reloads server suggestion over generated fallback',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'token',
        'auth_backend_user_id': 'me',
        'auth_display_name': 'GeneratedOtter88',
        'auth_identity_state_user_id': 'me',
        'auth_identity_supported': true,
        'auth_first_name': 'Nathan',
        'auth_last_name': 'Chari',
        'auth_name_setup_onboarding_required': true,
      });
      final api = _IdentityApi()..suggestedDisplayName = 'NathanChari42';
      final auth = AuthService(backendApiService: api);
      await auth.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverableIdentityFlow(
            authService: auth,
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Choose your race name'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('identity-race-name-field')),
            )
            .controller
            ?.text,
        'NathanChari42',
      );
    },
  );

  // Regression: the fields are built above OnboardingScene's pinned light
  // Theme, so a night-mode device used to paint the night palette's near-black
  // fill behind the light theme's black input text — the typed name vanished.
  // Assert the color the EditableText ACTUALLY resolves (not just the style we
  // pass) contrasts with the fill it sits on, under either device theme.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('name fields stay legible in $mode', (tester) async {
      final api = _IdentityApi();
      final auth = AuthService(backendApiService: api);
      await auth.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          darkTheme: AppThemeData.night(),
          themeMode: mode,
          home: DiscoverableIdentityFlow(
            authService: auth,
            backendApiService: api,
          ),
        ),
      );

      void expectLegible(Key key) {
        final field = find.byKey(key);
        final fill = tester.widget<TextField>(field).decoration!.fillColor!;
        final text = tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .style
            .color!;

        expect(
          _contrastRatio(text, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$key input text is illegible on its own fill in $mode',
        );
        // Onboarding pins to the daytime palette, so the fill must not follow
        // the device into night.
        expect(fill, AppPalette.light.parchmentLight, reason: '$key fill');
      }

      expectLegible(const Key('identity-first-name-field'));
      expectLegible(const Key('identity-last-name-field'));

      // Page 2's race-name field goes through the same _field helper and is the
      // one users are most likely to edit, so cover that call site too.
      await tester.enterText(
        find.byKey(const Key('identity-first-name-field')),
        'Nathan',
      );
      await tester.tap(find.text("THAT'S ME"));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('identity-race-name-field')), findsOneWidget);
      expectLegible(const Key('identity-race-name-field'));
    });
  }
}

/// WCAG relative-luminance contrast ratio (1.0 = identical, 21.0 = black/white).
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
