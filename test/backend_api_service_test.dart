import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  group('describeBackendConnectionError', () {
    final uri = Uri.parse('http://192.168.1.188:3000');
    final productionUri = Uri.parse('https://steptracker-api.org');

    test('returns a generic message after a socket failure', () {
      final message = describeBackendConnectionError(
        const SocketException('Connection refused'),
        uri: uri,
      );

      expect(
        message,
        "Can't connect right now. Check your internet connection and try again.",
      );
    });

    test('returns a generic message for insecure HTTP failures on iOS', () {
      final message = describeBackendConnectionError(
        const HttpException(
          'App Transport Security policy requires the use of a secure connection',
        ),
        uri: uri,
      );

      expect(message, 'Secure connection failed. Please try again later.');
    });

    test('reports request timeouts distinctly without leaking the host', () {
      final message = describeBackendConnectionError(
        TimeoutException('Request timed out'),
        uri: uri,
      );

      expect(
        message,
        'Connection timed out. Check your internet connection and try again.',
      );
      expect(message, isNot(contains('192.168.1.188:3000')));
    });

    test('does not leak the production hostname in user-facing errors', () {
      final message = describeBackendConnectionError(
        const SocketException('Connection refused'),
        uri: productionUri,
      );

      expect(message, isNot(contains('steptracker-api.org')));
    });
  });
}
