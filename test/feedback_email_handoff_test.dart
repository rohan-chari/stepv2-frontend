import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/widgets/feedback_sheet.dart';
import 'package:step_tracker/widgets/pill_button.dart';

class _FeedbackApi extends BackendApiService {
  _FeedbackApi({
    this.result = FeedbackSubmissionDelivery.email,
    this.error,
    this.completion,
  });

  final FeedbackSubmissionDelivery result;
  final Object? error;
  final Completer<FeedbackSubmissionDelivery>? completion;
  int submissions = 0;
  String? text;
  String? replyToEmail;

  @override
  Future<FeedbackSubmissionDelivery> submitSuggestion({
    required String identityToken,
    required String text,
    String? replyToEmail,
    String? category,
  }) async {
    submissions++;
    this.text = text;
    this.replyToEmail = replyToEmail;
    if (error != null) throw error!;
    if (completion != null) return completion!.future;
    return result;
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, Object? body)
    : _bytes = utf8.encode(jsonEncode(body));

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers extends Fake implements HttpHeaders {
  final Map<String, Object> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  set contentType(ContentType? value) {
    if (value != null) values[HttpHeaders.contentTypeHeader] = value.toString();
  }
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);

  final HttpClientResponse response;
  final _Headers recordedHeaders = _Headers();
  final StringBuffer written = StringBuffer();

  @override
  HttpHeaders get headers => recordedHeaders;

  @override
  void write(Object? object) => written.write(object);

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Http extends Fake implements HttpClient {
  _Http(this.response);

  final HttpClientResponse response;
  late final _Request request;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    request = _Request(response);
    return request;
  }
}

Future<AuthService> _auth(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'TestBara',
    'auth_onboarding_v3_enabled': true,
  });
  final auth = AuthService(backendApiService: api);
  await auth.restoreSession();
  return auth;
}

