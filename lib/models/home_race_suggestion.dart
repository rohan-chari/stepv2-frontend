import 'loadable.dart';

enum HomeRaceSuggestionKind { featuredRace, publicRace, tournament }

enum HomeRaceSuggestionCategory { featuredRaces, publicRaces, tournaments }

/// One validated entry from the additive Home discovery contract.
///
/// Parsing is intentionally strict for every required contract field: a
/// malformed row costs one card, never the whole carousel. Optional values are
/// exposed through typed, nullable fields so rendering never reaches back into
/// untrusted JSON.
class HomeRaceSuggestion {
  const HomeRaceSuggestion._({
    required this.kind,
    required this.id,
    required this.name,
    required this.status,
    required this.participantCount,
    required this.powerupsEnabled,
    required this.raw,
    this.seedKind,
    this.endsAt,
    this.startedAt,
    this.maxParticipants,
    this.maxDurationDays,
    this.buyInAmount = 0,
    this.payoutPreset,
    this.prizePool,
    this.finishReward,
    this.isTeamRace = false,
    this.teamSize,
    this.teamAName,
    this.teamBName,
    this.teams,
    this.bracketSize,
    this.matchupDurationDays,
    this.potCoins,
    this.powerupStepInterval,
    this.createdAt,
  });

  final HomeRaceSuggestionKind kind;
  final String id;
  final String name;
  final String status;
  final String? seedKind;
  final DateTime? endsAt;
  final DateTime? startedAt;
  final int participantCount;
  final int? maxParticipants;
  final int? maxDurationDays;
  final int buyInAmount;
  final String? payoutPreset;
  final bool powerupsEnabled;
  final Map<String, dynamic>? prizePool;
  final Map<String, dynamic>? finishReward;
  final bool isTeamRace;
  final int? teamSize;
  final String? teamAName;
  final String? teamBName;
  final Map<String, dynamic>? teams;
  final int? bracketSize;
  final int? matchupDurationDays;
  final int? potCoins;
  final int? powerupStepInterval;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  HomeRaceSuggestionCategory get category => switch (kind) {
    HomeRaceSuggestionKind.featuredRace =>
      HomeRaceSuggestionCategory.featuredRaces,
    HomeRaceSuggestionKind.publicRace => HomeRaceSuggestionCategory.publicRaces,
    HomeRaceSuggestionKind.tournament => HomeRaceSuggestionCategory.tournaments,
  };

  String get wireKind => switch (kind) {
    HomeRaceSuggestionKind.featuredRace => 'FEATURED_RACE',
    HomeRaceSuggestionKind.publicRace => 'PUBLIC_RACE',
    HomeRaceSuggestionKind.tournament => 'TOURNAMENT',
  };

  String get stableKey => '$wireKind:$id';

  String get eyebrow {
    if (kind == HomeRaceSuggestionKind.featuredRace) {
      return seedKind == 'DAILY_10K' ? 'DAILY' : 'WEEKLY';
    }
    return kind == HomeRaceSuggestionKind.publicRace ? 'PUBLIC' : 'TOURNAMENT';
  }

