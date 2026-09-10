enum RaceCardState {
  pendingInvite,
  activeRace,
  friendRacing,
  friendFinished,
  publicRace,
  empty,
}

class RaceCardUser {
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final List<Map<String, dynamic>> accessories;

  const RaceCardUser({
    required this.userId,
    required this.displayName,
    this.profilePhotoUrl,
    this.accessories = const [],
  });

  static RaceCardUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawAccessories = json['accessories'];
    final accessories = rawAccessories is List
        ? rawAccessories.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    return RaceCardUser(
      userId: json['userId'] is String ? json['userId'] as String : '',
      displayName: json['displayName'] is String
          ? json['displayName'] as String
          : 'Anonymous',
      profilePhotoUrl: json['profilePhotoUrl'] is String
          ? json['profilePhotoUrl'] as String
          : null,
      accessories: accessories,
    );
  }
}

class RaceCardData {
  final RaceCardState state;
  final int pendingInviteCount;
  final Map<String, dynamic> data;

  const RaceCardData({
    required this.state,
    this.pendingInviteCount = 0,
    this.data = const {},
  });

  static RaceCardData fromJson(Map<String, dynamic> json) {
    final state = json['state'];
    final stateStr = state is String ? state.toUpperCase() : 'EMPTY';
    final rawData = json['data'];
    final count = json['pendingInviteCount'];
    return RaceCardData(
      state: _stateFromString(stateStr),
      pendingInviteCount: count is num && count.isFinite ? count.toInt() : 0,
      data: rawData is Map
          ? {
              for (final entry in rawData.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }
          : const {},
    );
  }

  static RaceCardState _stateFromString(String s) {
    switch (s) {
      case 'PENDING_INVITE':
        return RaceCardState.pendingInvite;
      case 'ACTIVE_RACE':
        return RaceCardState.activeRace;
      case 'FRIEND_RACING':
        return RaceCardState.friendRacing;
      case 'FRIEND_FINISHED':
        return RaceCardState.friendFinished;
      case 'PUBLIC_RACE':
        return RaceCardState.publicRace;
      default:
        return RaceCardState.empty;
    }
  }
}
