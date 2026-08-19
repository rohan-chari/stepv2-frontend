import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../models/admin_metrics_dashboard.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart' as error_toast;
import '../widgets/game_background.dart';
import '../widgets/info_toast.dart' as info_toast;
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/trail_sign.dart';
import 'admin_accessory_tuner_screen.dart';
import 'admin_metrics_dashboard.dart';
import 'admin_sections.dart';
import 'admin_balance_config_screen.dart';
import 'admin_powerup_shop_screen.dart';

/// Runtime feature flags (backend AppSetting rows). Toggling here changes what
/// every client sees on its next /auth/me sync; no app release needed.
///
/// Batch 2026-08-09 item 10: no longer draws its own board or SETTINGS title —
/// it is the body of the hub's CONFIG section now.
class AdminFlagsPanel extends StatefulWidget {
  const AdminFlagsPanel({
    super.key,
    required this.authService,
    required this.showErrorToast,
    this.backendApiService,
  });

  final AuthService authService;
  final void Function(BuildContext context, String message) showErrorToast;
  final BackendApiService? backendApiService;

  @override
  State<AdminFlagsPanel> createState() => _AdminFlagsPanelState();
}

class _AdminFlagsPanelState extends State<AdminFlagsPanel> {
  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
  final TextEditingController _serviceBannerMessage = TextEditingController();
  bool _serviceBannerEnabled = false;

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
          _serviceBannerEnabled = settings['homeServiceBannerEnabled'] == true;
          final message = settings['homeServiceBannerMessage'];
          _serviceBannerMessage.text = message is String ? message : '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _serviceBannerMessage.dispose();
    super.dispose();
  }

  Future<void> _saveHomeServiceBanner() async {
    final token = widget.authService.authToken;
    final message = _serviceBannerMessage.text.trim();
    if (token == null || token.isEmpty || _saving) return;
    if (_serviceBannerEnabled && (message.isEmpty || message.length > 240)) {
      widget.showErrorToast(context, 'Enter a 1–240 character banner message.');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await _api.updateAdminHomeServiceBanner(
        identityToken: token,
        enabled: _serviceBannerEnabled,
        message: _serviceBannerEnabled ? message : '',
      );
      // The endpoint must echo the standard full settings envelope. A malformed
      // or legacy response must not erase the settings this panel already has.
      if (updated.isEmpty) {
        throw const ApiException('Invalid settings response');
      }
      if (mounted) {
        setState(() {
          _settings = updated;
          _serviceBannerEnabled = updated['homeServiceBannerEnabled'] == true;
          final returnedMessage = updated['homeServiceBannerMessage'];
          _serviceBannerMessage.text = returnedMessage is String
              ? returnedMessage
              : '';
        });
      }
    } catch (_) {
      if (mounted) widget.showErrorToast(context, 'Couldn\'t save the banner.');
    } finally {
      if (mounted) setState(() => _saving = false);
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final settings = _settings;
    if (settings == null) {
      return Text(
        'Couldn\'t load settings.',
        style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSettingsCardBody(
          settings: settings,
          saving: _saving,
          onChanged: _setSetting,
        ),
        const SizedBox(height: 18),
        Text(
          'HOME SERVICE BANNER',
          style: PixelText.title(
            size: 13,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Persistent plain-text status notice on Home.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: _serviceBannerEnabled,
          onChanged: _saving
              ? null
              : (value) => setState(() => _serviceBannerEnabled = value),
        ),
        TextField(
          key: const Key('admin-home-service-banner-message'),
          controller: _serviceBannerMessage,
          enabled: !_saving,
          maxLength: 240,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Service status message'),
        ),
        PillButton(
          label: _saving ? 'SAVING…' : 'SAVE SERVICE BANNER',
          fullWidth: true,
          onPressed: _saving ? null : _saveHomeServiceBanner,
        ),
      ],
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
      blurb:
          'Hides the team toggle in race creation when off. '
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
      blurb:
          'Health-gate rework, degraded state, relocated notification '
          'ask, referral landing, five-step tutorial. Implies v2.',
    ),
    (
      key: 'onboardingInviteCodeEnabled',
      title: 'Onboarding invite code',
      blurb:
          'KILL SWITCH (defaults ON): the "got an invite code?" step at '
          'the top of the v3 flow. Off removes it with no app release.',
    ),
    // Batch 2026-08-09 item 9. Flip ON only once the carrying build has
    // rolled out — older binaries ignore it and stay skippable either way.
    (
      key: 'tutorialMandatoryEnabled',
      title: 'Mandatory tutorial',
      blurb:
          'Removes every skip/back exit from the onboarding tutorial. '
          'Settings replay stays optional; a client-side breaker restores '
          'skip after 3 abandoned attempts.',
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

/// The admin hub — batch 2026-08-09 item 10.
///
/// Was one flat scroll of eight unlabelled boards. It is now six named,
/// collapsible sections in a fixed order (GROWTH, ENGAGEMENT, REVENUE, CONFIG,
/// INBOX, DEBUG) so an operator can find a number without reading past a
/// spinning crate.
///
/// The fetch strategy is the load-bearing part. `GET /admin/stats` with NO
/// `sections` param is the legacy payload and the legacy query set — that one
/// request feeds GROWTH and ENGAGEMENT. The REVENUE aggregates are opt-in and
/// only requested the first time that section is opened, because the prod box
/// has one vCPU and nobody should pay for ten `$queryRaw` aggregates to look
/// at the retention table. INBOX is lazy for the same reason.
class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.showInfoToast = info_toast.showInfoToast,
    this.showErrorToast = error_toast.showErrorToast,
    this.isIosForTesting,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final void Function(BuildContext context, String message) showInfoToast;
  final void Function(BuildContext context, String message) showErrorToast;
  final bool? isIosForTesting;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();

  /// The legacy payload: GROWTH + ENGAGEMENT read from this.
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;
  bool _statsFailed = false;

  /// The legacy payload PLUS `coinEconomy` and `adRevenue`. Null until the
  /// REVENUE section has been opened at least once.
  Map<String, dynamic>? _revenueStats;
  bool _revenueLoading = false;
  bool _revenueFailed = false;
  bool _revenueRequested = false;

  final Map<String, _DashboardRequestState> _dashboardRequests = {};
  final Set<String> _openedDashboardSections = {};
  Future<void> _dashboardQueue = Future.value();
  Future<void>? _refreshInFlight;
  Future<void>? _lastRefreshFuture;
  DateTime? _lastRefreshStartedAt;
  Map<String, dynamic>? _legacyFallbackStats;

  bool get _usesMetricsDashboard => widget.isIosForTesting ?? Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_usesMetricsDashboard) {
      _requestDashboardSection('dashboard-summary');
    } else {
      _loadStats();
    }
  }

  _DashboardRequestState _dashboardState(String section) =>
      _dashboardRequests.putIfAbsent(section, _DashboardRequestState.new);

  Future<void> _requestDashboardSection(String section, {bool force = false}) {
    final state = _dashboardState(section);
    if (!force && (state.loading || state.envelope != null || state.failed)) {
      return state.pending ?? Future.value();
    }
    state
      ..loading = true
      ..failed = false;
    if (mounted) setState(() {});

    final operation = _dashboardQueue
        .then((_) async {
          final token = widget.authService.authToken;
          if (token == null || token.isEmpty) {
            throw const ApiException('Missing authentication');
          }
          final stats = await _api.fetchAdminStats(
            identityToken: token,
            sections: [section],
            window: '30d',
          );
          final envelope = AdminMetricsEnvelope.fromStats(stats);
          if (!mounted) return;
          setState(() {
            state
              ..envelope = envelope
              ..loading = false
              ..failed = false;
            if (section == 'dashboard-summary' && !envelope.present) {
              _legacyFallbackStats = stats;
            }
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            state
              ..loading = false
              ..failed = true;
          });
        });
    state.pending = operation;
    _dashboardQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  void _openDashboardSection(String section) {
    _openedDashboardSections.add(section);
    unawaited(_requestDashboardSection(section));
  }

  Future<void> _refreshDashboard() {
    final now = DateTime.now();
    final lastStarted = _lastRefreshStartedAt;
    if (_refreshInFlight == null &&
        lastStarted != null &&
        now.difference(lastStarted) < const Duration(milliseconds: 500)) {
      return _lastRefreshFuture ?? Future.value();
    }
    _lastRefreshStartedAt = now;
    final future = _refreshInFlight ??= _runDashboardRefresh().whenComplete(() {
      _refreshInFlight = null;
      if (mounted) setState(() {});
    });
    _lastRefreshFuture = future;
    return future;
  }

  Future<void> _runDashboardRefresh() async {
    if (mounted) setState(() {});
    await _requestDashboardSection('dashboard-summary', force: true);
    const order = [
      'dashboard-growth',
      'dashboard-funnels',
      'dashboard-activation',
      'dashboard-retention',
      'dashboard-engagement',
      'dashboard-virality',
      'dashboard-revenue',
      'dashboard-release-adoption',
    ];
    for (final section in order) {
      if (_openedDashboardSections.contains(section)) {
        await _requestDashboardSection(section, force: true);
      }
    }
  }

  Future<void> _loadStats() async {
    final token = widget.authService.authToken;
    if (token == null) {
      setState(() {
        _statsLoading = false;
        _statsFailed = true;
      });
      return;
    }
    setState(() {
      _statsLoading = true;
      _statsFailed = false;
    });
    try {
      final stats = await _api.fetchAdminStats(identityToken: token);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
        _statsFailed = true;
      });
    }

    // REVENUE latches `_revenueRequested` so that collapsing and re-opening
    // the section can't re-run ten aggregates. That latch also froze its
    // numbers for the life of the screen — refresh has to clear it, but only
    // when the section was actually opened, or refresh would start paying for
    // aggregates nobody asked to see.
    if (_revenueStats != null || _revenueFailed) {
      _revenueRequested = false;
      await _loadRevenue();
    }
  }

  /// Fired once, by the REVENUE section's first expand.
  Future<void> _loadRevenue() async {
    if (_revenueRequested) return;
    _revenueRequested = true;

    final token = widget.authService.authToken;
    if (token == null) {
      if (!mounted) return;
      setState(() => _revenueFailed = true);
      return;
    }
    setState(() {
      _revenueLoading = true;
      _revenueFailed = false;
    });
    try {
      // Both blocks in one round trip — the section renders them together, so
      // splitting them would only double the latency.
      final stats = await _api.fetchAdminStats(
        identityToken: token,
        sections: const ['economy', 'ads'],
      );
      if (!mounted) return;
      setState(() {
        _revenueStats = stats;
        _revenueLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _revenueLoading = false;
        _revenueFailed = true;
      });
    }
  }

  /// GROWTH/ENGAGEMENT bodies want null to mean "couldn't load"; an empty map
  /// means "loaded, but this backend sends nothing", which still renders rows.
  Map<String, dynamic>? get _sharedStats => _statsFailed ? null : _stats;

  @override
  Widget build(BuildContext context) {
    if (_usesMetricsDashboard) return _buildMetricsDashboard(context);
    final boardWidth = MediaQuery.of(context).size.width - 48;
    final colors = AppColors.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: colors.textDark),
            onPressed: _statsLoading ? null : _loadStats,
          ),
        ],
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
                    style: PixelText.title(size: 22, color: colors.textDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),

                // -- GROWTH ------------------------------------------------
                AdminSection(
                  title: 'GROWTH',
                  width: boardWidth,
                  // The one section that opens by default: it is what the
                  // screen is usually opened to read.
                  initiallyExpanded: true,
                  child: _statsLoading
                      ? const _SectionSpinner()
                      : AdminGrowthStatsBody(stats: _sharedStats),
                ),
                const SizedBox(height: 16),

                // -- ENGAGEMENT --------------------------------------------
                AdminSection(
                  title: 'ENGAGEMENT',
                  width: boardWidth,
                  child: _statsLoading
                      ? const _SectionSpinner()
                      : AdminEngagementStatsBody(stats: _sharedStats),
                ),
                const SizedBox(height: 16),

                // -- REVENUE -----------------------------------------------
                AdminSection(
                  title: 'REVENUE',
                  width: boardWidth,
                  onFirstExpand: _loadRevenue,
                  child: AdminRevenueBody(
                    // Falls back to the base payload so the rewarded-ad rows
                    // still render while the sectioned request is in flight.
                    stats: _revenueStats ?? _sharedStats,
                    loading: _revenueLoading,
                    failed: _revenueFailed && _revenueStats == null,
                  ),
                ),
                const SizedBox(height: 16),

                // -- CONFIG ------------------------------------------------
                AdminSection(
                  title: 'CONFIG',
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminFlagsPanel(
                        authService: widget.authService,
                        backendApiService: widget.backendApiService,
                        showErrorToast: widget.showErrorToast,
                      ),
                      const SizedBox(height: 16),
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
                              authService: widget.authService,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                              authService: widget.authService,
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
                              authService: widget.authService,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // -- INBOX -------------------------------------------------
                AdminSection(
                  title: 'INBOX',
                  width: boardWidth,
                  child: AdminInboxBody(
                    authService: widget.authService,
                    backendApiService: widget.backendApiService,
                  ),
                ),
                const SizedBox(height: 16),

                // -- DEBUG -------------------------------------------------
                // Kept, not deleted: the toast harness and the icon gallery
                // are how rendering regressions get caught by hand. They just
                // stop being the first thing on the screen.
                AdminSection(
                  title: 'DEBUG',
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOAST TESTS',
                        style: PixelText.title(
                          size: 14,
                          color: colors.textDark,
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
                              onPressed: () => widget.showInfoToast(
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
                              onPressed: () => widget.showErrorToast(
                                context,
                                'This is a test error toast.',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'POWERUP ICONS',
                        style: PixelText.title(
                          size: 14,
                          color: colors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Driven off PowerupIcon's own asset map, not a
                      // hand-kept copy of it: the old parallel list had
                      // drifted five types behind the shipped art. Names and
                      // descriptions come from the backend copy catalog, with
                      // the bundled fallback underneath (PowerupCopy handles
                      // that resolution order itself).
                      for (final type in PowerupIcon.knownTypes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: PowerupIcon(
                                  type: type,
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
                                      PowerupCopy.nameFor(type),
                                      style: PixelText.title(
                                        size: 13,
                                        color: colors.textDark,
                                      ),
                                    ),
                                    Text(
                                      PowerupCopy.descriptionFor(type),
                                      style: PixelText.body(
                                        size: 11,
                                        color: colors.textMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'POWERUP CRATE',
                        style: PixelText.title(
                          size: 14,
                          color: colors.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Center(child: SpinningCrate(size: 100)),
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

  Widget _buildMetricsDashboard(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;
    final colors = AppColors.of(context);
    final summaryState = _dashboardState('dashboard-summary');
    final summary = summaryState.envelope;
    final dashboardUnavailable = summary != null && !summary.present;
    final dashboardDisabled = summary?.status == AdminDashboardStatus.disabled;
    final dashboardStatusUnavailable =
        summary?.status == AdminDashboardStatus.unavailable;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: colors.textDark),
            onPressed: _refreshInFlight == null ? _refreshDashboard : null,
          ),
        ],
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
                    style: PixelText.title(size: 22, color: colors.textDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                if (dashboardUnavailable)
                  _dashboardMessageBoard(
                    boardWidth,
                    'Dashboard requires a server update',
                  )
                else if (dashboardDisabled)
                  _dashboardMessageBoard(
                    boardWidth,
                    'Dashboard temporarily disabled',
                  )
                else if (dashboardStatusUnavailable)
                  _dashboardMessageBoard(boardWidth, 'Dashboard unavailable')
                else ...[
                  AdminSection(
                    title: 'SUMMARY',
                    width: boardWidth,
                    initiallyExpanded: true,
                    child: _dashboardBody(
                      requestSection: 'dashboard-summary',
                      viewSection: 'dashboard-summary',
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final route in const [
                    (
                      title: 'USER GROWTH',
                      request: 'dashboard-growth',
                      view: 'dashboard-growth',
                    ),
                    (
                      title: 'INVITE FUNNEL',
                      request: 'dashboard-funnels',
                      view: 'dashboard-funnels-invite',
                    ),
                    (
                      title: 'ONBOARDING FUNNEL',
                      request: 'dashboard-funnels',
                      view: 'dashboard-funnels-onboarding',
                    ),
                    (
                      title: 'ACTIVATION',
                      request: 'dashboard-activation',
                      view: 'dashboard-activation',
                    ),
                    (
                      title: 'RETENTION',
                      request: 'dashboard-retention',
                      view: 'dashboard-retention',
                    ),
                    (
                      title: 'RACE + ENGAGEMENT',
                      request: 'dashboard-engagement',
                      view: 'dashboard-engagement',
                    ),
                    (
                      title: 'VIRALITY',
                      request: 'dashboard-virality',
                      view: 'dashboard-virality',
                    ),
                    (
                      title: 'REVENUE',
                      request: 'dashboard-revenue',
                      view: 'dashboard-revenue',
                    ),
                  ]) ...[
                    AdminSection(
                      title: route.title,
                      width: boardWidth,
                      onFirstExpand: () => _openDashboardSection(route.request),
                      child: _dashboardBody(
                        requestSection: route.request,
                        viewSection: route.view,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                if (dashboardUnavailable ||
                    dashboardDisabled ||
                    dashboardStatusUnavailable)
                  const SizedBox(height: 16),
                _buildMetricsConfig(boardWidth),
                const SizedBox(height: 16),
                AdminSection(
                  title: 'INBOX',
                  width: boardWidth,
                  child: AdminInboxBody(
                    authService: widget.authService,
                    backendApiService: widget.backendApiService,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMetricsDebug(boardWidth, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboardMessageBoard(double width, String message) => AdminSection(
    title: 'SUMMARY',
    width: width,
    initiallyExpanded: true,
    child: AdminMetricsStatePanel(message: message),
  );

  Widget _dashboardBody({
    required String requestSection,
    required String viewSection,
  }) {
    final state = _dashboardState(requestSection);
    if (state.loading && state.envelope == null) return const _SectionSpinner();
    if (state.failed && state.envelope == null) {
      return AdminMetricsStatePanel(
        message: 'Couldn’t load this section.',
        retryKey: Key('admin-dashboard-retry-$requestSection'),
        onRetry: () => _requestDashboardSection(requestSection, force: true),
      );
    }
    final envelope = state.envelope;
    if (envelope == null || !envelope.present) {
      return const AdminMetricsStatePanel(message: 'Section unavailable.');
    }
    if (envelope.status == AdminDashboardStatus.disabled) {
      return const AdminMetricsStatePanel(
        message: 'Dashboard temporarily disabled',
      );
    }
    if (envelope.status != AdminDashboardStatus.available) {
      return const AdminMetricsStatePanel(message: 'Section unavailable.');
    }
    return AdminMetricsSectionBody(section: viewSection, envelope: envelope);
  }

  Widget _buildMetricsConfig(double boardWidth) => AdminSection(
    title: 'CONFIG',
    width: boardWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminFlagsPanel(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
          showErrorToast: widget.showErrorToast,
        ),
        const SizedBox(height: 16),
        for (final item in [
          (
            label: 'ACCESSORY RENDER TUNER',
            builder: (BuildContext context) =>
                AdminAccessoryTunerScreen(authService: widget.authService),
          ),
          (
            label: 'BALANCE CONFIG',
            builder: (BuildContext context) =>
                AdminBalanceConfigScreen(authService: widget.authService),
          ),
          (
            label: 'POWERUP SHOP',
            builder: (BuildContext context) =>
                AdminPowerupShopScreen(authService: widget.authService),
          ),
        ]) ...[
          PillButton(
            label: item.label,
            variant: PillButtonVariant.primary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: item.builder)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    ),
  );

  Widget _buildMetricsDebug(double boardWidth, AppPalette colors) {
    final releaseState = _dashboardState('dashboard-release-adoption');
    final legacyVersions = _legacyFallbackStats?['versions'];
    final hasLegacyVersions =
        legacyVersions is List && legacyVersions.isNotEmpty;
    return AdminSection(
      title: 'DEBUG',
      width: boardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_legacyFallbackStats == null || hasLegacyVersions) ...[
            AdminSection(
              title: 'RELEASE ADOPTION',
              width: boardWidth - 24,
              onFirstExpand: _legacyFallbackStats != null
                  ? null
                  : () => _openDashboardSection('dashboard-release-adoption'),
              child: _legacyFallbackStats != null
                  ? AdminLegacyReleaseAdoptionBody(stats: _legacyFallbackStats)
                  : releaseState.loading && releaseState.envelope == null
                  ? const _SectionSpinner()
                  : _dashboardBody(
                      requestSection: 'dashboard-release-adoption',
                      viewSection: 'dashboard-release-adoption',
                    ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'TOAST TESTS',
            style: PixelText.title(size: 14, color: colors.textDark),
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
                  onPressed: () => widget.showInfoToast(
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
                  onPressed: () => widget.showErrorToast(
                    context,
                    'This is a test error toast.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'POWERUP ICONS',
            style: PixelText.title(size: 14, color: colors.textDark),
          ),
          const SizedBox(height: 12),
          for (final type in PowerupIcon.knownTypes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: PowerupIcon(
                      type: type,
                      size: 28,
                      spinning: true,
                      spinDuration: const Duration(milliseconds: 2800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PowerupCopy.nameFor(type),
                          style: PixelText.title(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        Text(
                          PowerupCopy.descriptionFor(type),
                          style: PixelText.body(
                            size: 11,
                            color: colors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'POWERUP CRATE',
            style: PixelText.title(size: 14, color: colors.textDark),
          ),
          const SizedBox(height: 16),
          const Center(child: SpinningCrate(size: 100)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DashboardRequestState {
  bool loading = false;
  bool failed = false;
  AdminMetricsEnvelope? envelope;
  Future<void>? pending;
}

class _SectionSpinner extends StatelessWidget {
  const _SectionSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
