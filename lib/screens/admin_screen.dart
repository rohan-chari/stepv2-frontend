import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart' as error_toast;
import '../widgets/game_background.dart';
import '../widgets/info_toast.dart' as info_toast;
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/trail_sign.dart';
import 'admin_accessory_tuner_screen.dart';
import 'admin_balance_config_screen.dart';
import 'admin_powerup_shop_screen.dart';

/// Prefer the backend copy catalog so duration text tracks the server's
/// standardized powerup windows (spec §3.4/§6); fall back to the bundled
/// string only when the catalog doesn't cover the type.
String _adminPowerupDescription(String type, String fallback) {
  final catalog = PowerupCopy.descriptionFor(type);
  if (catalog.trim().isNotEmpty) return catalog;
  return fallback;
}

const _powerupEntries = [
  (
    type: 'LEG_CRAMP',
    name: 'Leg Cramp',
    description: 'Freeze a rival\'s steps for 2 hours',
  ),
  (
    type: 'RED_CARD',
    name: 'Red Card',
    description: 'Remove 5% of the leader\'s steps',
  ),
  (
    type: 'SHORTCUT',
    name: 'Shortcut',
    description: 'Steal 1,000 steps from a rival',
  ),
  (
    type: 'COMPRESSION_SOCKS',
    name: 'Compression Socks',
    description: 'Shield against the next attack',
  ),
  (
    type: 'PROTEIN_SHAKE',
    name: 'Protein Shake',
    description: '+1,500 bonus steps instantly',
  ),
  (
    type: 'RUNNERS_HIGH',
    name: "Runner's High",
    description: '2x steps for 3 hours',
  ),
  (
    type: 'SECOND_WIND',
    name: 'Second Wind',
    description: 'Bonus steps based on how far behind',
  ),
  (
    type: 'STEALTH_MODE',
    name: 'Stealth Mode',
    description: 'Hide your progress for 4 hours',
  ),
  (
    type: 'WRONG_TURN',
    name: 'Wrong Turn',
    description: 'Reverse a rival\'s steps for 1 hour',
  ),
  (
    type: 'FANNY_PACK',
    name: 'Fanny Pack',
    description: 'Unlock an extra powerup slot',
  ),
  (
    type: 'TRAIL_MIX',
    name: 'Trail Mix',
    description: '+100 steps per unique powerup type used',
  ),
  (
    type: 'DETOUR_SIGN',
    name: 'Detour Sign',
    description: 'Hide the entire leaderboard from a rival for 3 hours',
  ),
  (
    type: 'LUCKY_HORSESHOE',
    name: 'Lucky Horseshoe',
    description: 'Guarantee a better next mystery box',
  ),
  (
    type: 'CAMPFIRE_REST',
    name: 'Campfire Rest',
    description: 'Freeze for 30 min, then multiply steps for up to 90 min',
  ),
  (
    type: 'TRAIL_MAGNET',
    name: 'Trail Magnet',
    description: 'Pull your next mystery box 1,000 steps closer',
  ),
  (
    type: 'POCKET_WATCH',
    name: 'Pocket Watch',
    description: 'Extend all active timed buffs',
  ),
  (
    type: 'TRAIL_MINE',
    name: 'Trail Mine',
    description: 'Drop a hidden trap at your current step position',
  ),
  (
    type: 'PINECONE_TOSS',
    name: 'Pinecone Toss',
    description: 'Hit the runner directly ahead or behind you',
  ),
  (
    type: 'SNEAKY_SWAP',
    name: 'Sneaky Swap',
    description: 'Steal a random powerup from a rival',
  ),
  (
    type: 'MIRROR',
    name: 'Mirror',
    description: 'Reflect the next attack back at the attacker',
  ),
  (
    type: 'CLEANSE',
    name: 'Cleanse',
    description: 'Remove all debuffs an opponent placed on you',
  ),
  (
    type: 'IMPOSTER',
    name: 'Imposter',
    description:
        'Swap leaderboard positions with a rival for 1 hour (cosmetic)',
  ),
  (
    type: 'RAINSTORM',
    name: 'Rainstorm',
    description:
        'Everyone else\'s steps count for half for 1 hour (shields protect)',
  ),
  (
    type: 'SIGNAL_JAMMER',
    name: 'Signal Jammer',
    description:
        'Jam a rival\'s signal — they can\'t use any powerups for 1 hour',
  ),
  // §7 powerups5 store-only additions.
  (
    type: 'UPRISING',
    name: 'Uprising',
    description: '2x steps for 2 hours for everyone in the bottom half',
  ),
  (
    type: 'GHOST_PEPPER',
    name: 'Ghost Pepper',
    description: '3x steps for 30 min, then frozen for 30 min',
  ),
  (
    type: 'COIN_FLIP',
    name: 'Coin Flip',
    description: 'Heads doubles your steps for 1 hour, tails halves them',
  ),
  (
    type: 'MYSTERY_POTION',
    name: 'Mystery Potion',
    description: 'A random effect — boost, attack, or nasty surprise',
  ),
  (
    type: 'DECOY',
    name: 'Decoy',
    description: 'Redirect the next single-target attack to another racer',
  ),
  (
    type: 'POWER_OUTAGE',
    name: 'Power Outage',
    description: 'No rival can use powerups for 30 minutes',
  ),
  (
    type: 'UMBRELLA',
    name: 'Umbrella',
    description: 'Immune to Rainstorm and Power Outage for 12 hours',
  ),
  (
    type: 'RALLY_FLAG',
    name: 'Rally Flag',
    description: '1.25x steps for your whole team for 1 hour',
  ),
  (
    type: 'DRILL_SERGEANT',
    name: 'Drill Sergeant',
    description: 'Dare a rival to hit a step goal in 2 hours or lose steps',
  ),
  (
    type: 'PIGGY_BANK',
    name: 'Piggy Bank',
    description: 'Bank steps for 24 hours and cash them out as coins',
  ),
  (
    type: 'BOUNTY',
    name: 'Bounty',
    description: 'Out-place a rival ahead of you by race end to collect',
  ),
];

