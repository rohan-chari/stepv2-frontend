/// Strict, defensive DTOs for the additive referral-contest API.
///
/// A populated response is accepted only when every contract-required field is
/// present with the right type. Callers treat `null` as feature unavailable so
/// a newer app never destabilizes Home or ordinary referrals against an older
/// or partially deployed backend.
library;

import 'dart:convert';

const Set<String> giveawayUsRegionsV1 = {
  'US-AL',
  'US-AK',
  'US-AZ',
  'US-AR',
  'US-CA',
  'US-CO',
  'US-CT',
  'US-DE',
  'US-DC',
  'US-FL',
  'US-GA',
  'US-HI',
  'US-ID',
  'US-IL',
  'US-IN',
  'US-IA',
  'US-KS',
  'US-KY',
  'US-LA',
  'US-ME',
  'US-MD',
  'US-MA',
  'US-MI',
  'US-MN',
  'US-MS',
  'US-MO',
  'US-MT',
  'US-NE',
  'US-NV',
  'US-NH',
  'US-NJ',
  'US-NM',
  'US-NY',
  'US-NC',
  'US-ND',
  'US-OH',
  'US-OK',
  'US-OR',
  'US-PA',
  'US-RI',
  'US-SC',
  'US-SD',
  'US-TN',
  'US-TX',
  'US-UT',
  'US-VT',
  'US-VA',
  'US-WA',
  'US-WV',
  'US-WI',
  'US-WY',
};

enum GiveawayStatus { scheduled, active, verifying, finalResult }

enum GiveawayEligibilityMode { us18, baraAccount }

enum GiveawayEntryStatus {
  actionRequired,
  eligible,
  underReview,
  ineligible,
  withdrawn,
}

const giveawayCashMinorMax = 2147483647;
const giveawayCoinPrizeMax = 1000000;

/// Mirrors the server's global Home-headline guard closely enough to fail
/// closed before rendering or sending admin copy. The server remains
/// authoritative and applies full Unicode NFKC normalization.
bool isValidGlobalGiveawayBannerMessage(Object? raw) {
  if (raw is! String) return false;
  final normalized = _compatibilityAscii(raw).trim();
  final length = normalized.runes.length;
  if (length < 12 ||
      length > 96 ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(normalized)) {
    return false;
  }
  return !RegExp(
    r'(?:\$|\busd\b|\bdollars?\b|\bbucks?\b|\bcash\b|\bmoney\b|\bfiat\b|\bcurrenc(?:y|ies)\b|\bvenmo\b|\bpaypal\b|\bcash\s*app\b|\bgift\s*(?:card|certificate)s?\b|\bstore\s*credits?\b|\bvouchers?\b|\bcrypto(?:currenc(?:y|ies))?\b|\bbitcoin\b|\bethereum\b|\bmerch(?:andise)?\b|\bphysical\s+(?:goods?|items?|prizes?)\b|\breal[-\s]*world\s+value\b|\bmarket\s+value\b|\bwithdraw\w*\b|\bredeem\w*\b|\bconvert\w*\b|\bexchange\w*\b|\btradeable\b|\btradable\b|\bresell\w*\b)',
    caseSensitive: false,
  ).hasMatch(normalized);
}

String _compatibilityAscii(String value) => String.fromCharCodes(
  value.runes.map((rune) {
    if (rune == 0x3000) return 0x20;
    if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
    return rune;
  }),
);

final class GiveawayPrize {
  const GiveawayPrize({
    required this.cashCurrency,
    required this.cashMinor,
    required this.coins,
  });

  final String cashCurrency;
  final int cashMinor;
  final int coins;

  static GiveawayPrize? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final hasCurrency = raw.containsKey('cashCurrency');
    final hasCash = raw.containsKey('cashMinor');
    final hasCoins = raw.containsKey('coins');
    if (hasCurrency != hasCash) return null;
    final currency = hasCurrency ? raw['cashCurrency'] : 'USD';
    final cashMinor = hasCash ? _strictInt(raw['cashMinor']) : 0;
    final coins = hasCoins ? _strictInt(raw['coins']) : 0;
    if (currency is! String || cashMinor == null || coins == null) {
      return null;
    }
    if (currency != 'USD' ||
        cashMinor < 0 ||
        cashMinor > giveawayCashMinorMax ||
        coins < 0 ||
        coins > giveawayCoinPrizeMax ||
        (cashMinor == 0 && coins == 0)) {
      return null;
    }
    return GiveawayPrize(
      cashCurrency: currency,
      cashMinor: cashMinor,
      coins: coins,
    );
  }
}

