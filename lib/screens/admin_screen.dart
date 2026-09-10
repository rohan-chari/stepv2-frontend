import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart' as error_toast;
import '../widgets/info_toast.dart' as info_toast;
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import 'admin_accessory_tuner_screen.dart';
import 'admin_sections.dart';
import 'admin_dashboard_controller.dart';
import 'admin_dashboard_overview.dart';
import 'admin_dashboard_detail.dart';
import '../widgets/admin_metric_widgets.dart';
import '../services/ad_service.dart';
import 'admin_balance_config_screen.dart';
import 'admin_giveaway_screen.dart';
import 'admin_powerup_shop_screen.dart';

/// Batch 2026-08-09 item 10: no longer draws its own board or SETTINGS title —
/// it is the body of the hub's CONFIG section now. Product rollout switches
/// have graduated; CONFIG retains only the operational Home service banner.
class AdminFlagsPanel extends StatefulWidget {
  const AdminFlagsPanel({
    super.key,
    required this.authService,
    required this.showErrorToast,
    this.showInfoToast,
    this.backendApiService,
  });

  final AuthService authService;
  final void Function(BuildContext context, String message) showErrorToast;
  final void Function(BuildContext context, String message)? showInfoToast;
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
  bool _bannerAdsEnabled = true;
  final TextEditingController _serviceBannerMessage = TextEditingController();
  final TextEditingController _serviceBannerContestSlug =
      TextEditingController();
  bool _serviceBannerEnabled = false;
  final TextEditingController _activeLimitController = TextEditingController();
  bool _activeLimitLoading = true;
  bool _activeLimitSaving = false;
  bool _activeLimitUnavailable = false;
  bool _activeLimitFailed = false;
  int? _activeLimit;
  int _activeLimitMinimum = 1;
  int _activeLimitMaximum = 20;

  @override
  void initState() {
    super.initState();
    _load();
    _loadActiveLimit();
  }

