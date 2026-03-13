import 'dart:convert';
import 'dart:io';

import '../config/backend_config.dart';
import '../models/step_data.dart';

/// An API error with a user-friendly message.
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

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
      throw const ApiException('Something went wrong. Please try again.');
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

  Future<Map<String, dynamic>> fetchMe({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/auth/me',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<Map<String, dynamic>> setStepGoal({
    required String identityToken,
    required int stepGoal,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/step-goal',
      body: {'stepGoal': stepGoal},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<Map<String, dynamic>> setDisplayName({
    required String identityToken,
    required String? displayName,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/display-name',
      body: {'displayName': displayName},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<List<Map<String, dynamic>>> searchUsers({
    required String identityToken,
    required String query,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends/search?q=${Uri.encodeComponent(query)}',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final users = payload['users'];

    if (users is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return users.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> sendFriendRequest({
    required String identityToken,
    required String addresseeId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/friends/request',
      body: {'addresseeId': addresseeId},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> respondToFriendRequest({
    required String identityToken,
    required String friendshipId,
    required bool accept,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/friends/request/$friendshipId',
      body: {'accept': accept},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends/steps?date=${Uri.encodeComponent(date)}',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final friends = payload['friends'];

    if (friends is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return friends.cast<Map<String, dynamic>>();
  }

  Future<HttpClientResponse> _sendGetRequest({
    required String path,
    String? identityToken,
  }) async {
    final request = await _httpClient.openUrl(
      'GET',
      Uri.parse('${BackendConfig.baseUrl}$path'),
    );
    if (identityToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $identityToken',
      );
    }
    return request.close();
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
      throw ApiException(message);
    }

    throw const ApiException('Something went wrong. Please try again.');
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}
