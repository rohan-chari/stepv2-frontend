import 'giveaway.dart';

final class AdminGiveawayCounts {
  const AdminGiveawayCounts({
    required this.entrants,
    required this.reviewableFacts,
    required this.rankedResults,
  });
  final int entrants;
  final int reviewableFacts;
  final int rankedResults;

  static AdminGiveawayCounts? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final entrants = _int(raw['entrants']);
    final reviewable = _int(raw['reviewableFacts']);
    final ranked = _int(raw['rankedResults']);
    if (entrants == null ||
        entrants < 0 ||
        reviewable == null ||
        reviewable < 0 ||
        ranked == null ||
        ranked < 0) {
      return null;
    }
    return AdminGiveawayCounts(
      entrants: entrants,
      reviewableFacts: reviewable,
      rankedResults: ranked,
    );
  }
}

final class AdminGiveawayContest {
  const AdminGiveawayContest({
    required this.id,
    required this.revision,
    required this.slug,
    required this.title,
    required this.status,
    required this.lifecycleStatus,
    required this.governingTimeZone,
    required this.startsAt,
    required this.endsAt,
    required this.cashCurrency,
    required this.cashMinor,
    required this.coinPrize,
    required this.minimumAge,
    required this.eligibleCountries,
    required this.eligibleRegions,
    required this.sponsorLegalName,
    required this.sponsorMailingAddress,
    required this.rules,
    required this.socialLinks,
    required this.bannerMessage,
    required this.counts,
    required this.createdAt,
    required this.updatedAt,
    this.publicReason,
    this.amendedRulesVersion,
    this.publishedAt,
    this.frozenAt,
    this.finalizedAt,
    this.cancelledAt,
    this.archivedAt,
  });

  final String id;
  final int revision;
  final String slug;
  final String title;
  final String status;
  final String lifecycleStatus;
  final String governingTimeZone;
  final DateTime startsAt;
  final DateTime endsAt;
  final String cashCurrency;
  final int cashMinor;
  final int coinPrize;
  final int minimumAge;
  final List<String> eligibleCountries;
  final List<String> eligibleRegions;
  final String sponsorLegalName;
  final String sponsorMailingAddress;
  final GiveawayRules rules;
  final List<GiveawaySocialLink> socialLinks;
  final String bannerMessage;
  final String? publicReason;
  final String? amendedRulesVersion;
  final AdminGiveawayCounts counts;
  final DateTime? publishedAt;
  final DateTime? frozenAt;
  final DateTime? finalizedAt;
  final DateTime? cancelledAt;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => lifecycleStatus == 'DRAFT';
  bool get isPublished => lifecycleStatus == 'PUBLISHED';
  bool get canArchive =>
      lifecycleStatus == 'FINAL' || lifecycleStatus == 'CANCELLED';

  static const _derived = {
    'DRAFT',
    'SCHEDULED',
    'ACTIVE',
    'VERIFYING',
    'FINAL',
    'CANCELLED',
    'ARCHIVED',
  };
  static const _persisted = {
    'DRAFT',
    'PUBLISHED',
    'FINAL',
    'CANCELLED',
    'ARCHIVED',
  };