final class GiveawayRuleSection {
  const GiveawayRuleSection({required this.heading, required this.body});

  final String heading;
  final String body;

  static GiveawayRuleSection? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final heading = raw['heading'];
    final body = raw['body'];
    if (heading is! String ||
        heading.trim().isEmpty ||
        heading.trim().length > 120 ||
        body is! String ||
        body.trim().isEmpty ||
        body.trim().length > 8000) {
      return null;
    }
    return GiveawayRuleSection(heading: heading.trim(), body: body.trim());
  }
}

final class GiveawayRules {
  const GiveawayRules({
    required this.version,
    required this.sha256,
    required this.sections,
    this.url,
  });

  final String version;
  final String sha256;
  final List<GiveawayRuleSection> sections;
  final Uri? url;

  static GiveawayRules? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final sha = raw['sha256'];
    final rawSections = raw['sections'];
    if (version is! String ||
        version.trim().isEmpty ||
        version.trim().length > 80 ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        rawSections is! List) {
      return null;
    }
    if (rawSections.isEmpty || rawSections.length > 20) return null;
    final sections = <GiveawayRuleSection>[];
    var totalBytes = 0;
    for (final item in rawSections) {
      final section = GiveawayRuleSection.tryParse(item);
      if (section == null) return null;
      totalBytes += utf8.encode(section.heading).length;
      totalBytes += utf8.encode(section.body).length;
      if (totalBytes > 24000) return null;
      sections.add(section);
    }
    Uri? url;
    if (raw.containsKey('url') && raw['url'] != null) {
      final value = raw['url'];
      if (value is! String) return null;
      final parsed = Uri.tryParse(value);
      if (parsed == null || parsed.scheme != 'https') return null;
      url = parsed;
    }
    return GiveawayRules(
      version: version.trim(),
      sha256: sha.trim(),
      sections: List.unmodifiable(sections),
      url: url,
    );
  }
}

final class GiveawaySocialLink {
  const GiveawaySocialLink({
    required this.platform,
    required this.label,
    required this.url,
  });

  final String platform;
  final String label;
  final Uri url;

  static const _platforms = {'instagram', 'tiktok', 'x', 'facebook', 'youtube'};
  static const _hosts = <String, Set<String>>{
    'instagram': {'instagram.com', 'www.instagram.com'},
    'tiktok': {'tiktok.com', 'www.tiktok.com'},
    'x': {'x.com', 'www.x.com', 'twitter.com', 'www.twitter.com'},
    'facebook': {'facebook.com', 'www.facebook.com'},
    'youtube': {'youtube.com', 'www.youtube.com', 'youtu.be'},
  };

  static GiveawaySocialLink? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final platform = raw['platform'];
    final label = raw['label'];
    final url = raw['url'];
    if (platform is! String ||
        !_platforms.contains(platform) ||
        label is! String ||
        label.trim().isEmpty ||
        url is! String) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        _hosts[platform]?.contains(uri.host.toLowerCase()) != true) {
      return null;
    }
    return GiveawaySocialLink(
      platform: platform,
      label: label.trim(),
      url: uri,
    );
  }
}

final class GiveawayContest {
  const GiveawayContest({
    required this.slug,
    required this.title,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.governingTimeZone,
    required this.prize,
    required this.eligibilityMode,
    required this.eligibilitySummary,
    required this.minimumAge,
    required this.eligibleCountries,
    required this.eligibleRegions,
    required this.sponsorName,
    required this.sponsorLegalName,
    required this.sponsorMailingAddress,
    required this.rules,
    required this.socialLinks,
  });

  final String slug;
  final String title;
  final GiveawayStatus status;
  final DateTime startsAt;
  final DateTime endsAt;
  final String governingTimeZone;
  final GiveawayPrize prize;
  final GiveawayEligibilityMode eligibilityMode;
  final String eligibilitySummary;
  final int? minimumAge;
  final List<String> eligibleCountries;
  final List<String> eligibleRegions;
  final String sponsorName;
  final String? sponsorLegalName;
  final String? sponsorMailingAddress;
  final GiveawayRules rules;
  final List<GiveawaySocialLink> socialLinks;

