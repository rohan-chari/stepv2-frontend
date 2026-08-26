import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/daily_reward_screen.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/activation_analytics_service.dart';
import '../styles.dart';
import 'extra_spin_reward_ticket.dart';
import 'pill_button.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Full-width daily-reward button shown inside the home hero. Fed by the home
/// race-card batch via [initialData] (so it renders with the rest of the
/// page); self-fetches the daily-reward status only as a fallback for old
/// backends. Pulses gently while unclaimed and opens [DailyRewardScreen] on
/// tap. Public [refresh] lets the parent (pull-to-refresh) re-sync.
class StreakChip extends StatefulWidget {
  const StreakChip({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.compact = false,
    this.initialData,
    this.awaitingBatch = false,
    this.onClaimedToday,
    this.adController,
    this.analytics,
  });

  /// Test seam for the rewarded-ad extra spin; defaults to a real [AdService]
  /// owned by the chip.
  final ExtraSpinAdController? adController;

  /// Shared with the destination sheet so Home and Daily Reward write to the
  /// same bounded best-effort analytics queue.
  final ActivationAnalyticsService? analytics;

  final AuthService authService;
  final BackendApiService backendApiService;
  final bool compact;

  /// Daily-reward payload from the home race-card batch (`dailyReward`:
  /// `{claimedToday, localDate}`). When present and fresh, no extra request
  /// is made — the button renders in the same frame as the rest of home.
  final Map<String, dynamic>? initialData;

  /// True while the home batch is still in flight. Holds off the fallback
  /// self-fetch; it runs only if the batch lands without the field (old
  /// backend) or fails.
  final bool awaitingBatch;

  /// Called when the user claims today's reward, so the parent can patch its
  /// cached batch payload and a later remount doesn't show a stale CLAIM.
  final VoidCallback? onClaimedToday;

  @override
  State<StreakChip> createState() => StreakChipState();
}

class StreakChipState extends State<StreakChip> with WidgetsBindingObserver {
  Future<void> refresh() => _refresh();

