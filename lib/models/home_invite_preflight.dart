/// Defensive, capability-scoped Home invitation preflight DTO. The Home
/// overlay must never infer invitation state from a legacy races response.
enum HomeInviteKind { race, tournament }

class HomeInvite {
  const HomeInvite({
    required this.kind,
    required this.id,
    required this.name,
    required this.status,
    this.createdAt,
    this.scheduledStartAt,
    this.inviteExpiresAt,
    this.durationDays,
    this.isTeamRace = false,
    this.requiresTeamRaceSupport = false,
    this.buyInAmount = 0,
    this.creatorName,
  });

  final HomeInviteKind kind;
  final String id;
  final String name;
  final String status;
  final DateTime? createdAt;
  final DateTime? scheduledStartAt;
  final DateTime? inviteExpiresAt;
  final int? durationDays;
  final bool isTeamRace;
  final bool requiresTeamRaceSupport;
  final int buyInAmount;
  final String? creatorName;

  bool get isTournament => kind == HomeInviteKind.tournament;

  static HomeInvite? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = <String, dynamic>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final rawKind = map['kind'];
    final kind = switch (rawKind) {
      'RACE' => HomeInviteKind.race,
      'TOURNAMENT' => HomeInviteKind.tournament,
      _ => null,
    };
    final id = map['id'];
    if (kind == null || id is! String || id.trim().isEmpty) return null;
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;
    final creator = map['creator'];
    final creatorName = creator is Map && creator['displayName'] is String
        ? (creator['displayName'] as String).trim()
        : null;
    final name = map['name'];
    final status = map['status'];
    final rawDuration = kind == HomeInviteKind.tournament
        ? map['matchupDurationDays']
        : map['maxDurationDays'];
    final rawBuyIn = map['buyInAmount'];
    return HomeInvite(
      kind: kind,
      id: id.trim(),
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : (kind == HomeInviteKind.tournament
                ? 'Bracket invitation'
                : 'Race invitation'),
      status: status is String ? status : 'PENDING',
      createdAt: date(map['createdAt']),
      scheduledStartAt: date(map['scheduledStartAt']),
      inviteExpiresAt: date(map['myInviteExpiresAt']),
      durationDays: rawDuration is num && rawDuration >= 0
          ? rawDuration.toInt()
          : null,
      isTeamRace: map['isTeamRace'] == true,
      requiresTeamRaceSupport: map['requiresTeamRaceSupport'] == true,
      buyInAmount: rawBuyIn is num && rawBuyIn > 0 ? rawBuyIn.toInt() : 0,
      creatorName: creatorName == null || creatorName.isEmpty
          ? null
          : creatorName,
    );
  }
}

class HomeInvitePreflight {
  const HomeInvitePreflight({required this.supported, required this.invites});

  final bool supported;
  final List<HomeInvite> invites;

  static HomeInvitePreflight tryParse(Map<String, dynamic> json) {
    // Missing/false `resolved` is intentionally unsupported/no-prompt, not an
    // empty invitation list; an old server cannot safely drive Home UI.
    if (json['resolved'] != true || json['supported'] == false) {
      return const HomeInvitePreflight(supported: false, invites: []);
    }
    final raw = json['invites'];
    if (raw is! List) {
      return const HomeInvitePreflight(supported: false, invites: []);
    }
    final invites =
        raw
            .map(HomeInvite.tryParse)
            .whereType<HomeInvite>()
            .toList(growable: false)
          ..sort(_compare);
    return HomeInvitePreflight(supported: true, invites: invites);
  }

  static int _compare(HomeInvite a, HomeInvite b) {
    if (a.kind != b.kind) {
      return a.isTournament ? -1 : 1;
    }
    DateTime? sortDate(HomeInvite invite) => invite.isTournament
        ? invite.createdAt
        : (invite.inviteExpiresAt ??
              invite.scheduledStartAt ??
              invite.createdAt);
    final ad = sortDate(a);
    final bd = sortDate(b);
    if (ad != null && bd != null) {
      final comparison = ad.compareTo(bd);
      if (comparison != 0) return comparison;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return a.id.compareTo(b.id);
  }
}