  static GiveawayContest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'];
    final title = raw['title'];
    final status = _parseStatus(raw['status']);
    final startsAt = _date(raw['startsAt']);
    final endsAt = _date(raw['endsAt']);
    final zone = raw['governingTimeZone'];
    final prize = GiveawayPrize.tryParse(raw['prize']);
    final eligibility = raw['eligibility'];
    final isGlobal =
        eligibility is Map && eligibility['mode'] == 'BARA_ACCOUNT';
    if (eligibility != null && !isGlobal) return null;
    final age = _strictInt(raw['minimumAge']);
    final countries = _stringList(raw['eligibleCountries']);
    final regions = _stringList(raw['eligibleRegions']);
    final sponsor = raw['sponsor'];
    final sponsorName = sponsor is Map
        ? _boundedString(sponsor['name'], 200)
        : null;
    final sponsorLegalName = sponsor is Map
        ? _boundedString(sponsor['legalName'], 200)
        : null;
    final sponsorMailingAddress = sponsor is Map
        ? _boundedString(sponsor['mailingAddress'], 500)
        : null;
    final rules = GiveawayRules.tryParse(raw['rules']);
    final rawSocial = raw['socialLinks'];
    if (slug is! String ||
        slug.trim().isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        status == null ||
        startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt) ||
        zone is! String ||
        zone.trim().isEmpty ||
        prize == null ||
        rules == null ||
        rawSocial is! List) {
      return null;
    }
    final eligibilitySummary = isGlobal
        ? _boundedString(eligibility['summary'], 200)
        : 'U.S. residents age 18 and older.';
    if (isGlobal) {
      if (eligibilitySummary != 'Open to signed-in Bara users.' ||
          raw['minimumAge'] != null ||
          raw['eligibleCountries'] != null ||
          raw['eligibleRegions'] != null ||
          sponsorName != 'Bara' ||
          prize.cashMinor != 0 ||
          prize.coins < 1 ||
          prize.coins > 25000 ||
          !RegExp(r'^bara-account-v1-[0-9a-f]{24}$').hasMatch(rules.version)) {
        return null;
      }
    } else if (age != 18 ||
        countries == null ||
        countries.length != 1 ||
        countries.single != 'US' ||
        regions == null ||
        !_isExactUsRegionSet(regions) ||
        sponsorLegalName == null ||
        sponsorMailingAddress == null) {
      return null;
    }
    final social = <GiveawaySocialLink>[];
    for (final item in rawSocial) {
      final link = GiveawaySocialLink.tryParse(item);
      if (link == null) return null;
      social.add(link);
    }
    return GiveawayContest(
      slug: slug.trim(),
      title: title.trim(),
      status: status,
      startsAt: startsAt,
      endsAt: endsAt,
      governingTimeZone: zone.trim(),
      prize: prize,
      eligibilityMode: isGlobal
          ? GiveawayEligibilityMode.baraAccount
          : GiveawayEligibilityMode.us18,
      eligibilitySummary: eligibilitySummary ?? '',
      minimumAge: isGlobal ? null : 18,
      eligibleCountries: List.unmodifiable(countries ?? const <String>[]),
      eligibleRegions: List.unmodifiable(regions ?? const <String>[]),
      sponsorName: isGlobal ? sponsorName ?? '' : sponsorLegalName ?? '',
      sponsorLegalName: sponsorLegalName,
      sponsorMailingAddress: sponsorMailingAddress,
      rules: rules,
      socialLinks: List.unmodifiable(social),
    );
  }
}

final class GiveawayLeaderboardRow {
  const GiveawayLeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.completedCount,
  });
  final int rank;
  final String displayName;
  final int completedCount;

  static GiveawayLeaderboardRow? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rank = _strictInt(raw['rank']);
    final name = raw['displayName'];
    final count = _strictInt(raw['completedCount']);
    if (rank == null ||
        rank < 1 ||
        name is! String ||
        name.trim().isEmpty ||
        count == null ||
        count < 0) {
      return null;
    }
    return GiveawayLeaderboardRow(
      rank: rank,
      displayName: name.trim(),
      completedCount: count,
    );
  }
}

final class GiveawayEntry {
  const GiveawayEntry({
    required this.status,
    required this.displayName,
    this.acceptedAt,
    this.country,
    this.region,
    this.rulesVersion,
  });
  final GiveawayEntryStatus status;
  final String? displayName;
  final DateTime? acceptedAt;
  final String? country;
  final String? region;
  final String? rulesVersion;

