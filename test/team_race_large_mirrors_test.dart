import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_api_service.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart'
    show TutorialMockPage;
import 'support/large_team_fixture.dart';

class _TeamDemoEngine extends DemoRaceEngine {
  _TeamDemoEngine(this.details, this.progress)
    : super(myUserId: tutorialPreviewUserId, myDisplayName: 'Rohan');
  final Map<String, dynamic> details;
  final Map<String, dynamic> progress;
  @override
  Map<String, dynamic> raceDetails(DateTime now, {DateTime? wallNow}) =>
      details;
  @override
  Map<String, dynamic> raceProgress(DateTime now) => progress;
}

class _TeamTutorialApi extends TutorialPreviewBackendApiService {
  _TeamTutorialApi(this.details, this.progress);
  final Map<String, dynamic> details;
  final Map<String, dynamic> progress;
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => details;
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => progress;
}

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '2.3.13',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  for (final mirror in ['demo', 'tab tutorial']) {
    testWidgets(
      '$mirror renders real 10v10 detail and keeps all20 on refresh',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = LargeTeamFixtureApi(status: 'ACTIVE');
        final details = await fixture.fetchRaceDetails(
          identityToken: 'fake',
          raceId: 'fake',
        );
        final progress = await fixture.fetchRaceProgress(
          identityToken: 'fake',
          raceId: 'fake',
        );
        final auth = TutorialPreviewAuthService();
        late BackendApiService api;
        late Widget screen;
        if (mirror == 'demo') {
          api = DemoRaceApiService(_TeamDemoEngine(details, progress));
          screen = RaceDetailScreen(
            authService: auth,
            raceId: 'fake',
            backendApiService: api,
            demoMode: true,
          );
        } else {
          final tutorialApi = _TeamTutorialApi(details, progress);
          api = tutorialApi;
          screen = TutorialRealHost(
            page: TutorialMockPage.raceDetail,
            keys: const {},
            authService: auth,
            api: tutorialApi,
          );
        }
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final side = find.byKey(const Key('team-roster-scroll-TEAM_B'));
        expect(side, findsOneWidget);
        await tester.ensureVisible(side);
        await tester.drag(side, const Offset(0, -650));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byKey(const Key('team-cell-B9')).hitTestable(),
          findsOneWidget,
        );
        final refreshed = await api.fetchRaceProgressParticipants(
          identityToken: 'fake',
          raceId: 'fake',
          offset: 15,
          limit: 15,
        );
        expect((refreshed.progress['participants'] as List).length, 20);
        expect(refreshed.participantsPagination, isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