  Future<void> _loadActiveLimit() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _activeLimitLoading = false;
          _activeLimitFailed = true;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _activeLimitLoading = true;
        _activeLimitFailed = false;
      });
    }
    try {
      final response = await _api.fetchAdminActiveCompetitionLimit(
        identityToken: token,
      );
      final limit = response['activeCompetitionLimit'];
      final minimum = response['minimum'];
      final maximum = response['maximum'];
      if (limit is! int ||
          minimum is! int ||
          maximum is! int ||
          minimum != 1 ||
          maximum != 20 ||
          limit < minimum ||
          limit > maximum) {
        throw const ApiException('Invalid active competition limit response');
      }
      if (!mounted) return;
      setState(() {
        _activeLimit = limit;
        _activeLimitMinimum = minimum;
        _activeLimitMaximum = maximum;
        _activeLimitController.text = '$limit';
        _activeLimitLoading = false;
        _activeLimitUnavailable = false;
        _activeLimitFailed = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _activeLimitLoading = false;
        _activeLimitUnavailable = error.statusCode == 404;
        _activeLimitFailed = error.statusCode != 404;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeLimitLoading = false;
        _activeLimitFailed = true;
      });
    }
  }

  int? get _enteredActiveLimit {
    final parsed = int.tryParse(_activeLimitController.text.trim());
    if (parsed == null ||
        parsed < _activeLimitMinimum ||
        parsed > _activeLimitMaximum) {
      return null;
    }
    return parsed;
  }

  Future<void> _saveActiveLimit() async {
    final token = widget.authService.authToken;
    final next = _enteredActiveLimit;
    if (token == null ||
        token.isEmpty ||
        next == null ||
        next == _activeLimit ||
        _activeLimitSaving) {
      return;
    }
    setState(() => _activeLimitSaving = true);
    try {
      final response = await _api.updateAdminActiveCompetitionLimit(
        identityToken: token,
        activeCompetitionLimit: next,
      );
      final returned = response['activeCompetitionLimit'];
      final minimum = response['minimum'];
      final maximum = response['maximum'];
      if (returned is! int ||
          minimum is! int ||
          maximum is! int ||
          minimum != 1 ||
          maximum != 20 ||
          returned < minimum ||
          returned > maximum) {
        throw const ApiException('Invalid active competition limit response');
      }
      if (!mounted) return;
      setState(() {
        _activeLimit = returned;
        _activeLimitController.text = '$returned';
      });
      widget.showInfoToast?.call(context, 'Active race limit saved.');
    } catch (_) {
      if (mounted) {
        widget.showErrorToast(context, 'Couldn’t save the active race limit.');
      }
    } finally {
      if (mounted) setState(() => _activeLimitSaving = false);
    }
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null) return;
    try {
      final settings = await _api.fetchAdminSettings(identityToken: token);
      if (mounted) {
        setState(() {
          _settings = settings;
          _bannerAdsEnabled = settings['bannerAdsEnabled'] is bool
              ? settings['bannerAdsEnabled'] as bool
              : true;
          _serviceBannerEnabled = settings['homeServiceBannerEnabled'] == true;
          final message = settings['homeServiceBannerMessage'];
          _serviceBannerMessage.text = message is String ? message : '';
          final contestSlug = settings['homeServiceBannerContestSlug'];
          _serviceBannerContestSlug.text = contestSlug is String
              ? contestSlug
              : '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveBannerAds(bool enabled) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty || _saving) return;
    final previous = _bannerAdsEnabled;
    setState(() {
      _bannerAdsEnabled = enabled;
      _saving = true;
    });
    try {
      final updated = await _api.updateAdminSettings(
        identityToken: token,
        bannerAdsEnabled: enabled,
      );
      final returned = updated['bannerAdsEnabled'];
      if (returned is! bool) {
        throw const ApiException('Invalid settings response');
      }
      AdService.setBannerAdsEnabled(returned);
      if (mounted) setState(() => _bannerAdsEnabled = returned);
    } catch (_) {
      if (mounted) {
        setState(() => _bannerAdsEnabled = previous);
        AdService.setBannerAdsEnabled(previous);
        widget.showErrorToast(context, 'Couldn\'t save banner ads.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _activeLimitController.dispose();
    _serviceBannerMessage.dispose();
    _serviceBannerContestSlug.dispose();
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
        contestSlug: _serviceBannerEnabled
            ? _serviceBannerContestSlug.text.trim()
            : '',
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
          final returnedSlug = updated['homeServiceBannerContestSlug'];
          _serviceBannerContestSlug.text = returnedSlug is String
              ? returnedSlug
              : '';
        });
      }
    } catch (_) {
      if (mounted) widget.showErrorToast(context, 'Couldn\'t save the banner.');
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
        style: AdminSans.body(size: 12, color: AppColors.of(context).textMid),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActiveLimitCard(context),
        const SizedBox(height: 18),
        Text(
          'ADVERTISING',
          style: AdminSans.title(
            size: 13,
            color: AppColors.of(context).textDark,
          ),
        ),
        SwitchListTile.adaptive(
          key: const Key('admin-banner-ads-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Banner ads'),
          subtitle: const Text('Remote control for display banner placements.'),
          value: _bannerAdsEnabled,
          onChanged: _saving ? null : _saveBannerAds,
        ),
        const SizedBox(height: 14),
        Text(
          'HOME SERVICE BANNER',
          style: AdminSans.title(
            size: 13,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Persistent plain-text status notice on Home.',
          style: AdminSans.body(size: 11, color: AppColors.of(context).textMid),
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
        TextField(
          key: const Key('admin-home-service-banner-contest-slug'),
          controller: _serviceBannerContestSlug,
          enabled: !_saving,
          maxLength: 120,
          decoration: const InputDecoration(
            hintText: 'Optional published contest slug',
            helperText:
                'Leave blank for an ordinary notice. A contest slug adds the typed in-app action.',
          ),
        ),
        PillButton(
          label: _saving ? 'SAVING…' : 'SAVE SERVICE BANNER',
          fullWidth: true,
          onPressed: _saving ? null : _saveHomeServiceBanner,
        ),
      ],
    );
  }

  Widget _buildActiveLimitCard(BuildContext context) {
    final colors = AppColors.of(context);
    if (_activeLimitLoading) {
      return const SizedBox(
        height: 52,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Container(
      key: const Key('admin-active-race-limit-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.parchmentLight,
        border: Border.all(color: colors.parchmentBorder, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: colors.woodShadow, offset: const Offset(0, 3)),
        ],
      ),
      child: _activeLimitUnavailable
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE RACE LIMIT',
                  style: AdminSans.title(size: 13, color: colors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Update backend to edit',
                  style: AdminSans.body(size: 12, color: colors.textMid),
                ),
              ],
            )
          : _activeLimitFailed
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'Couldn’t load the active race limit.',
                    style: AdminSans.body(size: 12, color: colors.textMid),
                  ),
                ),
                TextButton(
                  onPressed: _loadActiveLimit,
                  child: const Text('RETRY'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ACTIVE RACE LIMIT',
                  style: AdminSans.title(size: 13, color: colors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accepted pending or active competitions per runner ($_activeLimitMinimum–$_activeLimitMaximum).',
                  style: AdminSans.body(size: 11, color: colors.textMid),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('admin-active-race-limit-field'),
                  controller: _activeLimitController,
                  enabled: !_activeLimitSaving,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Active races'),
                ),
                const SizedBox(height: 10),
                PillButton(
                  key: const Key('admin-active-race-limit-save'),
                  label: _activeLimitSaving ? 'SAVING…' : 'SAVE LIMIT',
                  fullWidth: true,
                  onPressed:
                      !_activeLimitSaving &&
                          _enteredActiveLimit != null &&
                          _enteredActiveLimit != _activeLimit
                      ? _saveActiveLimit
                      : null,
                ),
              ],
            ),
    );
  }
}

