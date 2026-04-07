import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_timezone/flutter_timezone.dart';

import '../config/backend_config.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';

/// An API error with a user-friendly message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

String describeBackendConnectionError(Object error, {required Uri uri}) {
  final target = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  if (error is TimeoutException) {
    return 'Request to $target timed out. Make sure the backend is running and reachable from this device.';
  }

  if (error is SocketException) {
    final isLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';

    if (isLoopback) {
      return "Can't reach the backend at $target. On a physical iPhone, localhost points to the phone itself. Use your Mac's LAN IP instead.";
    }

    return "Can't reach the backend at $target. Make sure the backend is listening on 0.0.0.0:${uri.port}, your Mac and iPhone are on the same Wi-Fi, and macOS isn't blocking the port.";
  }

  if (error is HandshakeException) {
    return 'Secure connection to $target failed. Check the backend HTTPS certificate and TLS configuration.';
  }

  if (error is HttpException) {
    if (error.message.contains('App Transport Security')) {
      return 'iOS blocked insecure HTTP to $target because of App Transport Security. Use HTTPS or allow local HTTP in the iOS Runner target.';
    }

    return 'Backend request to $target failed: ${error.message}';
  }

  return 'Could not connect to the backend at $target. Check the server URL and local network access.';
}

class BackendApiService {
  BackendApiService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = _requestTimeout;
  }

  static const Duration _requestTimeout = Duration(seconds: 15);
  final HttpClient _httpClient;
  String? _cachedTimeZone;

  Future<String> _getTimeZone() async {
    _cachedTimeZone ??= await FlutterTimezone.getLocalTimezone();
    return _cachedTimeZone!;
  }

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

    return payload;
  }

  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/auth/session',
      identityToken: authToken,
    );

    return _decodeJsonResponse(response);
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

  Future<void> recordStepSamples({
    required String identityToken,
    required List<StepSampleData> samples,
  }) async {
    if (samples.isEmpty) return;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/steps/samples',
      body: {'samples': samples.map((s) => s.toJson()).toList()},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
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

  Future<Map<String, dynamic>> checkDisplayName({
    required String identityToken,
    required String name,
  }) async {
    final response = await _sendGetRequest(
      path: '/auth/check-display-name?name=${Uri.encodeComponent(name)}',
      identityToken: identityToken,
    );

    return await _decodeJsonResponse(response);
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

  Future<void> removeFriend({
    required String identityToken,
    required String friendshipId,
  }) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/friends/$friendshipId',
      body: {},
      identityToken: identityToken,
    );
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

  Future<Map<String, dynamic>> initiateChallenge({
    required String identityToken,
    required String friendUserId,
    required String stakeId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/challenges/initiate',
      body: {'friendUserId': friendUserId, 'stakeId': stakeId},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<List<Map<String, dynamic>>> fetchStakeCatalog({
    required String identityToken,
    String? relationshipType,
  }) async {
    final query = relationshipType != null
        ? '?relationship_type=${Uri.encodeComponent(relationshipType)}'
        : '';
    final response = await _sendGetRequest(
      path: '/stakes$query',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final stakes = payload['stakes'];

    if (stakes is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return stakes.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> proposeStake({
    required String identityToken,
    required String instanceId,
    required String stakeId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/challenges/$instanceId/propose-stake',
      body: {'stakeId': stakeId},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> respondToStake({
    required String identityToken,
    required String instanceId,
    required bool accept,
    String? counterStakeId,
  }) async {
    final body = <String, dynamic>{'accept': accept};
    if (counterStakeId != null) body['counterStakeId'] = counterStakeId;

    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/challenges/$instanceId/respond-stake',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchChallengeProgress({
    required String identityToken,
    required String instanceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/challenges/$instanceId/progress',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    return payload['progress'] as Map<String, dynamic>;
  }

  Future<void> cancelChallenge({
    required String identityToken,
    required String instanceId,
  }) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/challenges/$instanceId',
      body: {},
      identityToken: identityToken,
    );
  }

  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/challenges/current',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
  }) async {
    final uri = Uri(
      path: '/leaderboard',
      queryParameters: {'type': type, 'period': period},
    );

    final response = await _sendGetRequest(
      path: uri.toString(),
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchLeaderboardHighlights({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/leaderboard/highlights',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps/stats',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps/calendar?month=$month',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<List<Map<String, dynamic>>> fetchStepsHistory({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final records = payload['records'];
    if (records is! List) return [];
    return records.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/weekly-challenge',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> ensureAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/admin/weekly-challenge/ensure-current',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> resolveAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/admin/weekly-challenge/resolve-current',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> resetAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/admin/weekly-challenge/reset-current',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<void> registerDeviceToken({
    required String identityToken,
    required String deviceToken,
    required String platform,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/notifications/device-token',
      body: {'deviceToken': deviceToken, 'platform': platform},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  // -- Races --

  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    required int targetSteps,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'targetSteps': targetSteps,
      'maxDurationDays': maxDurationDays,
    };
    if (powerupsEnabled) {
      body['powerupsEnabled'] = true;
      body['powerupStepInterval'] = powerupStepInterval;
    }

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/races',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> inviteToRace({
    required String identityToken,
    required String raceId,
    required List<String> inviteeIds,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/invite',
      body: {'inviteeIds': inviteeIds},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/respond',
      body: {'accept': accept},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> startRace({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/start',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId/progress',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    return payload['progress'] as Map<String, dynamic>;
  }

  Future<void> cancelRace({
    required String identityToken,
    required String raceId,
  }) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/races/$raceId',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
  }

  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
  }) async {
    final body = <String, dynamic>{};
    if (targetUserId != null) body['targetUserId'] = targetUserId;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/use',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/open',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/discard',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceInventory({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId/inventory',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
  }) async {
    final query = cursor != null
        ? '?cursor=${Uri.encodeComponent(cursor)}'
        : '';
    final response = await _sendGetRequest(
      path: '/races/$raceId/feed$query',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<void> unregisterDeviceToken({
    required String identityToken,
    required String deviceToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/notifications/device-token',
      body: {'deviceToken': deviceToken},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  Future<HttpClientResponse> _sendGetRequest({
    required String path,
    String? identityToken,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');

    try {
      final request = await _httpClient.openUrl('GET', uri);
      if (identityToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $identityToken',
        );
      }
      request.headers.set('X-Timezone', await _getTimeZone());
      return await request.close().timeout(_requestTimeout);
    } on SocketException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on TimeoutException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HandshakeException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HttpException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    }
  }

  Future<HttpClientResponse> _sendJsonRequest({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    String? identityToken,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');

    try {
      final request = await _httpClient.openUrl(method, uri);

      request.headers.contentType = ContentType.json;

      if (identityToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $identityToken',
        );
      }
      request.headers.set('X-Timezone', await _getTimeZone());

      request.write(jsonEncode(body));

      return await request.close().timeout(_requestTimeout);
    } on SocketException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on TimeoutException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HandshakeException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HttpException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    }
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
      throw ApiException(message, statusCode: response.statusCode);
    }

    throw ApiException(
      'Something went wrong. Please try again.',
      statusCode: response.statusCode,
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}
