import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/activation_analytics_service.dart';
import '../services/auth_service.dart';
import '../styles.dart';
import '../widgets/game_container.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';
import 'spotlight_overlay.dart';
import 'tutorial_preview_data.dart';
import 'tutorial_real_screens.dart';

/// One-time coins granted for finishing the tutorial. Display-only — the
/// backend is authoritative for the actual grant (and its idempotency).
const int kTutorialRewardCoins = 100;

enum TutorialMockPage { home, races, raceDetail, leaderboard, friends, profile }

class TutorialStep {
  const TutorialStep({
    required this.page,
    required this.targetKey,
    required this.title,
    required this.body,
  });

  final TutorialMockPage page;
  final String? targetKey;
  final String title;
  final String body;
}

/// Builds the walkthrough — five steps, ~15–20 seconds, four taps.
///
/// This is deliberately a *reinstatement*, not a trim. Turning the v2 flow on
/// deletes the tutorial from onboarding outright (the flow early-returns before
/// the tutorial check), so the only surviving path to it is Profile → Settings
/// → View Tutorial. V3 puts a much smaller one back in the critical path.
///
/// The ten-step version taught seventeen concepts — shop, inventory, referral
/// links, prize-pool funding, leaderboard filters — before the user had walked
/// a single step, and steps 4 and 5 were near-duplicates about finding friends.
/// What survives is the spine: walk → race → boxes → rivals → coins. Everything
/// evicted becomes a just-in-time tip fired when the user actually reaches the
/// surface (see `widgets/coach_tip.dart`).
///
/// Titles are declarative sentences, not noun phrases: "Just walk." is an
/// instruction, "Track today" was a feature name. Bodies are ≤14 words.
///
/// The health-source name stays device-aware (Apple Health on iOS, Health
/// Connect on Android) so the very first line is never wrong for the platform
/// the user is actually on. Every spotlight anchor below is already wired —
/// `races.box` in particular has existed as an anchor with no step pointing at
/// it, and step 3 finally uses it.
List<TutorialStep> _buildSteps() {
  final healthSource = Platform.isAndroid ? 'Health Connect' : 'Apple Health';

  return [
    TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.steps',
      title: 'Just walk.',
      body:
          'Bara counts your steps from $healthSource automatically. '
          'Nothing to start, nothing to log.',
    ),
    const TutorialStep(
      page: TutorialMockPage.races,
      targetKey: 'races.card',
      title: 'Race your friends.',
      body: 'Most steps when the clock runs out wins.',
    ),
    const TutorialStep(
      page: TutorialMockPage.races,
      targetKey: 'races.box',
      title: 'Grab mystery boxes.',
      body: 'Walking earns boxes full of powerups.',
    ),
    const TutorialStep(
      page: TutorialMockPage.raceDetail,
      targetKey: 'raceDetail.powerups',
      title: 'Mess with rivals.',
      body: 'Boosts and shields for you. Freezes and steals for them.',
    ),
    // Ending back on home is intentional: the tutorial finishes on the screen
    // the user is about to be dropped into.
    const TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.shop',
      title: 'Win coins.',
      body: 'Every race pays out. Spend coins on gear for your capy.',
    ),
  ];
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    this.onComplete,
    this.authService,
    this.analytics,
    this.mandatory = false,
  });

  /// Called when the user finishes or skips the tutorial, with the tutorial's
  /// own (still-mounted) [BuildContext] so the callback can navigate forward.
  /// If null, the screen is simply popped (the replay path from Profile, which
  /// sits on top of the app and pops cleanly). On first run there is nothing
  /// beneath the tutorial to pop to, so the caller passes a callback that
  /// routes into the app instead.
  ///
  /// [completed] is true only when the user reached the end — a skip, and a
  /// back gesture outside mandatory mode, report false. Batch 2026-08-09 item
  /// 9 needs that distinction to decide whether the onboarding step may be
  /// marked seen; it used to be inferred by the caller from the fact that the
  /// skip controls were hidden, which was correct but only by argument.
  final void Function(BuildContext context, bool completed)? onComplete;

  /// The real auth service. When provided, finishing the *entire* tutorial
  /// (not skipping) claims the one-time 100-coin completion reward via the
  /// backend (idempotent — granted once per account ever, across the onboarding
  /// and replay paths) and shows a brief reveal. Null disables the reward (e.g.
  /// in tests or previews).
  final AuthService? authService;

  /// Activation telemetry sink. Defaults to a real service; injectable so the
  /// tutorial's own funnel events are assertable.
  final ActivationAnalyticsService? analytics;

  /// Batch 2026-08-09 item 9 — mandatory onboarding mode.
  ///
  /// Hides the SKIP pill and makes the back gesture inert. Defaults FALSE, and
  /// the Settings replay call site deliberately never sets it: a replay user
  /// whose spotlight anchor fails to mount would otherwise have no exit at all
  /// (ui-test-planner risk R2). Only the onboarding host passes true, and only
  /// when the backend flag is on and the local circuit breaker has not tripped.
  final bool mandatory;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final List<TutorialStep> _steps = _buildSteps();
  int _index = 0;
  int _epoch = 0;
  Rect? _targetRect;
  final Map<String, GlobalKey> _keys = {};
  final GlobalKey _stageKey = GlobalKey();
  late final TutorialPreviewAuthService _authService =
      TutorialPreviewAuthService();
  late final TutorialPreviewBackendApiService _api =
      TutorialPreviewBackendApiService();

  late final ActivationAnalyticsService _analytics =
      widget.analytics ?? ActivationAnalyticsService();

  @override
  void initState() {
    super.initState();
    for (final step in _steps) {
      if (step.targetKey != null) {
        _keys.putIfAbsent(step.targetKey!, () => GlobalKey());
      }
    }
    unawaited(_analytics.record('tutorial_opened'));
    _settleTarget(_epoch);
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }

  /// The real screens load their seeded data asynchronously and are taller than
  /// the viewport, so a spotlight target may not exist (or may be off-screen)
  /// for a few frames after a step change. Poll until the target mounts, scroll
  /// it into view, then measure. [epoch] is bumped on every step change so a
  /// stale settle loop from the previous step bails out.
  Future<void> _settleTarget(int epoch) async {
    final targetKey = _steps[_index].targetKey;
    if (targetKey == null) {
      if (mounted) setState(() => _targetRect = null);
      return;
    }
    for (var attempt = 0; attempt < 40; attempt++) {
      if (!mounted || epoch != _epoch) return;
      final ctx = _keys[targetKey]?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.42,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        } catch (_) {}
        if (!mounted || epoch != _epoch) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || epoch != _epoch) return;
        _updateTargetRect();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
    if (mounted && epoch == _epoch) _updateTargetRect();
  }

  void _updateTargetRect() {
    final step = _steps[_index];
    final ctx = step.targetKey == null
        ? null
        : _keys[step.targetKey!]?.currentContext;
    final stageCtx = _stageKey.currentContext;
    if (ctx == null || stageCtx == null) {
      setState(() => _targetRect = null);
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    final stageBox = stageCtx.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.attached ||
        stageBox == null ||
        !stageBox.attached) {
      setState(() => _targetRect = null);
      return;
    }
    final offset = box.localToGlobal(Offset.zero, ancestor: stageBox);
    setState(() => _targetRect = offset & box.size);
  }

  void _next() {
    if (_index == _steps.length - 1) {
      _finish(completed: true);
      return;
    }
    setState(() {
      _index += 1;
      _targetRect = null;
    });
    _epoch++;
    _settleTarget(_epoch);
  }

  void _back() {
    if (_index == 0) return;
    setState(() {
      _index -= 1;
      _targetRect = null;
    });
    _epoch++;
    _settleTarget(_epoch);
  }

  void _skip() {
    // Skipping is not completion — no reward. The onboarding step still marks
    // itself seen when this route returns, and the user can earn the reward
    // later by finishing a replay.
    _finish(completed: false);
  }

  bool _finishing = false;

  /// Closes the tutorial. When [completed] (the user reached the end rather than
  /// skipping) and a real [AuthService] is wired in, claims the one-time reward
  /// first and shows a reveal if coins were actually granted.
  Future<void> _finish({required bool completed}) async {
    if (_finishing) return;
    _finishing = true;

    // Per-step drop-off: a skip reports the 1-indexed step the user was on when
    // they bailed, which turns into the histogram that says whether five steps
    // is still too many. Completion carries no step — it is by definition the
    // last one. Best-effort and never awaited: the queue is bounded and
    // offline-tolerant, so a telemetry failure can neither surface to the user
    // nor hold up onboarding.
    unawaited(
      _analytics.record(
        completed ? 'tutorial_completed' : 'tutorial_skipped',
        context: completed
            ? const {'source': 'onboarding'}
            : {'source': 'onboarding', 'step': '${_index + 1}'},
      ),
    );

    if (completed && widget.authService != null) {
      final granted = await widget.authService!.claimTutorialReward();
      if (!mounted) return;
      if (granted) {
        await _showRewardReveal();
        if (!mounted) return;
      }
    }

    if (widget.onComplete != null) {
      widget.onComplete!(context, completed);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showRewardReveal() {
    // Framed GameContainer reveal, matching the daily-reward / attack-outcome
    // modal family (accent frame, parchment surface, coin-gold glow). No
    // emoji — the SpinningCoin is the hero, like every other coin reveal.
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: GameContainer(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            frameColor: AppColors.of(context).accent,
            surfaceColor: AppColors.of(context).parchmentLight,
            glowColor: AppColors.of(context).coinMid,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpinningCoin(size: 44),
                const SizedBox(height: 12),
                Text(
                  'TUTORIAL COMPLETE',
                  style: PixelText.title(
                    size: 13,
                    color: AppColors.of(context).textMid,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '+$kTutorialRewardCoins coins',
                  style: PixelText.title(
                    size: 30,
                    color: AppColors.of(context).textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Nice work. Your reward is in the bag. Now go earn some more!',
                  style: PixelText.body(
                    size: 15,
                    color: AppColors.of(context).textMid,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                PillButton(
                  label: 'LET’S GO',
                  fullWidth: true,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];

    // The abandonment hole: with no PopScope an OS back-swipe popped the route
    // without ever calling _finish — no reward, no analytics — while the
    // onboarding host marked the step seen anyway on the await return. That was
    // tolerable when the tutorial was optional. It gates the app under v3, so a
    // back-gesture now routes through exactly the same path as SKIP.
    // The tutorial is part of the onboarding brand moment, so it pins to the
    // light palette like StartScreen and OnboardingScene — the spotlighted
    // host page underneath renders in day colors regardless of device theme.
    return Theme(
      data: AppThemeData.light(),
      child: Builder(builder: (context) => _buildTutorial(context, step)),
    );
  }

  Widget _buildTutorial(BuildContext context, TutorialStep step) {
    return PopScope(
      key: const Key('tutorial-pop-scope'),
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Item 9: back stops being the skip affordance under mandatory mode.
        // canPop is already false, so this is simply a no-op — the route does
        // not pop and onboarding is not marked complete.
        if (widget.mandatory) return;
        _skip();
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).parchment,
        body: SafeArea(
          child: Stack(
            key: _stageKey,
            children: [
              Positioned.fill(
                child: TutorialRealHost(
                  page: step.page,
                  keys: _keys,
                  authService: _authService,
                  api: _api,
                ),
              ),
              Positioned.fill(
                child: SpotlightOverlay(
                  targetRect: _targetRect,
                  title: step.title,
                  body: step.body,
                  stepIndex: _index,
                  stepCount: _steps.length,
                  onNext: _next,
                  onBack: _index == 0 ? null : _back,
                  // Null removes the pill; the replay path keeps it.
                  onSkip: widget.mandatory ? null : _skip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
