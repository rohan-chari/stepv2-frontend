import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/next_race.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/quick_create_race_sheet.dart';

class _RecordingHttpClient extends Fake implements HttpClient {
  _RecordingHttpClient(this.responseBody);

  final String responseBody;
  _RecordingRequest? request;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    request = _RecordingRequest(method, url, responseBody);
    return request!;
  }
}

class _RecordingRequest extends Fake implements HttpClientRequest {
  _RecordingRequest(this.method, this.uri, this.responseBody);

  @override
  final String method;
  @override
  final Uri uri;
  final String responseBody;
  final _RecordingHeaders recordedHeaders = _RecordingHeaders();
  final List<int> bytes = [];

  @override
  HttpHeaders get headers => recordedHeaders;

  @override
  void add(List<int> data) => bytes.addAll(data);

  @override
  void write(Object? object) => bytes.addAll(utf8.encode(object.toString()));

  @override
  Future<HttpClientResponse> close() async => _RecordingResponse(responseBody);
}

class _RecordingHeaders extends Fake implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  set contentType(ContentType? value) {
    if (value != null) values['content-type'] = value.toString();
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }
}

class _RecordingResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _RecordingResponse(this.body);

  final String body;

  @override
  int get statusCode => 201;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('next race parser fails closed on absent and malformed payloads', () {
    expect(NextRaceState.tryParse(null), isNull);
    expect(
      NextRaceState.tryParse({'resolved': true, 'eligible': 'yes'}),
      isNull,
    );
    expect(
      NextRaceState.tryParse({
        'resolved': true,
        'eligible': true,
        'discoveryEnabled': true,
        'createEnabled': false,
        'openRaces': [
          {'id': null, 'name': 'Bad'},
          {'id': 'race-1', 'name': 'Weekend Sprint', 'participantCount': 2},
        ],
      })?.openRaces.single.id,
      'race-1',
    );
  });

  test(
    'automatic-start copy requires both explicit public and policy fields',
    () {
      expect(
        isAutomaticStartRace({
          'isPublic': true,
          'creationSource': 'QUICK_CREATE',
          'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
        }),
        isTrue,
      );
      expect(isAutomaticStartRace({'isPublic': true}), isFalse);
      expect(
        isAutomaticStartRace({
          'isPublic': false,
          'creationSource': 'QUICK_CREATE',
          'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
        }),
        isFalse,
      );
      expect(
        isAutomaticStartRace({
          'isPublic': true,
          'creationSource': 'CUSTOM',
          'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
        }),
        isFalse,
      );
    },
  );

  test(
    'Apple and Google provision bodies optionally carry source race token',
    () async {
      for (final provider in ['apple', 'google']) {
        final http = _RecordingHttpClient(
          jsonEncode({
            'user': {'id': 'user-1'},
            'sessionToken': 'session',
          }),
        );
        final api = BackendApiService(httpClient: http);
        if (provider == 'apple') {
          await api.provisionAppleUser(
            identityToken: 'apple-token',
            userIdentifier: 'apple-user',
            referralSourceRaceToken: 'raceToken123',
          );
        } else {
          await api.provisionGoogleUser(
            idToken: 'google-token',
            referralSourceRaceToken: 'raceToken123',
          );
        }
        expect(
          jsonDecode(utf8.decode(http.request!.bytes)),
          containsPair('referralSourceRaceToken', 'raceToken123'),
        );
      }
    },
  );

  test(
    'AuthService wires pending race attribution to both provision paths',
    () {
      final source = File('lib/services/auth_service.dart').readAsStringSync();
      expect(
        RegExp(
          r'referralSourceRaceToken:\s*pendingRaceToken',
        ).allMatches(source).length,
        2,
      );
    },
  );

  test(
    'provision omits source race attribution when none was captured',
    () async {
      final http = _RecordingHttpClient(
        jsonEncode({
          'user': {'id': 'user-1'},
          'sessionToken': 'session',
        }),
      );
      await BackendApiService(httpClient: http).provisionAppleUser(
        identityToken: 'apple-token',
        userIdentifier: 'apple-user',
      );
      expect(
        jsonDecode(utf8.decode(http.request!.bytes)),
        isNot(contains('referralSourceRaceToken')),
      );
    },
  );

  test('capability token is present in both header-construction branches', () {
    final source = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    expect(
      RegExp('next_race_cta').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('setup invite prompt flag is fail-closed', () {
    final auth = AuthService();
    auth.applyBackendUser({'id': 'u', 'featureFlags': const {}});
    expect(auth.setupInviteCodePromptEnabled, isFalse);
    auth.applyBackendUser({
      'id': 'u',
      'featureFlags': const {'setupInviteCodePromptEnabled': true},
    });
    expect(auth.setupInviteCodePromptEnabled, isTrue);
    auth.applyBackendUser({
      'id': 'u',
      'featureFlags': const {'setupInviteCodePromptEnabled': 'yes'},
    });
    expect(auth.setupInviteCodePromptEnabled, isFalse);
  });

  test(
    'quick create advertises capability and sends the locked preset',
    () async {
      for (final days in [2, 7]) {
        final http = _RecordingHttpClient(
          jsonEncode({
            'race': {
              'id': 'race-1',
              'creationSource': 'QUICK_CREATE',
              'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
            },
          }),
        );
        final api = BackendApiService(httpClient: http);

        await api.quickCreateRace(
          identityToken: 'token',
          name: 'Weekend Sprint',
          maxDurationDays: days,
        );

        expect(
          http.request!.recordedHeaders.values['x-client-features'],
          contains('next_race_cta'),
        );
        expect(jsonDecode(utf8.decode(http.request!.bytes)), {
          'name': 'Weekend Sprint',
          'maxDurationDays': days,
          'isPublic': true,
          'buyInAmount': 0,
          'payoutPreset': 'TOP3_70_20_10',
          'powerupsEnabled': true,
          'powerupStepInterval': 2000,
          'maxParticipants': 10,
          'creationSource': 'QUICK_CREATE',
          'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
        });
      }
    },
  );

  testWidgets('quick-create sheet exposes only the two presets and customize', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickCreateRaceSheet(
            onCreate: (_) async {},
            onCustomize: () {},
          ),
        ),
      ),
    );

    expect(find.text('2-DAY RACE'), findsOneWidget);
    expect(find.text('7-DAY RACE'), findsOneWidget);
    expect(find.text('CUSTOMIZE…'), findsOneWidget);
  });

  testWidgets('quick-create failure stays in the sheet and can retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickCreateRaceSheet(
            onCreate: (_) async {
              calls++;
              throw const ApiException(
                'You already have a quick race.',
                code: 'QUICK_RACE_ALREADY_LIVE',
              );
            },
            onCustomize: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('quick-create-2d')));
    await tester.pump();
    expect(find.text('You already have a quick race.'), findsOneWidget);
    expect(find.byKey(const Key('quick-create-2d')), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-create-2d')));
    await tester.pump();
    expect(calls, 2);
  });
}