  static AdminGiveawayContest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _string(raw['id']);
    final revision = _int(raw['revision']);
    final slug = _string(raw['slug']);
    final title = _string(raw['title']);
    final status = _string(raw['status']);
    final lifecycle = _string(raw['lifecycleStatus']);
    final zone = _string(raw['governingTimeZone']);
    final starts = _date(raw['startsAt']);
    final ends = _date(raw['endsAt']);
    final currency = _string(raw['cashCurrency']);
    final cash = _int(raw['cashMinor']);
    final coins = _int(raw['coinPrize']);
    final age = _int(raw['minimumAge']);
    final countries = _strings(raw['eligibleCountries']);
    final regions = _strings(raw['eligibleRegions']);
    final sponsor = raw['sponsor'];
    final legalName = sponsor is Map
        ? _boundedString(sponsor['legalName'], 200)
        : null;
    final address = sponsor is Map
        ? _boundedString(sponsor['mailingAddress'], 500)
        : null;
    final rules = GiveawayRules.tryParse(raw['rules']);
    final linksRaw = raw['socialLinks'];
    final banner = _string(raw['bannerMessage']);
    final counts = AdminGiveawayCounts.tryParse(raw['counts']);
    final created = _date(raw['createdAt']);
    final updated = _date(raw['updatedAt']);
    if (id == null ||
        revision == null ||
        revision < 0 ||
        slug == null ||
        title == null ||
        status == null ||
        !_derived.contains(status) ||
        lifecycle == null ||
        !_persisted.contains(lifecycle) ||
        zone == null ||
        starts == null ||
        ends == null ||
        !ends.isAfter(starts) ||
        currency == null ||
        cash == null ||
        coins == null ||
        age == null ||
        countries == null ||
        regions == null ||
        legalName == null ||
        address == null ||
        rules == null ||
        linksRaw is! List ||
        banner == null ||
        counts == null ||
        created == null ||
        updated == null) {
      return null;
    }
    if (currency != 'USD' ||
        cash != 5000 ||
        coins != 5000 ||
        age != 18 ||
        countries.length != 1 ||
        countries.single != 'US' ||
        !_isExactUsRegionSet(regions)) {
      return null;
    }
    final links = <GiveawaySocialLink>[];
    for (final item in linksRaw) {
      final link = GiveawaySocialLink.tryParse(item);
      if (link == null) return null;
      links.add(link);
    }
    final publicReason = _optionalString(raw, 'publicReason');
    final amended = _optionalString(raw, 'amendedRulesVersion');
    final published = _optionalDate(raw, 'publishedAt');
    final frozen = _optionalDate(raw, 'frozenAt');
    final finalized = _optionalDate(raw, 'finalizedAt');
    final cancelled = _optionalDate(raw, 'cancelledAt');
    final archived = _optionalDate(raw, 'archivedAt');
    if (publicReason.invalid ||
        amended.invalid ||
        published.invalid ||
        frozen.invalid ||
        finalized.invalid ||
        cancelled.invalid ||
        archived.invalid) {
      return null;
    }
    final lifecycleValid = switch (lifecycle) {
      'DRAFT' =>
        status == 'DRAFT' &&
            published.value == null &&
            frozen.value == null &&
            finalized.value == null &&
            cancelled.value == null &&
            archived.value == null &&
            publicReason.value == null &&
            amended.value == null,
      'PUBLISHED' =>
        const {'SCHEDULED', 'ACTIVE', 'VERIFYING'}.contains(status) &&
            published.value != null &&
            frozen.value != null &&
            cancelled.value == null &&
            archived.value == null &&
            publicReason.value == null &&
            amended.value == null &&
            (status == 'VERIFYING' || finalized.value == null),
      'FINAL' =>
        status == 'FINAL' &&
            published.value != null &&
            frozen.value != null &&
            finalized.value != null &&
            cancelled.value == null &&
            archived.value == null &&
            publicReason.value == null &&
            amended.value == null,
      'CANCELLED' =>
        status == 'CANCELLED' &&
            published.value != null &&
            frozen.value != null &&
            finalized.value == null &&
            cancelled.value != null &&
            archived.value == null &&
            publicReason.value != null &&
            amended.value != null,
      'ARCHIVED' =>
        status == 'ARCHIVED' &&
            published.value != null &&
            frozen.value != null &&
            archived.value != null &&
            ((finalized.value != null) != (cancelled.value != null)) &&
            (cancelled.value == null
                ? publicReason.value == null && amended.value == null
                : publicReason.value != null && amended.value != null),
      _ => false,
    };
    if (!lifecycleValid) return null;
    return AdminGiveawayContest(
      id: id,
      revision: revision,
      slug: slug,
      title: title,
      status: status,
      lifecycleStatus: lifecycle,
      governingTimeZone: zone,
      startsAt: starts,
      endsAt: ends,
      cashCurrency: currency,
      cashMinor: cash,
      coinPrize: coins,
      minimumAge: age,
      eligibleCountries: List.unmodifiable(countries),
      eligibleRegions: List.unmodifiable(regions),
      sponsorLegalName: legalName,
      sponsorMailingAddress: address,
      rules: rules,
      socialLinks: List.unmodifiable(links),
      bannerMessage: banner,
      counts: counts,
      publicReason: publicReason.value,
      amendedRulesVersion: amended.value,
      publishedAt: published.value,
      frozenAt: frozen.value,
      finalizedAt: finalized.value,
      cancelledAt: cancelled.value,
      archivedAt: archived.value,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

final class AdminGiveawayCandidate {
  const AdminGiveawayCandidate({
    required this.entrantId,
    required this.displayName,
    required this.status,
    required this.verifiedCount,
    required this.reviewableCount,
    required this.reachedCountAt,
    required this.provisionalRank,
    required this.sharedRaceCount,
    required this.correlationFlags,
    required this.flaggedReferralFactIds,
  });
  final String entrantId;
  final String displayName;
  final String status;
  final int verifiedCount;
  final int reviewableCount;
  final DateTime? reachedCountAt;
  final int? provisionalRank;
  final int sharedRaceCount;
  final List<String> correlationFlags;
  final List<String> flaggedReferralFactIds;

  static const _statuses = {'ELIGIBLE', 'UNDER_REVIEW'};

  static AdminGiveawayCandidate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final entrant = _string(raw['entrantId']);
    final name = _string(raw['displayName']);
    final status = _string(raw['status']);
    final verified = _int(raw['verifiedCount']);
    final reviewable = _int(raw['reviewableCount']);
    final reached = _optionalDate(raw, 'reachedCountAt');
    final rank = _optionalInt(raw, 'provisionalRank');
    final signals = raw['auditSignals'];
    final shared = signals is Map ? _int(signals['sharedRaceCount']) : null;
    final correlations = signals is Map
        ? _strings(signals['correlationFlags'])
        : null;
    final factsRaw = raw['reviewFacts'];
    if (entrant == null ||
        name == null ||
        status == null ||
        !_statuses.contains(status) ||
        verified == null ||
        verified < 0 ||
        reviewable == null ||
        reviewable < 0 ||
        reached.invalid ||
        rank.invalid ||
        shared == null ||
        shared < 0 ||
        correlations == null ||
        factsRaw is! List) {
      return null;
    }
    final facts = <String>[];
    for (final item in factsRaw) {
      if (item is! Map || item['status'] != 'FLAGGED') return null;
      final id = _string(item['referralFactId']);
      if (id == null) return null;
      facts.add(id);
    }
    final rankValue = rank.value;
    final reachedValue = reached.value;
    final hasVerifiedStanding = verified > 0;
    if (hasVerifiedStanding != (rankValue != null && reachedValue != null) ||
        (!hasVerifiedStanding && (rankValue != null || reachedValue != null)) ||
        (rankValue != null && rankValue < 1) ||
        facts.length != (reviewable > 100 ? 100 : reviewable)) {
      return null;
    }
    return AdminGiveawayCandidate(
      entrantId: entrant,
      displayName: name,
      status: status,
      verifiedCount: verified,
      reviewableCount: reviewable,
      reachedCountAt: reachedValue,
      provisionalRank: rankValue,
      sharedRaceCount: shared,
      correlationFlags: List.unmodifiable(correlations),
      flaggedReferralFactIds: List.unmodifiable(facts),
    );
  }
}

final class AdminGiveawayResult {
  const AdminGiveawayResult({
    required this.rankedCount,
    required this.noWinner,
    this.potentialWinner,
    this.verifiedWinner,
  });
  final int rankedCount;
  final bool noWinner;
  final AdminGiveawayWinner? potentialWinner;
  final AdminGiveawayWinner? verifiedWinner;

