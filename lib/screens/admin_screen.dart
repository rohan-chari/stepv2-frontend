import 'package:flutter/material.dart';

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

  Future<void> _setBannerAds(bool enabled) async {
    await _setSetting('bannerAdsEnabled', enabled);
  }

  Future<void> _setDualBoxBanners(bool enabled) async {
    await _setSetting('dualBoxBannersEnabled', enabled);
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
    final bannerAdsEnabled = _settings?['bannerAdsEnabled'] == true;
    final dualBoxBannersEnabled = _settings?['dualBoxBannersEnabled'] == true;
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
          else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Banner ads',
                        style: PixelText.title(
                          size: 13,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      Text(
                        'Remote kill switch — applies on each client\'s '
                        'next launch/resume.',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: bannerAdsEnabled,
                  onChanged: _saving ? null : _setBannerAds,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dual box banners',
                        style: PixelText.title(
                          size: 13,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      Text(
                        'Adds the dedicated top placement to box screens.',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: dualBoxBannersEnabled,
                  onChanged: _saving ? null : _setDualBoxBanners,
                ),
              ],
            ),
          ],
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
                                      entry.description,
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