  bool _unclaimed = false;
  bool _opening = false;
  bool _loaded = false;
  String _lastFetchedDate = '';
  // Rewarded-ad extra spin is live for today (claimed the free box, extra not
  // yet used). Drives the EXTRA SPIN button state. Fed by the batch payload's
  // dailyReward.adExtraSpin (new backends) or the standalone status fetch.
  bool _extraSpinAvailable = false;
  bool _extraSpinPendingGrant = false;
  // One ad controller per chip lifetime so a preloaded rewarded ad survives
  // reopening the daily-reward screen. Constructing it touches no platform
  // channels; ads only load once the screen sees a live offer.
  late final ExtraSpinAdController _adController =
      widget.adController ?? AdService();
  late final ActivationAnalyticsService _analytics =
      widget.analytics ?? ActivationAnalyticsService();
  bool _ticketOfferShown = false;
  bool _ticketAdPreparationStarted = false;
  RewardedAdContext? _ticketAdContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthChanged);
    _consumeBatchOrFetch();
  }

  @override
  void didUpdateWidget(covariant StreakChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Batch landed (or its payload changed): consume it, or fall back to the
    // standalone fetch when the batch came back without the field.
    if (!identical(oldWidget.initialData, widget.initialData) ||
        (oldWidget.awaitingBatch && !widget.awaitingBatch)) {
      _consumeBatchOrFetch();
    }
  }

  void _consumeBatchOrFetch() {
    final data = widget.initialData;
    final today = _todayLocalDate();
    // Only trust a batch payload computed for today's local date — a cached
    // batch from before midnight would resurrect yesterday's claim state.
    if (data != null && data['localDate'] == today) {
      final wasAvailable = _extraSpinAvailable;
      final extra = _extraSpinBlock(data);
      final available = _extraSpinFrom(data);
      setState(() {
        _unclaimed = data['claimedToday'] != true;
        _extraSpinAvailable = available;
        _extraSpinPendingGrant = extra?['pendingGrant'] == true;
        _loaded = true;
        _lastFetchedDate = today;
      });
      _recordTicketShownIfNew(wasAvailable: wasAvailable, available: available);
      _maybePreloadTicketAd(
        available,
        pendingGrant: extra?['pendingGrant'] == true,
      );
    } else if (!widget.awaitingBatch) {
      // Old backend (no embedded dailyReward), stale batch, or batch failure:
      // standalone fetch, same as before the batching change.
      _refresh();
    }
    // else: batch still in flight — didUpdateWidget consumes it when it lands.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authService.removeListener(_handleAuthChanged);
    // Only dispose a controller the chip created; an injected one is owned by
    // the caller.
    if (widget.adController == null) _adController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastFetchedDate != _todayLocalDate()) {
        final previous = _ticketAdContext;
        if (previous != null) _adController.disposeContext(previous);
        _ticketAdContext = null;
        _ticketAdPreparationStarted = false;
        _refresh();
      } else {
        _ticketAdPreparationStarted = false;
        _maybePreloadTicketAd(
          _extraSpinAvailable,
          pendingGrant: _extraSpinPendingGrant,
        );
      }
    }
  }

  void _handleAuthChanged() {
    final previous = _ticketAdContext;
    final userId = widget.authService.userId;
    if (previous != null && previous.userId != userId) {
      _adController.disposeContext(previous);
      _ticketAdContext = null;
      _ticketAdPreparationStarted = false;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final localDate = _todayLocalDate();
    try {
      final res = await widget.backendApiService.fetchDailyRewardStatus(
        identityToken: token,
        localDate: localDate,
      );
      if (!mounted ||
          widget.authService.authToken != token ||
          widget.authService.userId != userId) {
        return;
      }
      final wasAvailable = _extraSpinAvailable;
      final extra = _extraSpinBlock(res);
      final available = _extraSpinFrom(res);
      setState(() {
        _unclaimed = res['claimedToday'] != true;
        _extraSpinAvailable = available;
        _extraSpinPendingGrant = extra?['pendingGrant'] == true;
        _loaded = true;
        _lastFetchedDate = localDate;
      });
      _recordTicketShownIfNew(wasAvailable: wasAvailable, available: available);
      _maybePreloadTicketAd(
        available,
        pendingGrant: extra?['pendingGrant'] == true,
      );
    } catch (_) {
      if (mounted &&
          widget.authService.authToken == token &&
          widget.authService.userId == userId) {
        setState(() => _loaded = true);
      }
    }
  }

  /// True when today's box is claimed and a rewarded-ad extra spin is still
  /// on the table (either watch-an-ad or a verified-but-unredeemed grant).
  /// Reads the additive `adExtraSpin` block defensively — absent on old
  /// backends and before the free claim.
  bool _extraSpinFrom(Map<String, dynamic> payload) {
    if (payload['claimedToday'] != true) return false;
    if (!_adController.isSupported) return false;
    final extra = _extraSpinBlock(payload);
    if (extra == null) return false;
    if (extra['used'] == true) return false;
    return extra['available'] == true || extra['pendingGrant'] == true;
  }

  Map<String, dynamic>? _extraSpinBlock(Map<String, dynamic> payload) {
    final extra = payload['adExtraSpin'];
    return extra is Map<String, dynamic> ? extra : null;
  }

  void _recordTicketShownIfNew({
    required bool wasAvailable,
    required bool available,
  }) {
    if (!wasAvailable && available && !_ticketOfferShown) {
      _ticketOfferShown = true;
      unawaited(
        _analytics.record(
          'extra_spin_offer_shown',
          context: const {'surface': 'home'},
        ),
      );
    }
  }

  /// Warm the extra-spin controller while the ticket is visible. The sheet
  /// borrows this same controller, so a ready ad survives navigation. A
  /// failed preload is retried by the sheet, which owns the user-visible
  /// loading state and its associated readiness telemetry.
  void _maybePreloadTicketAd(bool available, {required bool pendingGrant}) {
    if (!available ||
        pendingGrant ||
        _ticketAdPreparationStarted ||
        !_adController.isSupported) {
      return;
    }
    final userId = widget.authService.userId;
    if (userId == null || userId.isEmpty) return;
    final context = RewardedAdContext.extraSpin(
      userId: userId,
      localDate: _todayLocalDate(),
    );
    final previous = _ticketAdContext;
    if (previous != null && previous != context) {
      _adController.disposeContext(previous);
    }
    _ticketAdContext = context;
    _ticketAdPreparationStarted = true;
    unawaited(() async {
      if (!_adController.isReadyFor(context)) {
        await _adController.warm(context);
      }
      if (mounted && !_adController.isReadyFor(context)) {
        _ticketAdPreparationStarted = false;
      }
    }());
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final claimed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => DailyRewardScreen(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
          adController: _adController,
          analytics: _analytics,
          analyticsSurface: 'home',
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    if (claimed == true && mounted) {
      setState(() => _unclaimed = false);
      widget.onClaimedToday?.call();
    }
    if (mounted) setState(() => _opening = false);
    // Always re-fetch: a claim just changed today's state (the extra-spin
    // offer appears right after the free claim and disappears once used),
    // and a dismissed sheet may still have consumed the extra spin.
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(height: 48);
    }
    // The Home affordance is deliberately one stable destination. A changing
    // CLAIM/EXTRA SPIN label made the same tap target feel like two unrelated
    // systems; availability is communicated by the icon and attention beat.
    if (_extraSpinAvailable) {
      void openExtraSpin() {
        unawaited(
          _analytics.record(
            'extra_spin_cta_tapped',
            context: const {'surface': 'home'},
          ),
        );
        _open();
      }

      if (widget.compact) {
        return _DailyRewardAttention(
          active: !_opening,
          child: _CompactDailyRewardButton(
            label: 'DAILY REWARD',
            semanticsLabel: 'Daily reward. One more spin is ready.',
            icon: Icons.card_giftcard_rounded,
            onPressed: openExtraSpin,
          ),
        );
      }
      return ExtraSpinRewardTicket(
        label: 'DAILY REWARD',
        semanticsLabel: 'Daily reward. One more spin is ready.',
        onPressed: openExtraSpin,
      );
    }
    if (widget.compact) {
      return _DailyRewardAttention(
        active: _unclaimed && !_opening,
        child: _CompactDailyRewardButton(
          label: _unclaimed ? 'CLAIM REWARD' : 'DAILY REWARD',
          semanticsLabel: _unclaimed
              ? 'Claim daily reward'
              : 'Open daily reward',
          icon: _unclaimed
              ? Icons.card_giftcard_rounded
              : Icons.check_box_rounded,
          onPressed: _open,
        ),
      );
    }
    return _DailyRewardAttention(
      active: _unclaimed && !_opening,
      child: PillButton(
        label: _unclaimed ? 'CLAIM REWARD' : 'DAILY REWARD',
        icon: _unclaimed
            ? Icons.card_giftcard_rounded
            : Icons.check_box_rounded,
        variant: PillButtonVariant.secondary,
        fullWidth: true,
        onPressed: _open,
      ),
    );
  }
}