  static AdminGiveawayResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final count = _int(raw['rankedCount']);
    final noWinner = raw['noWinner'];
    if (count == null || count < 0 || noWinner is! bool) return null;
    final potential = raw['potentialWinner'] == null
        ? null
        : AdminGiveawayWinner.tryParse(raw['potentialWinner']);
    final verified = raw['verifiedWinner'] == null
        ? null
        : AdminGiveawayWinner.tryParse(raw['verifiedWinner']);
    if ((raw['potentialWinner'] != null && potential == null) ||
        (raw['verifiedWinner'] != null && verified == null)) {
      return null;
    }
    if ((potential != null && verified != null) ||
        (noWinner && (potential != null || verified != null)) ||
        (count == 0 && (potential != null || verified != null)) ||
        (potential != null && potential.originalRank > count) ||
        (verified != null && verified.originalRank > count)) {
      return null;
    }
    return AdminGiveawayResult(
      rankedCount: count,
      noWinner: noWinner,
      potentialWinner: potential,
      verifiedWinner: verified,
    );
  }
}

final class AdminGiveawayWinner {
  const AdminGiveawayWinner({
    required this.entrantId,
    required this.displayName,
    required this.originalRank,
  });
  final String entrantId;
  final String displayName;
  final int originalRank;
  static AdminGiveawayWinner? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _string(raw['entrantId']);
    final name = _string(raw['displayName']);
    final rank = _int(raw['originalRank']);
    if (id == null || name == null || rank == null || rank < 1) return null;
    return AdminGiveawayWinner(
      entrantId: id,
      displayName: name,
      originalRank: rank,
    );
  }
}

