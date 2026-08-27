import 'package:flutter/foundation.dart';

enum InterstitialPlacement {
  raceDetailExit('race_detail_exit'),
  raceResultsExit('race_results_exit');

  const InterstitialPlacement(this.wireName);
  final String wireName;

  static InterstitialPlacement? tryParse(Object? raw) {
    for (final value in values) {
      if (raw == value.wireName) return value;
    }
    return null;
  }
}

@immutable
class InterstitialEligibility {
  const InterstitialEligibility({
    required this.eligible,
    this.reason,
    this.dailyCount = 0,
    this.dailyLimit = 2,
    this.nextEligibleAt,
    this.capDate,
    this.timeZone,
    this.serverTime,
  });

  static const ineligible = InterstitialEligibility(eligible: false);

  final bool eligible;
  final String? reason;
  final int dailyCount;
  final int dailyLimit;
  final DateTime? nextEligibleAt;
  final String? capDate;
  final String? timeZone;
  final DateTime? serverTime;

  static InterstitialEligibility tryParse(Object? raw) {
    if (raw is! Map) return ineligible;
    final eligible = raw['eligible'] == true;
    final reason = raw['reason'];
    final dailyCount = raw['dailyCount'];
    final dailyLimit = raw['dailyLimit'];
    final capDate = raw['capDate'];
    final timeZone = raw['timeZone'];
    final serverTime = _date(raw['serverTime']);
    final nextEligibleAt = _date(raw['nextEligibleAt']);
    if (!eligible &&
        reason == 'invalid_timezone' &&
        dailyCount is num &&
        dailyCount >= 0 &&
        dailyLimit is num &&
        dailyLimit > 0 &&
        serverTime != null) {
      return InterstitialEligibility(
        eligible: false,
        reason: reason,
        dailyCount: dailyCount.toInt(),
        dailyLimit: dailyLimit.toInt(),
        serverTime: serverTime,
      );
    }
    if (dailyCount is! num ||
        dailyCount < 0 ||
        dailyLimit is! num ||
        dailyLimit <= 0 ||
        capDate is! String ||
        capDate.isEmpty ||
        timeZone is! String ||
        timeZone.isEmpty ||
        serverTime == null) {
      return ineligible;
    }
    if (eligible && reason != null) return ineligible;
    if (!eligible && reason is! String) return ineligible;
    return InterstitialEligibility(
      eligible: eligible,
      reason: reason is String ? reason : null,
      dailyCount: dailyCount.toInt(),
      dailyLimit: dailyLimit.toInt(),
      nextEligibleAt: nextEligibleAt,
      capDate: capDate,
      timeZone: timeZone,
      serverTime: serverTime,
    );
  }
}

@immutable
class InterstitialPermit {
  const InterstitialPermit({
    required this.id,
    required this.placement,
    required this.sessionId,
    required this.showBy,
    required this.reservationUntil,
  });

  final String id;
  final InterstitialPlacement placement;
  final String sessionId;
  final DateTime showBy;
  final DateTime reservationUntil;

  bool canBeginShow(DateTime now) =>
      showBy.difference(now.toUtc()) >= const Duration(seconds: 15);

  static InterstitialPermit? tryParse(
    Object? raw, {
    required InterstitialPlacement expectedPlacement,
    required String expectedSessionId,
    required DateTime now,
  }) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final placement = InterstitialPlacement.tryParse(raw['placement']);
    final sessionId = raw['sessionId'];
    final showBy = _date(raw['showBy']);
    final reservationUntil = _date(raw['reservationUntil']);
    if (id is! String ||
        !_canonicalUuid.hasMatch(id) ||
        placement != expectedPlacement ||
        sessionId != expectedSessionId ||
        showBy == null ||
        reservationUntil == null ||
        !reservationUntil.isAfter(showBy)) {
      return null;
    }
    final permit = InterstitialPermit(
      id: id,
      placement: placement!,
      sessionId: sessionId as String,
      showBy: showBy,
      reservationUntil: reservationUntil,
    );
    return permit.canBeginShow(now) ? permit : null;
  }
}

@immutable
class InterstitialPermitGrant {
  const InterstitialPermitGrant({
    required this.eligible,
    this.reason,
    this.permit,
    this.capDate,
    this.timeZone,
    this.serverTime,
  });

  static const ineligible = InterstitialPermitGrant(eligible: false);

  final bool eligible;
  final String? reason;
  final InterstitialPermit? permit;
  final String? capDate;
  final String? timeZone;
  final DateTime? serverTime;

  static InterstitialPermitGrant tryParse(
    Object? raw, {
    required InterstitialPlacement expectedPlacement,
    required String expectedSessionId,
    required DateTime now,
  }) {
    if (raw is! Map) return ineligible;
    if (raw['eligible'] != true) {
      final reason = raw['reason'];
      return InterstitialPermitGrant(
        eligible: false,
        reason: reason is String && reason.isNotEmpty ? reason : null,
      );
    }
    final capDate = raw['capDate'];
    final timeZone = raw['timeZone'];
    final serverTime = _date(raw['serverTime']);
    final permit = InterstitialPermit.tryParse(
      raw['permit'],
      expectedPlacement: expectedPlacement,
      expectedSessionId: expectedSessionId,
      now: now,
    );
    if (permit == null ||
        capDate is! String ||
        capDate.isEmpty ||
        timeZone is! String ||
        timeZone.isEmpty ||
        serverTime == null) {
      return ineligible;
    }
    return InterstitialPermitGrant(
      eligible: true,
      permit: permit,
      capDate: capDate,
      timeZone: timeZone,
      serverTime: serverTime,
    );
  }
}

DateTime? _date(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

final RegExp _canonicalUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
