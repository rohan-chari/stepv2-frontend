import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import 'admin_onboarding_funnel.dart';

/// Batch 2026-08-09 item 10 — the admin hub's section widgets.
///
/// Split out of `admin_screen.dart`, which had grown into one 1,300-line flat
/// scroll. Every body here is a PURE function of a stats map so each block can
/// be pumped on its own with a hand-written payload — including the payload
/// that matters most, the one from a prod backend that hasn't deployed the new
/// aggregates yet.
///
/// House rule for this file: a missing, null or wrong-typed field renders "—"
/// and an absent *section* renders nothing. Never an exception. The app and
/// the backend deploy independently and this screen is how an operator finds
/// out something is wrong — it must not be the thing that is broken.

/// The em-dash every absent value collapses to.
const String kAdminMissing = '—';

/// One label/value row. Deliberately identical to the row the flat stats card
/// drew, so nothing an operator reads changed shape in this refactor.
Widget adminStatRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          ),
        ),
        Text(
          value,
          style: PixelText.title(
            size: 13,
            color: AppColors.of(context).textDark,
          ),
        ),
      ],
    ),
  );
}

/// A sub-heading inside a section body.
Widget adminStatHeading(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      title,
      style: PixelText.title(size: 12, color: AppColors.of(context).textDark),
    ),
  );
}

// ---------------------------------------------------------------------------
// Defensive readers
// ---------------------------------------------------------------------------

Map<String, dynamic>? adminMap(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : null;

/// Every element of [value] that is a map, or an empty list for anything else
/// (absent, null, a bare string from a backend that changed shape).
List<Map<String, dynamic>> adminRows(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

/// An int from a numeric field, or null. A numeric STRING is deliberately not
/// accepted: the contract says number, and silently coercing would hide a real
/// backend regression behind a plausible-looking figure.
int? adminInt(dynamic value) => value is num ? value.toInt() : null;

/// Thousands-separated, or "—" when the field isn't a usable number.
String adminNumber(dynamic value) {
  final n = adminInt(value);
  if (n == null) return kAdminMissing;
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// A one-decimal figure, or "—". For genuinely fractional metrics (averages),
/// where the integer reader would silently floor 2.7 to 2.
String adminDecimal(dynamic value, {int places = 1}) {
  if (value is! num) return kAdminMissing;
  return value.toStringAsFixed(places);
}

/// "a / b", with each half degrading independently.
String adminPair(dynamic a, dynamic b) =>
    '${adminNumber(a)} / ${adminNumber(b)}';

// ---------------------------------------------------------------------------
// The collapsible section shell
// ---------------------------------------------------------------------------

/// A titled, collapsible board.
///
/// [onFirstExpand] fires ONCE, the first time the body is opened — that is the
/// lazy-fetch seam for the sections whose aggregates the backend only computes
/// on request. Collapsing and re-opening must never re-run them (the one-vCPU
/// prod box is the whole reason the aggregates are opt-in).
class AdminSection extends StatefulWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.width,
    required this.child,
    this.initiallyExpanded = false,
    this.onFirstExpand,
  });

  final String title;
  final double width;
  final Widget child;
  final bool initiallyExpanded;
  final VoidCallback? onFirstExpand;

  @override
  State<AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends State<AdminSection> {
  late bool _expanded = widget.initiallyExpanded;
  bool _everExpanded = false;

  @override
  void initState() {
    super.initState();
    if (_expanded) _fireFirstExpand();
  }

  void _fireFirstExpand() {
    if (_everExpanded) return;
    _everExpanded = true;
    final callback = widget.onFirstExpand;
    if (callback == null) return;
    // After the frame: the callback typically calls setState on the hub, and
    // an expanded-by-default section would otherwise fire it during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) _fireFirstExpand();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ContentBoard(
      key: Key('admin-section-${widget.title}'),
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('admin-section-header-${widget.title}'),
            onTap: _toggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: PixelText.title(size: 16, color: colors.textDark),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: colors.textDark,
                ),
              ],
            ),
          ),
          if (_expanded) ...[const SizedBox(height: 8), widget.child],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GROWTH
// ---------------------------------------------------------------------------

/// New users, DAU, app-version adoption, retention and the referral funnel.
class AdminGrowthStatsBody extends StatelessWidget {
  const AdminGrowthStatsBody({super.key, required this.stats});