final class AdminGiveawayFulfillment {
  const AdminGiveawayFulfillment({
    required this.status,
    required this.providerReferenceRedacted,
    this.provider,
    this.cashSentMinor,
    this.cashSentCurrency,
    this.claimedAt,
    this.cashSentAt,
    this.cashDeliveredAt,
    this.coinsAwardedAt,
    this.coinTransactionId,
    this.fulfilledAt,
  });
  final String status;
  final String? provider;
  final bool providerReferenceRedacted;
  final int? cashSentMinor;
  final String? cashSentCurrency;
  final DateTime? claimedAt;
  final DateTime? cashSentAt;
  final DateTime? cashDeliveredAt;
  final DateTime? coinsAwardedAt;
  final String? coinTransactionId;
  final DateTime? fulfilledAt;

  static const _statuses = {
    'UNCLAIMED',
    'CLAIMED',
    'CASH_SENT',
    'CASH_DELIVERED',
    'COINS_AWARDED',
  };

  static AdminGiveawayFulfillment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final status = _string(raw['status']);
    if (status == null || !_statuses.contains(status)) return null;
    final provider = _optionalString(raw, 'provider');
    final rawReference = raw['providerReference'];
    if (rawReference != null && rawReference != '••••') return null;
    final minor = _optionalInt(raw, 'cashSentMinor');
    final currency = _optionalString(raw, 'cashSentCurrency');
    final claimed = _optionalDate(raw, 'claimedAt');
    final sent = _optionalDate(raw, 'cashSentAt');
    final delivered = _optionalDate(raw, 'cashDeliveredAt');
    final coins = _optionalDate(raw, 'coinsAwardedAt');
    final transaction = _optionalString(raw, 'coinTransactionId');
    final fulfilled = _optionalDate(raw, 'fulfilledAt');
    if ([
      provider.invalid,
      minor.invalid,
      currency.invalid,
      claimed.invalid,
      sent.invalid,
      delivered.invalid,
      coins.invalid,
      transaction.invalid,
      fulfilled.invalid,
    ].contains(true)) {
      return null;
    }
    final providerValue = provider.value;
    final minorValue = minor.value;
    final currencyValue = currency.value;
    final claimedAt = claimed.value;
    final sentAt = sent.value;
    final deliveredAt = delivered.value;
    final coinsAwardedAt = coins.value;
    final transactionId = transaction.value;
    final fulfilledAt = fulfilled.value;
    final hasProvider = providerValue != null;
    final hasReference = rawReference == '••••';
    final hasCash = minorValue == 5000 && currencyValue == 'USD';
    final noCash = minorValue == null && currencyValue == null;
    final noProvider = !hasProvider && !hasReference;
    final validLifecycle = switch (status) {
      'UNCLAIMED' =>
        noProvider &&
            noCash &&
            claimedAt == null &&
            sentAt == null &&
            deliveredAt == null &&
            coinsAwardedAt == null &&
            transactionId == null &&
            fulfilledAt == null,
      'CLAIMED' =>
        noProvider &&
            noCash &&
            claimedAt != null &&
            sentAt == null &&
            deliveredAt == null &&
            coinsAwardedAt == null &&
            transactionId == null &&
            fulfilledAt == null,
      'CASH_SENT' =>
        hasProvider &&
            hasReference &&
            hasCash &&
            claimedAt != null &&
            sentAt != null &&
            deliveredAt == null &&
            coinsAwardedAt == null &&
            transactionId == null &&
            fulfilledAt == null &&
            _atOrAfter(sentAt, claimedAt),
      'CASH_DELIVERED' =>
        hasProvider &&
            hasReference &&
            hasCash &&
            claimedAt != null &&
            sentAt != null &&
            deliveredAt != null &&
            coinsAwardedAt == null &&
            transactionId == null &&
            fulfilledAt == null &&
            _atOrAfter(sentAt, claimedAt) &&
            _atOrAfter(deliveredAt, sentAt),
      'COINS_AWARDED' =>
        hasProvider &&
            hasReference &&
            hasCash &&
            claimedAt != null &&
            sentAt != null &&
            deliveredAt != null &&
            coinsAwardedAt != null &&
            transactionId != null &&
            fulfilledAt != null &&
            _atOrAfter(sentAt, claimedAt) &&
            _atOrAfter(deliveredAt, sentAt) &&
            _atOrAfter(coinsAwardedAt, deliveredAt) &&
            _atOrAfter(fulfilledAt, coinsAwardedAt),
      _ => false,
    };
    if (!validLifecycle) return null;
    return AdminGiveawayFulfillment(
      status: status,
      provider: providerValue,
      providerReferenceRedacted: rawReference == '••••',
      cashSentMinor: minorValue,
      cashSentCurrency: currencyValue,
      claimedAt: claimedAt,
      cashSentAt: sentAt,
      cashDeliveredAt: deliveredAt,
      coinsAwardedAt: coinsAwardedAt,
      coinTransactionId: transactionId,
      fulfilledAt: fulfilledAt,
    );
  }
}