  static HomeRaceSuggestion? tryParse(dynamic value) {
    if (value is! Map) return null;
    final json = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) json[entry.key as String] = entry.value;
    }
    final kind = json['kind'];
    return switch (kind) {
      'FEATURED_RACE' => _parseFeatured(json),
      'PUBLIC_RACE' => _parsePublic(json),
      'TOURNAMENT' => _parseTournament(json),
      _ => null,
    };
  }

  static HomeRaceSuggestion? _parseFeatured(Map<String, dynamic> json) {
    final id = _nonempty(json['id']);
    final name = _nonempty(json['name']);
    final seedKind = json['seedKind'];
    final endsAt = _date(json['endsAt']);
    final participantCount = _nonnegative(json['participantCount']);
    final maxParticipants = _positive(json['maxParticipants']);
    if (!_hasAll(json, const [
          'kind',
          'id',
          'seedKind',
          'name',
          'status',
          'endsAt',
          'participantCount',
          'maxParticipants',
          'isFull',
          'powerupsEnabled',
          'prizePool',
          'finishReward',
          'joinAction',
        ]) ||
        id == null ||
        name == null ||
        (seedKind != 'DAILY_10K' && seedKind != 'WEEKLY_50K') ||
        json['status'] != 'ACTIVE' ||
        endsAt == null ||
        participantCount == null ||
        maxParticipants == null ||
        json['isFull'] is! bool ||
        json['powerupsEnabled'] is! bool ||
        !_nullableMap(json['prizePool']) ||
        !_nullableMap(json['finishReward']) ||
        json['joinAction'] != 'JOIN') {
      return null;
    }
    return HomeRaceSuggestion._(
      kind: HomeRaceSuggestionKind.featuredRace,
      id: id,
      name: name,
      status: 'ACTIVE',
      seedKind: seedKind as String,
      endsAt: endsAt,
      participantCount: participantCount,
      maxParticipants: maxParticipants,
      powerupsEnabled: json['powerupsEnabled'] as bool,
      prizePool: _map(json['prizePool']),
      finishReward: _map(json['finishReward']),
      raw: json,
    );
  }

  static HomeRaceSuggestion? _parsePublic(Map<String, dynamic> json) {
    final id = _nonempty(json['id']);
    final name = _nonempty(json['name']);
    final status = json['status'];
    final duration = _positive(json['maxDurationDays']);
    final participantCount = _nonnegative(json['participantCount']);
    final buyIn = _nonnegative(json['buyInAmount']);
    final maxParticipants = json['maxParticipants'] == null
        ? null
        : _positive(json['maxParticipants']);
    final endsAt = json['endsAt'] == null ? null : _date(json['endsAt']);
    final startedAt = json['startedAt'] == null
        ? null
        : _date(json['startedAt']);
    if (!_hasAll(json, const [
          'kind',
          'id',
          'name',
          'status',
          'maxDurationDays',
          'endsAt',
          'startedAt',
          'participantCount',
          'maxParticipants',
          'buyInAmount',
          'payoutPreset',
          'powerupsEnabled',
          'prizePool',
          'isTeamRace',
          'teamSize',
          'teamAName',
          'teamBName',
          'teams',
          'joinAction',
        ]) ||
        id == null ||
        name == null ||
        (status != 'PENDING' && status != 'ACTIVE') ||
        duration == null ||
        participantCount == null ||
        buyIn == null ||
        (json['maxParticipants'] != null && maxParticipants == null) ||
        (json['endsAt'] != null && endsAt == null) ||
        (json['startedAt'] != null && startedAt == null) ||
        !_nullableString(json['payoutPreset']) ||
        json['powerupsEnabled'] is! bool ||
        !_nullableMap(json['prizePool']) ||
        json['isTeamRace'] is! bool ||
        !_nullablePositive(json['teamSize']) ||
        !_nullableString(json['teamAName']) ||
        !_nullableString(json['teamBName']) ||
        !_nullableMap(json['teams']) ||
        json['joinAction'] != 'JOIN') {
      return null;
    }
    return HomeRaceSuggestion._(
      kind: HomeRaceSuggestionKind.publicRace,
      id: id,
      name: name,
      status: status as String,
      endsAt: endsAt,
      startedAt: startedAt,
      participantCount: participantCount,
      maxParticipants: maxParticipants,
      maxDurationDays: duration,
      buyInAmount: buyIn,
      payoutPreset: json['payoutPreset'] as String?,
      powerupsEnabled: json['powerupsEnabled'] as bool,
      prizePool: _map(json['prizePool']),
      isTeamRace: json['isTeamRace'] as bool,
      teamSize: json['teamSize'] as int?,
      teamAName: json['teamAName'] as String?,
      teamBName: json['teamBName'] as String?,
      teams: _map(json['teams']),
      raw: json,
    );
  }

  static HomeRaceSuggestion? _parseTournament(Map<String, dynamic> json) {
    final id = _nonempty(json['id']);
    final name = _nonempty(json['name']);
    final bracketSize = _positive(json['bracketSize']);
    final duration = _positive(json['matchupDurationDays']);
    final accepted = _nonnegative(json['acceptedCount']);
    final buyIn = _nonnegative(json['buyInAmount']);
    final pot = _nonnegative(json['potCoins']);
    final createdAt = _date(json['createdAt']);
    if (!_hasAll(json, const [
          'kind',
          'id',
          'seedKind',
          'name',
          'status',
          'bracketSize',
          'matchupDurationDays',
          'acceptedCount',
          'buyInAmount',
          'potCoins',
          'prizePool',
          'powerupsEnabled',
          'powerupStepInterval',
          'createdAt',
          'joinAction',
        ]) ||
        id == null ||
        name == null ||
        json['status'] != 'PENDING' ||
        bracketSize == null ||
        duration == null ||
        accepted == null ||
        buyIn == null ||
        pot == null ||
        !_nullableString(json['seedKind']) ||
        !_nullableMap(json['prizePool']) ||
        json['powerupsEnabled'] is! bool ||
        !_nullablePositive(json['powerupStepInterval']) ||
        createdAt == null ||
        json['joinAction'] != 'JOIN') {
      return null;
    }
    return HomeRaceSuggestion._(
      kind: HomeRaceSuggestionKind.tournament,
      id: id,
      name: name,
      status: 'PENDING',
      seedKind: json['seedKind'] as String?,
      participantCount: accepted,
      bracketSize: bracketSize,
      matchupDurationDays: duration,
      buyInAmount: buyIn,
      potCoins: pot,
      prizePool: _map(json['prizePool']),
      powerupsEnabled: json['powerupsEnabled'] as bool,
      powerupStepInterval: json['powerupStepInterval'] as int?,
      createdAt: createdAt,
      raw: json,
    );
  }

  static String? _nonempty(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  static DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
  static int? _nonnegative(dynamic value) =>
      value is int && value >= 0 ? value : null;
  static int? _positive(dynamic value) =>
      value is int && value > 0 ? value : null;
  static bool _nullablePositive(dynamic value) =>
      value == null || _positive(value) != null;
  static bool _nullableString(dynamic value) =>
      value == null || value is String;
  static bool _nullableMap(dynamic value) => value == null || value is Map;
  static bool _hasAll(Map<String, dynamic> json, List<String> keys) =>
      keys.every(json.containsKey);
  static Map<String, dynamic>? _map(dynamic value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}

/// A category-aware refresh. Null means unresolved/retain; an empty list means
/// resolved-empty/replace.
class HomeSuggestedRacesRefresh {
  const HomeSuggestedRacesRefresh({
    this.featuredRaces,
    this.publicRaces,
    this.tournaments,
    this.error,
  });

  final List<HomeRaceSuggestion>? featuredRaces;
  final List<HomeRaceSuggestion>? publicRaces;
  final List<HomeRaceSuggestion>? tournaments;
  final String? error;

  bool get anyResolved =>
      featuredRaces != null || publicRaces != null || tournaments != null;
  bool get allResolved =>
      featuredRaces != null && publicRaces != null && tournaments != null;
}

/// MainShell-owned merge mechanics extracted for deterministic tests.
class HomeSuggestedRacesStore {
  final Map<HomeRaceSuggestionCategory, List<HomeRaceSuggestion>> _categories =
      {
        HomeRaceSuggestionCategory.featuredRaces: const [],
        HomeRaceSuggestionCategory.publicRaces: const [],
        HomeRaceSuggestionCategory.tournaments: const [],
      };
  final Set<String> _tombstones = {};
  int _generation = 0;
  String? _userId;
  bool _hasCommitted = false;
  Loadable<List<HomeRaceSuggestion>> state = const Loadable.initial();

  int beginRefresh() {
    final generation = ++_generation;
    final previous = _visible;
    state = previous.isEmpty
        ? const Loadable.loading()
        : Loadable.refreshing(previous);
    return generation;
  }

  bool apply(int generation, HomeSuggestedRacesRefresh refresh) {
    if (generation != _generation) return false;
    if (!refresh.anyResolved) {
      final previous = _visible;
      if (_hasCommitted) {
        state = Loadable.success(previous);
        return true;
      }
      state = Loadable.error(
        refresh.error ?? 'Could not load suggested races.',
        data: previous.isEmpty ? null : previous,
      );
      return true;
    }
    _replace(HomeRaceSuggestionCategory.featuredRaces, refresh.featuredRaces);
    _replace(HomeRaceSuggestionCategory.publicRaces, refresh.publicRaces);
    _replace(HomeRaceSuggestionCategory.tournaments, refresh.tournaments);
    _hasCommitted = true;
    state = Loadable.success(_visible);
    return true;
  }

  void tombstone(HomeRaceSuggestion suggestion) {
    _tombstones.add(suggestion.stableKey);
    state = Loadable.success(_visible);
  }

  void setUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _generation++;
    _tombstones.clear();
    _hasCommitted = false;
    for (final category in HomeRaceSuggestionCategory.values) {
      _categories[category] = const [];
    }
    state = const Loadable.initial();
  }

  void _replace(
    HomeRaceSuggestionCategory category,
    List<HomeRaceSuggestion>? fresh,
  ) {
    if (fresh == null) return;
    final freshKeys = fresh.map((item) => item.stableKey).toSet();
    _tombstones.removeWhere((key) {
      final belongs = key.startsWith(_wirePrefix(category));
      return belongs && !freshKeys.contains(key);
    });
    _categories[category] = List.unmodifiable(fresh);
  }

  String _wirePrefix(HomeRaceSuggestionCategory category) => switch (category) {
    HomeRaceSuggestionCategory.featuredRaces => 'FEATURED_RACE:',
    HomeRaceSuggestionCategory.publicRaces => 'PUBLIC_RACE:',
    HomeRaceSuggestionCategory.tournaments => 'TOURNAMENT:',
  };

  List<HomeRaceSuggestion> get _visible => List.unmodifiable(
    [
      ...?_categories[HomeRaceSuggestionCategory.featuredRaces],
      ...?_categories[HomeRaceSuggestionCategory.publicRaces],
      ...?_categories[HomeRaceSuggestionCategory.tournaments],
    ].where((item) => !_tombstones.contains(item.stableKey)),
  );
}
