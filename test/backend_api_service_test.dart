import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  group('describeBackendConnectionError', () {
    final uri = Uri.parse('http://192.168.1.188:3000');

    test('explains how to reach a LAN backend after a socket failure', () {
      final message = describeBackendConnectionError(
        const SocketException('Connection refused'),
        uri: uri,
      );

      expect(message, contains("Can't reach the backend"));
      expect(message, contains('192.168.1.188:3000'));
      expect(message, contains('0.0.0.0'));
      expect(message, contains('same Wi-Fi'));
    });

    test('surfaces ATS guidance for insecure HTTP failures on iOS', () {
      final message = describeBackendConnectionError(
        const HttpException(
          'App Transport Security policy requires the use of a secure connection',
        ),
        uri: uri,
      );

      expect(message, contains('iOS blocked insecure HTTP'));
      expect(message, contains('HTTPS'));
      expect(message, contains('App Transport Security'));
    });

    test('reports request timeouts distinctly', () {
      final message = describeBackendConnectionError(
        TimeoutException('Request timed out'),
        uri: uri,
      );

      expect(message, contains('timed out'));
      expect(message, contains('192.168.1.188:3000'));
    });
  });
}
