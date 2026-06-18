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

  static RaceCardUser? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final accessories = (json['accessories'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    return RaceCardUser(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Anonymous',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
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
    final stateStr = (json['state'] as String? ?? 'EMPTY').toUpperCase();
    return RaceCardData(
      state: _stateFromString(stateStr),
      pendingInviteCount: (json['pendingInviteCount'] as int?) ?? 0,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
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