Widget _sheet(AuthService auth, BackendApiService api) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showFeedbackSheet(
          context: context,
          authService: auth,
          backendApiService: api,
        ),
        child: const Text('OPEN'),
      ),
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester, BackendApiService api) async {
  await tester.pumpWidget(_sheet(await _auth(api), api));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('sheet adds reply email and email disclosure in field order', (
    tester,
  ) async {
    final api = _FeedbackApi();
    await _openSheet(tester, api);

    final message = find.byKey(const Key('feedback-input'));
    final reply = find.byKey(const Key('feedback-reply-email'));
    final submit = find.byKey(const Key('feedback-submit'));
    expect(message, findsOneWidget);
    expect(reply, findsOneWidget);
    expect(find.text('EMAIL (OPTIONAL)'), findsOneWidget);
    expect(find.text('you@example.com'), findsOneWidget);
    expect(
      find.text('Your feedback is emailed to Bara Support.'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(message).dy,
      lessThan(tester.getTopLeft(reply).dy),
    );
    expect(tester.getTopLeft(reply).dy, lessThan(tester.getTopLeft(submit).dy));

    await tester.enterText(message, '  a thoughtful note  ');
    await tester.enterText(reply, '  person@example.com  ');
    await tester.tap(submit);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('feedback-sheet')), findsOneWidget);
    expect(find.byKey(const Key('info-toast-shell')), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(api.text, 'a thoughtful note');
    expect(api.replyToEmail, 'person@example.com');
    expect(find.text('Sent to Bara Support'), findsOneWidget);
    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(find.byKey(const Key('feedback-sheet')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('old or unknown delivery response uses honest generic copy', (
    tester,
  ) async {
    final api = _FeedbackApi(result: FeedbackSubmissionDelivery.generic);
    await _openSheet(tester, api);
    await tester.enterText(
      find.byKey(const Key('feedback-input')),
      'legacy backend',
    );
    final submit = find.byKey(const Key('feedback-submit'));
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Feedback received'), findsOneWidget);
    expect(find.text('Sent to Bara Support'), findsNothing);
    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('uncertain delivery keeps draft and warns duplicate on retry', (
    tester,
  ) async {
    final api = _FeedbackApi(
      error: const ApiException(
        'uncertain',
        statusCode: 503,
        code: 'EMAIL_DELIVERY_UNCERTAIN',
      ),
    );
    await _openSheet(tester, api);
    await tester.enterText(
      find.byKey(const Key('feedback-input')),
      'keep this draft',
    );
    await tester.enterText(
      find.byKey(const Key('feedback-reply-email')),
      'me@example.com',
    );
    await tester.tap(find.byKey(const Key('feedback-submit')));
    await tester.pumpAndSettle();

    expect(find.text('keep this draft'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(
      find.text("We couldn't confirm delivery. Retrying may send a duplicate."),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);
  });

  testWidgets('client no-response uses the same duplicate warning', (
    tester,
  ) async {
    final api = _FeedbackApi(error: const ApiException('timed out'));
    await _openSheet(tester, api);
    await tester.enterText(
      find.byKey(const Key('feedback-input')),
      'did this arrive?',
    );
    final submit = find.byKey(const Key('feedback-submit'));
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text("We couldn't confirm delivery. Retrying may send a duplicate."),
      findsOneWidget,
    );
  });

  testWidgets('invalid reply email is local and in-flight submit is disabled', (
    tester,
  ) async {
    final completion = Completer<FeedbackSubmissionDelivery>();
    final api = _FeedbackApi(completion: completion);
    await _openSheet(tester, api);
    final message = find.byKey(const Key('feedback-input'));
    final reply = find.byKey(const Key('feedback-reply-email'));
    final submit = find.byKey(const Key('feedback-submit'));
    await tester.enterText(message, 'hello');
    await tester.enterText(reply, 'one@example.com,two@example.com');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(api.submissions, 0);
    expect(
      find.text('Enter one email address, like you@example.com.'),
      findsOneWidget,
    );

    await tester.enterText(reply, 'one@example.com');
    await tester.tap(submit);
    await tester.pump();
    expect(api.submissions, 1);
    expect(tester.widget<PillButton>(submit).loading, isTrue);
    await tester.tap(submit);
    await tester.pump();
    expect(api.submissions, 1);

    completion.complete(FeedbackSubmissionDelivery.email);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Sent to Bara Support'), findsOneWidget);
  });

  testWidgets('compact keyboard-open sheet scrolls submit into reach', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _openSheet(tester, _FeedbackApi());

    expect(find.byKey(const Key('feedback-scroll')), findsOneWidget);
    final outerScrollable = find
        .descendant(
          of: find.byKey(const Key('feedback-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollableState = tester.state<ScrollableState>(outerScrollable);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const Key('feedback-scroll')),
      const Offset(0, -420),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('feedback-submit')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'API sends optional reply email and bounded platform provenance',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        final http = _Http(
          _Response(201, const {'ok': true, 'delivery': 'email'}),
        );
        final result = await BackendApiService(httpClient: http)
            .submitSuggestion(
              identityToken: 'token',
              text: 'hello',
              replyToEmail: 'person@example.com',
            );

        expect(result, FeedbackSubmissionDelivery.email);
        expect(jsonDecode(http.request.written.toString()), {
          'text': 'hello',
          'replyToEmail': 'person@example.com',
        });
        expect(
          http.request.recordedHeaders.values['x-platform'],
          platform == TargetPlatform.iOS ? 'ios' : 'android',
        );
      }
    },
  );

  test('API maps missing and unknown delivery to generic success', () async {
    for (final body in [
      const <String, dynamic>{'ok': true},
      const <String, dynamic>{'ok': true, 'delivery': 'carrier-pigeon'},
    ]) {
      final result = await BackendApiService(
        httpClient: _Http(_Response(201, body)),
      ).submitSuggestion(identityToken: 'token', text: 'hello');
      expect(result, FeedbackSubmissionDelivery.generic);
    }
  });

  test('API maps non-object 201 responses to generic success', () async {
    for (final body in <Object?>[
      const <Object?>['ok'],
      'ok',
      null,
    ]) {
      final result = await BackendApiService(
        httpClient: _Http(_Response(201, body)),
      ).submitSuggestion(identityToken: 'token', text: 'hello');
      expect(result, FeedbackSubmissionDelivery.generic);
    }
  });

  test('API omits X-Platform outside supported mobile targets', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final http = _Http(_Response(201, const {'ok': true}));

    await BackendApiService(
      httpClient: http,
    ).submitSuggestion(identityToken: 'token', text: 'hello');

    expect(http.request.recordedHeaders.values, isNot(contains('x-platform')));
  });

  test('tutorial fake accepts reply email without a real transport', () async {
    final result = await TutorialPreviewBackendApiService().submitSuggestion(
      identityToken: 'preview-token',
      text: 'hi',
      replyToEmail: 'preview@example.com',
    );
    expect(result, FeedbackSubmissionDelivery.email);
  });
}