bool _atOrAfter(DateTime? value, DateTime? earlier) =>
    value != null && earlier != null && !value.isBefore(earlier);

String? _boundedString(Object? raw, int maxLength) {
  final value = _string(raw);
  return value == null || value.length > maxLength ? null : value;
}

bool _isExactUsRegionSet(List<String> regions) =>
    regions.length == giveawayUsRegionsV1.length &&
    regions.toSet().length == giveawayUsRegionsV1.length &&
    regions.every(giveawayUsRegionsV1.contains);

String? _string(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
int? _int(Object? raw) => raw is int ? raw : null;
DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
List<String>? _strings(Object? raw) {
  if (raw is! List) return null;
  final values = <String>[];
  for (final item in raw) {
    final value = _string(item);
    if (value == null) return null;
    values.add(value);
  }
  return values;
}

({String? value, bool invalid}) _optionalString(Map raw, String key) =>
    _optional<String>(raw, key, _string);
({int? value, bool invalid}) _optionalInt(Map raw, String key) =>
    _optional<int>(raw, key, _int);
({DateTime? value, bool invalid}) _optionalDate(Map raw, String key) =>
    _optional<DateTime>(raw, key, _date);
({T? value, bool invalid}) _optional<T>(
  Map raw,
  String key,
  T? Function(Object?) parser,
) {
  if (!raw.containsKey(key) || raw[key] == null) {
    return (value: null, invalid: false);
  }
  final value = parser(raw[key]);
  return (value: value, invalid: value == null);
}
