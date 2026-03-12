import 'dart:convert';
import 'dart:io';

import '../config/backend_config.dart';
import '../models/step_data.dart';

class BackendApiService {
  BackendApiService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<Map<String, dynamic>> provisionAppleUser({
    required String identityToken,
    required String userIdentifier,
    String? email,
    String? name,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/apple',
      body: {
        'identityToken': identityToken,
        'userIdentifier': userIdentifier,
        'email': email,
        'name': name,
      },
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const HttpException('Backend did not return a user payload');
    }

    return user;
  }

  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/steps',
      body: {'steps': stepData.steps, 'date': _formatDate(stepData.date)},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  Future<HttpClientResponse> _sendJsonRequest({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    String? identityToken,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      Uri.parse('${BackendConfig.baseUrl}$path'),
    );

    request.headers.contentType = ContentType.json;

    if (identityToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $identityToken',
      );
    }

    request.write(jsonEncode(body));

    return request.close();
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(
    HttpClientResponse response,
  ) async {
    final rawBody = await response.transform(utf8.decoder).join();
    final parsedBody = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return parsedBody;
    }

    final message = parsedBody['error'];

    if (message is String && message.isNotEmpty) {
      throw HttpException(message);
    }

    throw HttpException(
      'Backend request failed with status ${response.statusCode}',
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}
