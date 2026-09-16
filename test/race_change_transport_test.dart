import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_change_refresh.dart';

void main() {
  test(
    'real HTTP authenticates, parses split frames, ignores malformed/foreign hints and closes socket',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = BackendApiService(
        raceStreamClientFactory: () => HttpClient()
          ..connectionFactory = (uri, proxyHost, proxyPort) =>
              Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
      );
      final requestReady = Completer<HttpRequest>();
      final serving = server.listen(requestReady.complete);
      final signals = <RaceChangeSignal>[];
      final hint = Completer<void>();
      final subscription = api
          .watchRaceChanges(identityToken: 'private-bearer', raceId: 'race-a')
          .listen((signal) {
            signals.add(signal);
            if (signal == RaceChangeSignal.invalidated && !hint.isCompleted) {
              hint.complete();
            }
          });
      final request = await requestReady.future;
      expect(request.uri.path, '/races/race-a/changes');
      expect(request.uri.query, isEmpty);
      expect(request.headers.value('authorization'), 'Bearer private-bearer');
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        ': ready\n\nevent: race-invalidated\ndata: garbage\n\nevent: race-invalidated\ndata: {"raceId":"other"}\n\n',
      );
      await request.response.flush();
      request.response.write('event: race-invalidated\r');
      await request.response.flush();
      request.response.write('\ndata: {"raceId":"race-a"}\r\n\r\n');
      await request.response.flush();
      await hint.future.timeout(const Duration(seconds: 3));
      expect(signals, [
        RaceChangeSignal.connected,
        RaceChangeSignal.invalidated,
      ]);
      await subscription.cancel();
      await serving.cancel();
      await server.close(force: true);
    },
  );
  for (final code in [401, 403, 404, 503]) {
    test(
      'HTTP $code remains an explicit stream error for fallback policy',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final api = BackendApiService(
          raceStreamClientFactory: () => HttpClient()
            ..connectionFactory = (uri, proxyHost, proxyPort) =>
                Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
        );
        final serving = server.listen((request) {
          request.response.statusCode = code;
          unawaited(request.response.close());
        });
        await expectLater(
          api.watchRaceChanges(identityToken: 'token', raceId: 'a'),
          emitsError(
            isA<RaceChangeStreamException>().having(
              (e) => e.statusCode,
              'status',
              code,
            ),
          ),
        );
        await serving.cancel();
        await server.close(force: true);
      },
    );
  }
}