  static GiveawayEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final status = _parseEntryStatus(raw['status']);
    final name = raw['displayName'];
    if (status == null) return null;
    String? displayName;
    if (name is String && name.trim().isNotEmpty) {
      displayName = name.trim();
    } else if (name != null && name is! String) {
      return null;
    } else if (status != GiveawayEntryStatus.actionRequired &&
        status != GiveawayEntryStatus.withdrawn) {
      return null;
    }
    final accepted = _nullableDate(raw, 'acceptedAt');
    if (accepted.invalid) return null;
    final country = _nullableString(raw, 'country');
    final region = _nullableString(raw, 'region');
    final version = _nullableString(raw, 'rulesVersion');
    if (country.invalid || region.invalid || version.invalid) return null;
    return GiveawayEntry(
      status: status,
      displayName: displayName,
      acceptedAt: accepted.value,
      country: country.value,
      region: region.value,
      rulesVersion: version.value,
    );
  }
}

final class GiveawayStanding {
  const GiveawayStanding({
    required this.verifiedCount,
    required this.reviewableCount,
    required this.provisionalRank,
    this.reachedCountAt,
  });
  final int verifiedCount;
  final int reviewableCount;
  final int? provisionalRank;
  final DateTime? reachedCountAt;

  static GiveawayStanding? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final verified = _strictInt(raw['verifiedCount']);
    final reviewable = _strictInt(raw['reviewableCount']);
    final rankRaw = raw['provisionalRank'];
    final rank = rankRaw == null ? null : _strictInt(rankRaw);
    final reached = _nullableDate(raw, 'reachedCountAt');
    if (verified == null ||
        verified < 0 ||
        reviewable == null ||
        reviewable < 0 ||
        (rankRaw != null && (rank == null || rank < 1)) ||
        reached.invalid) {
      return null;
    }
    if (verified == 0
        ? (rank != null || reached.value != null)
        : (rank == null || reached.value == null)) {
      return null;
    }
    return GiveawayStanding(
      verifiedCount: verified,
      reviewableCount: reviewable,
      provisionalRank: rank,
      reachedCountAt: reached.value,
    );
  }
}

final class GiveawayShare {
  const GiveawayShare({required this.code, required this.url});
  final String code;
  final Uri url;

  static GiveawayShare? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    final url = raw['url'];
    if (code is! String ||
        code.trim() != code ||
        !RegExp(r'^BARA-[A-Z0-9]{2,32}$').hasMatch(code) ||
        url is! String) {
      return null;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.toLowerCase() != 'barastep.com' ||
        parsed.hasPort ||
        parsed.userInfo.isNotEmpty ||
        parsed.path != '/r/$code' ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      return null;
    }
    return GiveawayShare(code: code, url: parsed);
  }
}

final class GiveawayWinner {
  const GiveawayWinner({required this.displayName, required this.originalRank});
  final String displayName;
  final int originalRank;

  static GiveawayWinner? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['displayName'];
    final rank = _strictInt(raw['originalRank']);
    if (name is! String || name.trim().isEmpty || rank == null || rank < 1) {
      return null;
    }
    return GiveawayWinner(displayName: name.trim(), originalRank: rank);
  }
}

final class GiveawayCurrent {
  const GiveawayCurrent({
    required this.contest,
    required this.leaderboard,
    required this.entry,
    required this.standing,
    required this.share,
    required this.winner,
  });
  final GiveawayContest contest;
  final List<GiveawayLeaderboardRow> leaderboard;
  final GiveawayEntry? entry;
  final GiveawayStanding? standing;
  final GiveawayShare? share;
  final GiveawayWinner? winner;

