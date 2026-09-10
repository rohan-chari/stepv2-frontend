/// Negotiated Home catch-up representation. Only a complete, known core can
/// replace the previous Home snapshot; absent optional sections are not merged.
class HomeSyncRefreshResult {
  const HomeSyncRefreshResult._({this.home, this.unsupported = false});

  static const unavailable = HomeSyncRefreshResult._();
  static const unsupportedResult = HomeSyncRefreshResult._(unsupported: true);
  final Map<String, dynamic>? home;
  final bool unsupported;

  static HomeSyncRefreshResult parse(Object? payload) {
    if (payload is! Map || payload['contract'] != 'home-sync-refresh-v1') {
      return unsupportedResult;
    }
    final retained = payload['retainedSections'];
    final core = payload['home'];
    if (retained is! List ||
        retained.length != 2 ||
        retained[0] != 'presentation' ||
        retained[1] != 'friends' ||
        core is! Map ||
        core.keys.any((key) => key is! String) ||
        const [
          'contract',
          'resolved',
          'presentation',
          'friends',
        ].any(core.containsKey)) {
      return unsupportedResult;
    }
    final data = core['data'];
    if (core['state'] is! String || data is! Map) return unsupportedResult;
    bool objectList(Object? value) =>
        value is List && value.every((row) => row is Map);
    bool raceId(Object? value) => value is String && value.trim().isNotEmpty;
    final valid = switch (core['state']) {
      'EMPTY' => true,
      'ACTIVE_RACES' =>
        data['races'] is List &&
            (data['races'] as List).every(
              (row) => row is Map && raceId(row['raceId']),
            ),
      'ACTIVE_RACE' =>
        raceId(data['raceId']) &&
            (data['me'] == null || data['me'] is Map) &&
            (data['leader'] == null || data['leader'] is Map) &&
            objectList(data['others']),
      'PENDING_INVITE' || 'PUBLIC_RACE' => raceId(data['raceId']),
      'FRIEND_RACING' =>
        raceId(data['raceId']) &&
            data['friend'] is Map &&
            objectList(data['participants']),
      'FRIEND_FINISHED' => data['friend'] is Map && data['raceName'] is String,
      _ => false,
    };
    if (!valid) return unsupportedResult;
    return HomeSyncRefreshResult._(home: Map<String, dynamic>.from(core));
  }
}