/// Runtime feature flags (backend AppSetting rows) — currently just the banner
/// ads kill switch. Toggling here changes what every client sees on its next
/// /auth/me sync; no app release needed.
class _AdminSettingsCard extends StatefulWidget {
  const _AdminSettingsCard({
    required this.width,
    required this.authService,
    required this.showErrorToast,
  });

  final double width;
  final AuthService authService;
  final void Function(BuildContext context, String message) showErrorToast;

  @override
  State<_AdminSettingsCard> createState() => _AdminSettingsCardState();
}

class _AdminSettingsCardState extends State<_AdminSettingsCard> {
  final _api = BackendApiService();
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null) return;
    try {
      final settings = await _api.fetchAdminSettings(identityToken: token);
      if (mounted) {
        setState(() {
          _settings = settings;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setSetting(String key, bool enabled) async {
    final token = widget.authService.authToken;
    if (token == null || _saving) return;
    final previous = _settings;
    setState(() {
      _saving = true;
      _settings = {...?_settings, key: enabled};
    });
    try {
      final updated = await _api.updateAdminSettings(
        identityToken: token,
        settings: {key: enabled},
      );
      if (mounted) setState(() => _settings = updated);
    } catch (_) {
      if (mounted) {
        setState(() => _settings = previous);
        widget.showErrorToast(context, 'Couldn\'t save the setting.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentBoard(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SETTINGS',
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_settings == null)
            Text(
              'Couldn\'t load settings.',
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            )
          else
            AdminSettingsCardBody(
              settings: _settings!,
              saving: _saving,
              onChanged: _setSetting,
            ),
        ],
      ),
    );
  }
}

/// One switch per client-served feature flag (the `featureFlags` envelope).
///
/// Server-only flags stay out on purpose — they change backend behavior, not
/// what a client renders, and a mis-tap on one of those is not recoverable from
/// this screen. Split out from the card so the full switch list is assertable
/// without a live admin session.
class AdminSettingsCardBody extends StatelessWidget {
  const AdminSettingsCardBody({
    super.key,
    required this.settings,
    required this.saving,
    required this.onChanged,
  });

  final Map<String, dynamic> settings;
  final bool saving;
  final void Function(String key, bool enabled) onChanged;

  /// Order matters: the two ad switches are the ones an operator reaches for
  /// most often, so they stay on top where they have always been.
  static const _flags = <({String key, String title, String blurb})>[
    (
      key: 'bannerAdsEnabled',
      title: 'Banner ads',
      blurb: 'Remote kill switch for every banner placement.',
    ),
    (
      key: 'dualBoxBannersEnabled',
      title: 'Dual box banners',
      blurb: 'Adds the dedicated top placement to box screens.',
    ),
    (
      key: 'teamRacesEnabled',
      title: 'Team races',
      blurb: 'Hides the team toggle in race creation when off. '
          'Existing team races keep running either way.',
    ),
    (
      key: 'onboardingV2Enabled',
      title: 'Onboarding v2',
      blurb: 'Skips the blocking tutorial gate for signed-in users.',
    ),
    (
      key: 'onboardingV3Enabled',
      title: 'Onboarding v3',
      blurb: 'Health-gate rework, degraded state, relocated notification '
          'ask, referral landing, five-step tutorial. Implies v2.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _flags.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _flags[i].title,
                      style: PixelText.title(size: 13, color: colors.textDark),
                    ),
                    Text(
                      _flags[i].blurb,
                      style: PixelText.body(size: 11, color: colors.textMid),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settings[_flags[i].key] == true,
                onChanged: saving
                    ? null
                    : (value) => onChanged(_flags[i].key, value),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // The flag cache is per-worker with a 30s TTL, so a toggle that looks
        // like it did nothing is usually just early. Saying so here stops the
        // re-tap that follows.
        Text(
          'Flags are cached for 30s per server, so a change takes up to 30s '
          'to reach every client.',
          style: PixelText.body(size: 11, color: colors.textMid),
        ),
      ],
    );
  }
}

/// The activation funnel from `GET /admin/stats` → `onboardingFunnel` (§6.5).
///
/// Design notes. A funnel is not a list of numbers, it is the *shape of the
/// loss between them* — and a plain table hides exactly the thing you opened
/// the screen to find. So every stage gets a proportional bar: the eye catches
/// the notch where a bar suddenly shortens long before it reads a percentage.
/// Everything else stays deliberately flat and dense (no gradients, no motion,
/// the same PixelText idiom as the stats card above) because this is an
/// operator tool and the bars are the one expressive element it needs.
///
/// Two of the seven stages are **not** funnel stages. `health_escaped` and
/// `health_probe_inconclusive` are side exits: users leave the happy path
/// there, they do not flow through them. Chaining step-over-step retention
/// across them would produce numbers that look authoritative and mean nothing,
/// so they are drawn as muted branch rows showing their share of the top of
/// funnel, and the retention chain skips them.
///
/// Absent section → renders nothing at all. Not an error, not an empty card:
/// the backend and the app deploy independently, and an admin on a new build
/// against an old backend should simply not see a funnel yet (§8.11).
class OnboardingFunnelSection extends StatefulWidget {
  const OnboardingFunnelSection({super.key, required this.funnel});

  final Map<String, dynamic>? funnel;

  /// Display order, exactly as pinned in §6.5.
  static const stageKeys = <String>[
    'onboarding_started',
    'health_cta_tapped',
    'health_granted',
    'health_escaped',
    'health_probe_inconclusive',
    'daily_intro_viewed',
    // The teaching step, which under v3 is the playable demo race. Order is
    // pinned to the backend's ONBOARDING_FUNNEL_STAGES: this list only decides
    // what is DRAWN, so the two must not drift or the rows read out of order.
    'tutorial_opened',
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    'tutorial_completed',
    'home_reached',
  ];

  /// Index-aligned with [stageKeys] — `stageLabels[i]` is read directly.
  static const stageLabels = <String>[
    'Started',
    'Health CTA',
    'Health granted',
    'Escaped',
    'Probe zero',
    'Race intro',
    'Tutorial opened',
    'Box opened',
    'Powerup used',
    'Race won',
    'Tutorial done',
    'Home reached',
  ];

  /// The stages users actually flow through, in order. Retention is chained
  /// along this spine only.
  ///
  /// The demo-race stages are all spine: a user genuinely flows opened → box →
  /// powerup → won → finished, so step-over-step retention is exactly the
  /// number worth reading. `tutorial_skipped` is deliberately absent from
  /// [stageKeys] entirely — it is an exit, and the backend has no way to mark
  /// one, so charting it would invent a stage nobody flows through.
  static const _spine = <String>[
    'onboarding_started',
    'health_cta_tapped',
    'health_granted',
    'daily_intro_viewed',
    'tutorial_opened',
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    'tutorial_completed',
    'home_reached',
  ];

  static bool _isSideExit(String key) => !_spine.contains(key);

  @override
  State<OnboardingFunnelSection> createState() =>
      _OnboardingFunnelSectionState();
}

class _OnboardingFunnelSectionState extends State<OnboardingFunnelSection> {
  bool _thirtyDays = false;

  Map<String, dynamic>? _platforms(String key) {
    final raw = widget.funnel?[key];
    return raw is Map<String, dynamic> ? raw : null;
  }

  int _count(Map<String, dynamic>? stages, String key) {
    final value = stages?[key];
    return value is num ? value.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final sevenDay = _platforms('byPlatform');
    if (sevenDay == null || sevenDay.isEmpty) return const SizedBox.shrink();
    final thirtyDay = _platforms('byPlatformLast30Days');
    final active = (_thirtyDays && thirtyDay != null) ? thirtyDay : sevenDay;

    final windowDays = widget.funnel?['windowDays'];
    final sevenLabel = '${windowDays is num ? windowDays.toInt() : 7}D';

    final colors = AppColors.of(context);
    final platforms = <String>[
      for (final name in const ['ios', 'android'])
        if (active[name] is Map<String, dynamic>) name,
    ];
    if (platforms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'ONBOARDING FUNNEL',
                style: PixelText.title(size: 12, color: colors.textDark),
              ),
            ),
            if (thirtyDay != null) ...[
              _WindowChip(
                label: sevenLabel,
                selected: !_thirtyDays,
                onTap: () => setState(() => _thirtyDays = false),
              ),
              const SizedBox(width: 6),
              _WindowChip(
                label: '30D',
                selected: _thirtyDays,
                onTap: () => setState(() => _thirtyDays = true),
              ),
            ],
          ],
        ),
        Text(
          'Distinct onboarding sessions reaching each stage.',
          style: PixelText.body(size: 11, color: colors.textMid),
        ),
        for (final platform in platforms) ...[
          const SizedBox(height: 10),
          Text(
            platform.toUpperCase(),
            style: PixelText.title(size: 11, color: colors.textMid),
          ),
          const SizedBox(height: 4),
          ..._stageRows(active[platform] as Map<String, dynamic>),
        ],
      ],
    );
  }

  List<Widget> _stageRows(Map<String, dynamic> stages) {
    final counts = {
      for (final key in OnboardingFunnelSection.stageKeys)
        key: _count(stages, key),
    };
    // Scale to the largest stage rather than to `onboarding_started`, so the
    // bars stay meaningful even if the top of funnel is missing or somehow
    // smaller than a later stage.
    final scale = counts.values.fold<int>(0, (a, v) => v > a ? v : a);
    final start = counts['onboarding_started'] ?? 0;

    String? previousSpineKey;
    final rows = <Widget>[];
    for (var i = 0; i < OnboardingFunnelSection.stageKeys.length; i++) {
      final key = OnboardingFunnelSection.stageKeys[i];
      final count = counts[key] ?? 0;
      final sideExit = OnboardingFunnelSection._isSideExit(key);

      String trailing;
      if (sideExit) {
        trailing = start > 0
            ? '${((count / start) * 100).round()}% of start'
            : '—';
      } else if (previousSpineKey == null) {
        trailing = '—';
      } else {
        final previous = counts[previousSpineKey] ?? 0;
        trailing = previous > 0
            ? '${((count / previous) * 100).round()}%'
            : '—';
      }
      if (!sideExit) previousSpineKey = key;

      rows.add(
        _FunnelRow(
          label: OnboardingFunnelSection.stageLabels[i],
          count: count,
          trailing: trailing,
          fraction: scale > 0 ? (count / scale).clamp(0.0, 1.0) : 0.0,
          sideExit: sideExit,
        ),
      );
    }
    return rows;
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.accent : colors.parchmentBorder,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: PixelText.title(
              size: 10,
              color: selected ? colors.textLight : colors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

/// One stage: a label/count/percentage line with its proportional bar directly
/// beneath, so the bars form a single scannable silhouette down the column.
class _FunnelRow extends StatelessWidget {
  const _FunnelRow({
    required this.label,
    required this.count,
    required this.trailing,
    required this.fraction,
    required this.sideExit,
  });

  final String label;
  final int count;
  final String trailing;
  final double fraction;
  final bool sideExit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final barColor = sideExit ? colors.pillTerra : colors.accent;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideExit ? 12 : 0, 3, 0, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (sideExit)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 13,
                    color: colors.textMid,
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
              ),
              Text(
                '$count',
                style: PixelText.title(size: 13, color: colors.textDark),
              ),
              SizedBox(
                width: 78,
                child: Text(
                  trailing,
                  textAlign: TextAlign.right,
                  style: PixelText.body(size: 11, color: colors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: colors.textMid.withValues(alpha: 0.14),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: ColoredBox(color: barColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product-health snapshot (GET /admin/stats): invite funnel, friends
/// distribution, DAU-in-race, and D1/D7 retention split by has-friend.
class AdminStatsCard extends StatefulWidget {
  const AdminStatsCard({
    super.key,
    required this.width,
    required this.authService,
    this.backendApiService,
  });

  final double width;
  final AuthService authService;
  final BackendApiService? backendApiService;

  @override
  State<AdminStatsCard> createState() => _AdminStatsCardState();
}

class _AdminStatsCardState extends State<AdminStatsCard> {
  late final BackendApiService _api;
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null) return;
    setState(() => _loading = true);
    try {
      final stats = await _api.fetchAdminStats(identityToken: token);
      if (mounted) {
        setState(() {
          _stats = stats.isEmpty ? null : stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _row(String label, String value) {
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

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        title,
        style: PixelText.title(size: 12, color: AppColors.of(context).textDark),
      ),
    );
  }

  String _retentionLine(Map<String, dynamic>? side, String day) {
    if (side == null) return '—';
    final cohort = (side['${day}Cohort'] as num?)?.toInt() ?? 0;
    final retained = (side['${day}Retained'] as num?)?.toInt() ?? 0;
    if (cohort == 0) return '—';
    final pct = ((retained / cohort) * 100).round();
    return '$retained/$cohort ($pct%)';
  }

  String _rewardedAdLine(Map<String, dynamic>? rewarded, String key) {
    final value = rewarded?[key];
    if (value is! Map) return '—';
    final count = value['uniqueDauWatchers'];
    final pct = value['pctOfDau'];
    if (count is! num || pct is! num) return '—';
    return '${count.toInt()} (${pct.toInt()}%)';
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final users = stats?['users'] as Map<String, dynamic>?;
    final activity = stats?['activity'] as Map<String, dynamic>?;
    final rewardedAds = activity?['rewardedAds'] is Map<String, dynamic>
        ? activity!['rewardedAds'] as Map<String, dynamic>
        : null;
    final friends =
        (stats?['friends'] as Map<String, dynamic>?)?['distribution']
            as Map<String, dynamic>?;
    final retention = stats?['retention'] as Map<String, dynamic>?;
    final withFriend = retention?['withFriend'] as Map<String, dynamic>?;
    final withoutFriend = retention?['withoutFriend'] as Map<String, dynamic>?;
    final funnel = stats?['referralFunnel'] as Map<String, dynamic>?;
    // Additive section (§6.5). Absent on any backend that predates the
    // activation-funnel query, in which case the widget renders nothing.
    final onboardingFunnel = stats?['onboardingFunnel'] is Map<String, dynamic>
        ? stats!['onboardingFunnel'] as Map<String, dynamic>
        : null;

    return ContentBoard(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'STATISTICS',
                  style: PixelText.title(
                    size: 16,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (stats == null)
            Text(
              'Couldn\'t load stats (older backend?).',
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            )
          else ...[
            _section('USERS'),
            _row('Total', '${users?['total'] ?? '—'}'),
            _row(
              'New (7d / 30d)',
              '${users?['newLast7Days'] ?? '—'} / ${users?['newLast30Days'] ?? '—'}',
            ),
            _section('TODAY'),
            _row('DAU (stepped today)', '${activity?['dauToday'] ?? '—'}'),
            _row(
              'DAU watched coin ad',
              _rewardedAdLine(rewardedAds, 'coinReward'),
            ),
            _row(
              'DAU watched extra-spin ad',
              _rewardedAdLine(rewardedAds, 'extraSpin'),
            ),
            _row(
              'In an active race',
              '${activity?['dauInActiveRace'] ?? '—'} '
                  '(${activity?['pctDauInActiveRace'] ?? '—'}%)',
            ),
            // Item 9: avg unique users opening an in-race mystery box per ET day.
            // Null-safe — the backend field only exists after the box-open
            // logging deploy, and reads '—' until data accrues.
            _row(
              'Avg box openers/day',
              '${activity?['avgUniqueBoxOpenersPerDay'] ?? '—'}',
            ),
            _section('FRIENDS PER USER'),
            _row(
              '0 / 1 / 2 / 3-5 / 6+',
              '${friends?['0'] ?? 0} / ${friends?['1'] ?? 0} / '
                  '${friends?['2'] ?? 0} / ${friends?['3-5'] ?? 0} / '
                  '${friends?['6+'] ?? 0}',
            ),
            _section('RETENTION (LAST 32D COHORT)'),
            _row('D1 with friend', _retentionLine(withFriend, 'd1')),
            _row('D1 no friend', _retentionLine(withoutFriend, 'd1')),
            _row('D7 with friend', _retentionLine(withFriend, 'd7')),
            _row('D7 no friend', _retentionLine(withoutFriend, 'd7')),
            _section('INVITE FUNNEL'),
            _row(
              'Link opens (7d / all)',
              '${funnel?['linkOpensLast7Days'] ?? '—'} / ${funnel?['linkOpensTotal'] ?? '—'}',
            ),
            _row(
              'Referred signups (7d / all)',
              '${funnel?['signupsLast7Days'] ?? '—'} / ${funnel?['signups'] ?? '—'}',
            ),
            _row('Joined a race', '${funnel?['joinedRace'] ?? '—'}'),
            _row('Finished a race', '${funnel?['finishedRace'] ?? '—'}'),
            _row('Rewarded', '${funnel?['rewarded'] ?? '—'}'),
            OnboardingFunnelSection(funnel: onboardingFunnel),
          ],
        ],
      ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.authService,
    this.showInfoToast = info_toast.showInfoToast,
    this.showErrorToast = error_toast.showErrorToast,
  });

  final AuthService authService;
  final void Function(BuildContext context, String message) showInfoToast;
  final void Function(BuildContext context, String message) showErrorToast;

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.of(context).textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            child: Column(
              children: [
                TrailSign(
                  width: boardWidth,
                  child: Text(
                    'ADMIN TOOLS',
                    style: PixelText.title(
                      size: 22,
                      color: AppColors.of(context).textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                _AdminSettingsCard(
                  width: boardWidth,
                  authService: authService,
                  showErrorToast: showErrorToast,
                ),
                const SizedBox(height: 24),
                AdminStatsCard(width: boardWidth, authService: authService),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOAST TESTS',
                        style: PixelText.title(
                          size: 14,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PillButton(
                              label: 'TEST INFO TOAST',
                              variant: PillButtonVariant.primary,
                              fontSize: 11,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              onPressed: () => showInfoToast(
                                context,
                                'This is a test notification toast.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PillButton(
                              label: 'TEST ERROR TOAST',
                              variant: PillButtonVariant.accent,
                              fontSize: 11,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              onPressed: () => showErrorToast(
                                context,
                                'This is a test error toast.',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POWERUP ICONS',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final entry in _powerupEntries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: PowerupIcon(
                                  type: entry.type,
                                  size: 28,
                                  spinning: true,
                                  spinDuration: const Duration(
                                    milliseconds: 2800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: PixelText.title(
                                        size: 13,
                                        color: AppColors.of(context).textDark,
                                      ),
                                    ),
                                    Text(
                                      _adminPowerupDescription(
                                        entry.type,
                                        entry.description,
                                      ),
                                      style: PixelText.body(
                                        size: 11,
                                        color: AppColors.of(context).textMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COSMETICS',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PillButton(
                        label: 'ACCESSORY RENDER TUNER',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AdminAccessoryTunerScreen(
                              authService: authService,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ECONOMY',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PillButton(
                        label: 'BALANCE CONFIG',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AdminBalanceConfigScreen(
                              authService: authService,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PillButton(
                        label: 'POWERUP SHOP',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AdminPowerupShopScreen(
                              authService: authService,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    children: [
                      Text(
                        'POWERUP CRATE',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SpinningCrate(size: 100),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