  final Map<String, dynamic>? stats;

  static String retentionLine(Map<String, dynamic>? side, String day) {
    if (side == null) return kAdminMissing;
    final cohort = adminInt(side['${day}Cohort']) ?? 0;
    final retained = adminInt(side['${day}Retained']) ?? 0;
    if (cohort == 0) return kAdminMissing;
    final pct = ((retained / cohort) * 100).round();
    return '$retained/$cohort ($pct%)';
  }

  @override
  Widget build(BuildContext context) {
    final stats = this.stats;
    if (stats == null) return const AdminSectionUnavailable();

    final users = adminMap(stats['users']);
    final activity = adminMap(stats['activity']);
    final retention = adminMap(stats['retention']);
    final withFriend = adminMap(retention?['withFriend']);
    final withoutFriend = adminMap(retention?['withoutFriend']);
    final funnel = adminMap(stats['referralFunnel']);
    final versions = adminRows(stats['versions']);
    final versionsSince = stats['versionsSince'] is String
        ? stats['versionsSince'] as String
        : null;
    final onboardingFunnel = adminMap(stats['onboardingFunnel']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        adminStatHeading(context, 'USERS'),
        adminStatRow(context, 'Total', adminNumber(users?['total'])),
        adminStatRow(
          context,
          'New (7d / 30d)',
          adminPair(users?['newLast7Days'], users?['newLast30Days']),
        ),
        adminStatRow(
          context,
          'DAU (stepped today)',
          adminNumber(activity?['dauToday']),
        ),
        // Additive sections HIDE entirely rather than rendering a shell of
        // em-dashes — an operator on an older backend should see no version
        // table, not an empty one.
        if (versions.isNotEmpty) ...[
          adminStatHeading(context, 'VERSIONS'),
          if (versionsSince != null)
            adminStatRow(context, 'Seen since', versionsSince),
          for (final bucket in versions)
            adminStatRow(
              context,
              '${bucket['version'] ?? 'unknown'}'
              '${bucket['platform'] != null ? ' (${bucket['platform']})' : ''}',
              adminNumber(bucket['users'] ?? 0),
            ),
        ],
        adminStatHeading(context, 'RETENTION (LAST 32D COHORT)'),
        adminStatRow(
          context,
          'D1 with friend',
          retentionLine(withFriend, 'd1'),
        ),
        adminStatRow(
          context,
          'D1 no friend',
          retentionLine(withoutFriend, 'd1'),
        ),
        adminStatRow(
          context,
          'D7 with friend',
          retentionLine(withFriend, 'd7'),
        ),
        adminStatRow(
          context,
          'D7 no friend',
          retentionLine(withoutFriend, 'd7'),
        ),
        adminStatHeading(context, 'INVITE FUNNEL'),
        adminStatRow(
          context,
          'Link opens (7d / all)',
          adminPair(funnel?['linkOpensLast7Days'], funnel?['linkOpensTotal']),
        ),
        adminStatRow(
          context,
          'Referred signups (7d / all)',
          adminPair(funnel?['signupsLast7Days'], funnel?['signups']),
        ),
        adminStatRow(
          context,
          'Joined a race',
          adminNumber(funnel?['joinedRace']),
        ),
        // Item 2 changed what "finished" means server-side (a real race with
        // another real player). The key is unchanged, so the row is too.
        adminStatRow(
          context,
          'Finished a real race',
          adminNumber(funnel?['finishedRace']),
        ),
        adminStatRow(context, 'Rewarded', adminNumber(funnel?['rewarded'])),
        OnboardingFunnelSection(funnel: onboardingFunnel),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ENGAGEMENT
// ---------------------------------------------------------------------------

/// Races (private / public / team), box opens and friend distribution.
class AdminEngagementStatsBody extends StatelessWidget {
  const AdminEngagementStatsBody({super.key, required this.stats});

  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final stats = this.stats;
    if (stats == null) return const AdminSectionUnavailable();

    final activity = adminMap(stats['activity']);
    final races = adminMap(stats['races']);
    // Computed by the backend since the team-race build and never rendered
    // until now (item 10's "dead weight" list).
    final teamRaces = adminMap(stats['teamRaces']);
    final friends = adminMap(adminMap(stats['friends'])?['distribution']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        adminStatHeading(context, 'ACTIVITY'),
        adminStatRow(
          context,
          'In an active race',
          '${adminNumber(activity?['dauInActiveRace'])} '
              '(${adminNumber(activity?['pctDauInActiveRace'])}%)',
        ),
        adminStatRow(
          context,
          'Avg box openers/day',
          adminNumber(activity?['avgUniqueBoxOpenersPerDay']),
        ),
        if (races != null) ...[
          adminStatHeading(context, 'RACES'),
          adminStatRow(
            context,
            'Private (total / active)',
            adminPair(races['privateTotal'], races['privateActive']),
          ),
          adminStatRow(
            context,
            'Public (total / active)',
            adminPair(races['publicTotal'], races['publicActive']),
          ),
        ],
        if (teamRaces != null) ...[
          adminStatHeading(context, 'TEAM RACES'),
          adminStatRow(
            context,
            'Created (total / 7d)',
            adminPair(teamRaces['createdTotal'], teamRaces['createdLast7Days']),
          ),
          adminStatRow(
            context,
            'Completed (total / 7d)',
            adminPair(
              teamRaces['completedTotal'],
              teamRaces['completedLast7Days'],
            ),
          ),
          adminStatRow(
            context,
            'Active now',
            adminNumber(teamRaces['activeNow']),
          ),
        ],
        adminStatHeading(context, 'FRIENDS PER USER'),
        adminStatRow(
          context,
          '0 / 1 / 2 / 3-5 / 6+',
          '${adminInt(friends?['0']) ?? 0} / ${adminInt(friends?['1']) ?? 0} / '
              '${adminInt(friends?['2']) ?? 0} / ${adminInt(friends?['3-5']) ?? 0} / '
              '${adminInt(friends?['6+']) ?? 0}',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// REVENUE
// ---------------------------------------------------------------------------

/// Rewarded-ad watches (the app's only revenue proxy today), coins minted vs
/// sunk, shop purchases by SKU and box opens.
///
/// `coinEconomy` and `adRevenue` arrive only when the hub asked for them
/// (`?sections=economy,ads`) AND the backend is new enough to compute them.
/// Both absences look identical here, and both render "—".
class AdminRevenueBody extends StatelessWidget {
  const AdminRevenueBody({
    super.key,
    required this.stats,
    this.loading = false,
    this.failed = false,
  });

  final Map<String, dynamic>? stats;
  final bool loading;
  final bool failed;

  static String rewardedAdLine(Map<String, dynamic>? rewarded, String key) {
    final value = rewarded?[key];
    if (value is! Map) return kAdminMissing;
    final count = adminInt(value['uniqueDauWatchers']);
    final pct = adminInt(value['pctOfDau']);
    if (count == null || pct == null) return kAdminMissing;
    return '$count ($pct%)';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (failed) return const AdminSectionUnavailable();

    final stats = this.stats ?? const <String, dynamic>{};
    final rewardedAds = adminMap(adminMap(stats['activity'])?['rewardedAds']);
    final economy = adminMap(stats['coinEconomy']);
    final ads = adminMap(stats['adRevenue']);

    final economyDays = adminRows(economy?['days']);
    final purchases = adminRows(economy?['purchasesBySku']);
    final boxOpens = adminRows(economy?['boxOpens']);
    final adDays = adminRows(ads?['days']);
    final cap = adminMap(ads?['capUtilization']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        adminStatHeading(context, 'REWARDED ADS (TODAY)'),
        adminStatRow(
          context,
          'DAU watched coin ad',
          rewardedAdLine(rewardedAds, 'coinReward'),
        ),
        adminStatRow(
          context,
          'DAU watched extra-spin ad',
          rewardedAdLine(rewardedAds, 'extraSpin'),
        ),

        adminStatHeading(context, 'COINS MINTED VS SUNK'),
        if (economyDays.isEmpty)
          adminStatRow(context, 'Per day (minted / sunk)', kAdminMissing)
        else
          for (final day in economyDays)
            adminStatRow(
              context,
              '${day['date'] ?? kAdminMissing}',
              adminPair(day['minted'], day['sunk']),
            ),

        adminStatHeading(context, 'SHOP PURCHASES BY SKU'),
        if (purchases.isEmpty)
          adminStatRow(context, 'Count · coins', kAdminMissing)
        else
          for (final row in purchases)
            adminStatRow(
              context,
              '${row['sku'] ?? kAdminMissing}',
              '${adminNumber(row['count'])} · ${adminNumber(row['coins'])}',
            ),

        adminStatHeading(context, 'BOX OPENS'),
        if (boxOpens.isEmpty)
          adminStatRow(context, 'Per day', kAdminMissing)
        else
          for (final row in boxOpens)
            adminStatRow(
              context,
              '${row['date'] ?? kAdminMissing}',
              adminNumber(row['count']),
            ),

        adminStatHeading(context, 'AD WATCHES'),
        if (adDays.isEmpty)
          adminStatRow(context, 'Per day (coin / extra spin)', kAdminMissing)
        else
          for (final day in adDays)
            adminStatRow(
              context,
              '${day['date'] ?? kAdminMissing}',
              adminPair(day['coinRewardWatches'], day['extraSpinWatches']),
            ),

        adminStatHeading(context, 'CAP UTILIZATION'),
        adminStatRow(
          context,
          'Avg watches/user',
          // An average, not a count: the integer reader would render 2.7 as 2
          // and quietly understate cap pressure.
          adminDecimal(cap?['avgWatchesPerUser']),
        ),
        adminStatRow(context, 'Users at cap', adminNumber(cap?['usersAtCap'])),
      ],
    );
  }
}

/// The one shared "this didn't load" note. Never an empty section: a blank
/// card is indistinguishable from a working card with no data.
class AdminSectionUnavailable extends StatelessWidget {
  const AdminSectionUnavailable({super.key, this.onRetry, this.retryKey});

  final VoidCallback? onRetry;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Couldn’t load this section (older backend?).',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
        if (onRetry != null)
          TextButton(
            key: retryKey,
            onPressed: onRetry,
            child: Text(
              'RETRY',
              style: PixelText.title(
                size: 12,
                color: AppColors.of(context).textAccent,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// INBOX
// ---------------------------------------------------------------------------

/// The suggestions viewer over `GET /admin/feedback/suggestions` — an endpoint
/// that has existed since the in-app suggestion box shipped and never had a UI.
///
/// Every field except `text` is optional as far as this widget is concerned:
/// the row renders from whatever the backend actually sent.
class AdminInboxBody extends StatefulWidget {
  const AdminInboxBody({
    super.key,
    required this.authService,
    this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;

  @override
  State<AdminInboxBody> createState() => _AdminInboxBodyState();
}

class _AdminInboxBodyState extends State<AdminInboxBody> {
  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();

  List<Map<String, dynamic>>? _suggestions;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _api.fetchAdminSuggestions(identityToken: token);
      if (!mounted) return;
      setState(() {
        // An older backend, or one that changed the envelope, yields an empty
        // inbox rather than an error — there is nothing an operator can do
        // about a shape change from here.
        _suggestions = adminRows(page['suggestions']);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_failed) {
      return AdminSectionUnavailable(
        onRetry: _load,
        retryKey: const Key('admin-inbox-retry'),
      );
    }

    final suggestions = _suggestions ?? const <Map<String, dynamic>>[];
    if (suggestions.isEmpty) {
      return Text(
        'No suggestions yet.',
        style: PixelText.body(size: 12, color: colors.textMid),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in suggestions) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _byline(row),
                  style: PixelText.title(size: 11, color: colors.textMid),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['text'] ?? ''}',
                  style: PixelText.body(size: 13, color: colors.textDark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// "Walker · feature · ios 2.2.0 · 2026-08-08" — each part dropped when the
  /// backend didn't send it, so the line never reads "null · null".
  String _byline(Map<String, dynamic> row) {
    final parts = <String>[];
    final name = row['displayName'];
    parts.add(name is String && name.trim().isNotEmpty ? name : 'Anonymous');

    final category = row['category'];
    if (category is String && category.trim().isNotEmpty) parts.add(category);

    final platform = row['platform'];
    final version = row['appVersion'];
    final build = [
      if (platform is String && platform.trim().isNotEmpty) platform,
      if (version is String && version.trim().isNotEmpty) version,
    ].join(' ');
    if (build.isNotEmpty) parts.add(build);

    final createdAt = row['createdAt'];
    if (createdAt is String && createdAt.length >= 10) {
      parts.add(createdAt.substring(0, 10));
    }
    return parts.join(' · ');
  }
}