/// Compatibility shell retained for tests and downstream forks. Product
/// rollout settings are no longer mutable in the app, so it intentionally
/// renders no controls.
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

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    key: const Key('admin-settings-banner-ads-toggle'),
    contentPadding: EdgeInsets.zero,
    title: const Text('Banner ads'),
    subtitle: const Text('Remote control for display banner placements.'),
    value: settings['bannerAdsEnabled'] is bool
        ? settings['bannerAdsEnabled'] as bool
        : true,
    onChanged: saving ? null : (value) => onChanged('bannerAdsEnabled', value),
  );
}

/// Shared iOS/Android admin overview. The testing platform parameter remains
/// source-compatible; both platforms use the same scoped metrics contract.
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
  late final AdminDashboardController _dashboard = AdminDashboardController(
    _api,
    widget.authService,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_dashboard.loadAll(adminOverviewSections));
  }

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  Future<void> _openDetail(String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AdminDashboardDetail(title: title, controller: _dashboard),
      ),
    );
    if (!mounted) return;
    // A detail may have changed the shared range. Only fill missing overview
    // dependencies when returning; cached Today and 7-day sources are reused.
    unawaited(_dashboard.loadAll(adminOverviewSections));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _dashboard,
    builder: (context, _) => AdminPage(
      title: 'Admin',
      onRefresh: () => _dashboard.loadAll(adminOverviewSections, refresh: true),
      actions: [
        TextButton.icon(
          onPressed: _openTools,
          icon: const Icon(Icons.tune, size: 18),
          label: Text(
            'Tools',
            style: adminText(context, size: 13, strong: true),
          ),
        ),
        IconButton(
          key: const Key('admin-screen-refresh'),
          tooltip: 'Refresh overview',
          icon: const Icon(Icons.refresh, size: 21),
          onPressed:
              adminOverviewSections.any(
                (section) => _dashboard.state(section).loading,
              )
              ? null
              : () => _dashboard.loadAll(adminOverviewSections, refresh: true),
        ),
      ],
      child: AdminDashboardOverview(
        controller: _dashboard,
        onOpen: _openDetail,
      ),
    ),
  );

  void _openTools() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          final width = MediaQuery.sizeOf(context).width - 40;
          return AdminPage(
            title: 'Tools',
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Configuration, messages and diagnostics',
                  style: adminText(context, size: 13, muted: true),
                ),
                const SizedBox(height: 16),
                _buildMetricsConfig(width),
                const SizedBox(height: 12),
                _AdminToolGroup(
                  title: 'INBOX',
                  width: width,
                  child: AdminInboxBody(
                    authService: widget.authService,
                    backendApiService: widget.backendApiService,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMetricsDebug(width, AppColors.of(context)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsConfig(double boardWidth) => _AdminToolGroup(
    title: 'CONFIG',
    width: boardWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminFlagsPanel(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
          showErrorToast: widget.showErrorToast,
          showInfoToast: widget.showInfoToast,
        ),
        const SizedBox(height: 16),
        for (final item in [
          (
            label: 'GIVEAWAY DASHBOARD',
            builder: (BuildContext context) => AdminGiveawayScreen(
              authService: widget.authService,
              backendApiService: _api,
            ),
          ),
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
    return _AdminToolGroup(
      title: 'DEBUG',
      width: boardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOAST TESTS',
            style: AdminSans.title(size: 14, color: colors.textDark),
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
            style: AdminSans.title(size: 14, color: colors.textDark),
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
                          style: AdminSans.title(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        Text(
                          PowerupCopy.descriptionFor(type),
                          style: AdminSans.body(
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
            style: AdminSans.title(size: 14, color: colors.textDark),
          ),
          const SizedBox(height: 16),
          const Center(child: SpinningCrate(size: 100)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Mount operational children only when opened, preserving lazy inbox/config
/// requests without restoring the old analytics accordion on the overview.
class _AdminToolGroup extends StatefulWidget {
  const _AdminToolGroup({
    required this.title,
    required this.width,
    required this.child,
  });
  final String title;
  final double width;
  final Widget child;
  @override
  State<_AdminToolGroup> createState() => _AdminToolGroupState();
}

class _AdminToolGroupState extends State<_AdminToolGroup> {
  bool _opened = false;
  @override
  Widget build(BuildContext context) => AdminCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text(switch (widget.title) {
          'CONFIG' => 'Configuration',
          'INBOX' => 'Inbox',
          _ => 'Debugging',
        }, style: adminText(context, size: 17, strong: true)),
        onExpansionChanged: (open) {
          if (open && !_opened) setState(() => _opened = true);
        },
        maintainState: true,
        children: [if (_opened) widget.child],
      ),
    ),
  );
}