  static GiveawayCurrent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final contest = GiveawayContest.tryParse(raw['contest']);
    final rawRows = raw['leaderboard'];
    if (contest == null || rawRows is! List) return null;
    final rows = <GiveawayLeaderboardRow>[];
    for (final item in rawRows) {
      final row = GiveawayLeaderboardRow.tryParse(item);
      if (row == null) return null;
      rows.add(row);
    }
    final entry = GiveawayEntry.tryParse(raw['entry']);
    if (entry == null) return null;
    GiveawayStanding? standing;
    if (raw['standing'] != null) {
      standing = GiveawayStanding.tryParse(raw['standing']);
      if (standing == null) return null;
    }
    GiveawayShare? share;
    if (raw['share'] != null) {
      share = GiveawayShare.tryParse(raw['share']);
      if (share == null) return null;
    }
    GiveawayWinner? winner;
    if (raw['winner'] != null) {
      winner = GiveawayWinner.tryParse(raw['winner']);
      if (winner == null) return null;
    }
    if (contest.status != GiveawayStatus.finalResult && winner != null) {
      return null;
    }
    final actionRequired = entry.status == GiveawayEntryStatus.actionRequired;
    if (actionRequired) {
      if (entry.acceptedAt != null ||
          entry.country != null ||
          entry.region != null ||
          entry.rulesVersion != null) {
        return null;
      }
    } else {
      if (entry.acceptedAt == null ||
          (entry.rulesVersion != null &&
              entry.rulesVersion != contest.rules.version)) {
        return null;
      }
      if (contest.eligibilityMode == GiveawayEligibilityMode.baraAccount) {
        if (entry.country != null || entry.region != null) return null;
      } else if (entry.region == null ||
          !contest.eligibleRegions.contains(entry.region) ||
          (entry.country != null && entry.country != 'US')) {
        return null;
      }
    }
    final withdrawn = entry.status == GiveawayEntryStatus.withdrawn;
    if (withdrawn
        ? (standing != null || share != null)
        : (standing == null || share == null)) {
      return null;
    }
    if (contest.status == GiveawayStatus.finalResult &&
        standing != null &&
        standing.reviewableCount != 0) {
      return null;
    }
    final reachedAt = standing?.reachedCountAt;
    final acceptedAt = entry.acceptedAt;
    if (reachedAt != null) {
      if (reachedAt.isBefore(contest.startsAt) ||
          !reachedAt.isBefore(contest.endsAt) ||
          (acceptedAt != null && reachedAt.isBefore(acceptedAt))) {
        return null;
      }
    }
    if (standing != null &&
        contest.status == GiveawayStatus.scheduled &&
        (standing.verifiedCount != 0 || standing.reviewableCount != 0)) {
      return null;
    }
    if (standing != null &&
        (entry.status == GiveawayEntryStatus.actionRequired ||
            entry.status == GiveawayEntryStatus.ineligible) &&
        (standing.verifiedCount != 0 || standing.reviewableCount != 0)) {
      return null;
    }
    return GiveawayCurrent(
      contest: contest,
      leaderboard: List.unmodifiable(rows),
      entry: entry,
      standing: standing,
      share: share,
      winner: winner,
    );
  }
}

int? _strictInt(Object? raw) => raw is int ? raw : null;

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

List<String>? _stringList(Object? raw) {
  if (raw is! List) return null;
  final result = <String>[];
  for (final item in raw) {
    if (item is! String || item.isEmpty) return null;
    result.add(item);
  }
  return result;
}

String? _boundedString(Object? raw, int maxLength) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty || value.length > maxLength ? null : value;
}

bool _isExactUsRegionSet(List<String> regions) =>
    regions.length == giveawayUsRegionsV1.length &&
    regions.toSet().length == giveawayUsRegionsV1.length &&
    regions.every(giveawayUsRegionsV1.contains);

GiveawayStatus? _parseStatus(Object? raw) => switch (raw) {
  'SCHEDULED' => GiveawayStatus.scheduled,
  'ACTIVE' => GiveawayStatus.active,
  'VERIFYING' => GiveawayStatus.verifying,
  'FINAL' => GiveawayStatus.finalResult,
  _ => null,
};

GiveawayEntryStatus? _parseEntryStatus(Object? raw) => switch (raw) {
  'ACTION_REQUIRED' => GiveawayEntryStatus.actionRequired,
  'ELIGIBLE' => GiveawayEntryStatus.eligible,
  'UNDER_REVIEW' => GiveawayEntryStatus.underReview,
  'INELIGIBLE' => GiveawayEntryStatus.ineligible,
  'WITHDRAWN' => GiveawayEntryStatus.withdrawn,
  _ => null,
};

({T? value, bool invalid}) _nullable<T>(
  Map raw,
  String key,
  T? Function(Object?) parse,
) {
  if (!raw.containsKey(key) || raw[key] == null) {
    return (value: null, invalid: false);
  }
  final value = parse(raw[key]);
  return (value: value, invalid: value == null);
}

({DateTime? value, bool invalid}) _nullableDate(Map raw, String key) =>
    _nullable<DateTime>(raw, key, _date);

({String? value, bool invalid}) _nullableString(Map raw, String key) =>
    _nullable<String>(
      raw,
      key,
      (value) => value is String && value.isNotEmpty ? value : null,
    );