/// Home's wide quick action uses the same icon-over-label rhythm as the two
/// square destinations beside it. Non-compact StreakChip callers keep their
/// existing PillButton / ticket composition.
class _CompactDailyRewardButton extends StatelessWidget {
  const _CompactDailyRewardButton({
    required this.label,
    required this.semanticsLabel,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            key: const Key('home-daily-reward-compact-layout'),
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: colors.pillGold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.pillGoldDark, width: 2),
              boxShadow: [
                BoxShadow(
                  color: colors.pillGoldDark.withValues(alpha: 0.24),
                  offset: const Offset(3, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: colors.textDark),
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: PixelText.pill(size: 14, color: colors.textDark),
                    ),
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

/// A deliberately tiny, bounded beat for an actionable Home reward. The
/// first 700ms contains two one-pixel nudges; the rest of the seven-second
/// loop is static. Reduced-motion users get a fixed higher-contrast outline.
class _DailyRewardAttention extends StatefulWidget {
  const _DailyRewardAttention({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_DailyRewardAttention> createState() => _DailyRewardAttentionState();
}

class _DailyRewardAttentionState extends State<_DailyRewardAttention>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  bool _foregrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foregrounded = state == AppLifecycleState.resumed;
    if (mounted) _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _DailyRewardAttention oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncMotion();
  }

  void _syncMotion() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!widget.active || reduced || !_foregrounded) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!widget.active || reduced) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: reduced && widget.active
              ? Border.all(color: AppColors.of(context).coinDark, width: 2)
              : null,
        ),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Two restrained beats, then a long quiet interval.
        final offset = t < .025
            ? 1.0
            : t < .05
            ? -1.0
            : t < .075
            ? .7
            : t < .10
            ? -.7
            : 0.0;
        final pulse = t < .10 ? .16 * (1 - (t / .10)) : 0.0;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: AppColors.of(context).coinMid.withValues(alpha: pulse),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}
