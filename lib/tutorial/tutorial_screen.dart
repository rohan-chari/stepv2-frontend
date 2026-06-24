import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../styles.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import 'spotlight_overlay.dart';
import 'tutorial_preview_data.dart';
import 'tutorial_real_screens.dart';

/// One-time coins granted for finishing the tutorial. Display-only — the
/// backend is authoritative for the actual grant (and its idempotency).
const int kTutorialRewardCoins = 100;

enum TutorialMockPage { home, races, raceDetail, ranked, leaderboard, friends }

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

/// Builds the walkthrough. The health-source name is device-aware (Apple
/// Health on iOS, Health Connect on Android) so the very first line is never
/// wrong for the platform the user is actually on.
List<TutorialStep> _buildSteps() {
  final healthSource = Platform.isAndroid ? 'Health Connect' : 'Apple Health';

  return [
    TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.steps',
      title: 'Track today',
      body:
          'Bara reads your steps from $healthSource and keeps today’s '
          'progress front and center.',
    ),
    TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.milestones',
      title: 'Earn coins',
      body:
          'Walk to hit 5k, 10k, 15k and 20k steps, then tap each milestone to '
          'claim its coins. Races and the daily reward pay out too.',
    ),
    TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.shop',
      title: 'Dress up your capy',
      body:
          'Spend coins in the shop on outfits for your capybara — buy an item, '
          'then equip it from your Inventory.',
    ),
    TutorialStep(
      page: TutorialMockPage.home,
      targetKey: 'home.friends',
      title: 'Find friends',
      body:
          'Tap here to add friends and find people to race. Friends power your '
          'races and leaderboards.',
    ),
    TutorialStep(
      page: TutorialMockPage.friends,
      targetKey: 'friends.search',
      title: 'Add friends',
      body:
          'Search by display name to send a request. Once they accept, you can '
          'race and rank against each other.',
    ),
    TutorialStep(
      page: TutorialMockPage.races,
      targetKey: 'races.card',
      title: 'Join a race',
      body:
          'Race friends over a set number of days. Every synced step moves you '
          'up the board — most steps when the clock runs out wins.',
    ),
    TutorialStep(
      page: TutorialMockPage.races,
      targetKey: 'races.pot',
      title: 'Race for the pot',
      body:
          'Races can stake coins: every buy-in feeds the pot, and the winner '
          'takes it all — or the top 3 split it.',
    ),
    TutorialStep(
      page: TutorialMockPage.raceDetail,
      targetKey: 'raceDetail.powerups',
      title: 'Powerups & boxes',
      body:
          'Walking earns mystery boxes of powerups — boosts and shields, plus '
          'attacks that freeze or steal steps from rivals.',
    ),
    TutorialStep(
      page: TutorialMockPage.ranked,
      targetKey: 'ranked.tab',
      title: 'Climb the ranks',
      body:
          'Ranked drops you into a weekly cohort your size. Out-walk them to '
          'climb tiers and earn rewards.',
    ),
    TutorialStep(
      page: TutorialMockPage.leaderboard,
      targetKey: 'leaderboard.rank',
      title: 'Top the boards',
      body:
          'See how your steps and race wins stack up — switch between everyone '
          'and just your friends.',
    ),
  ];
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, this.onComplete, this.authService});

  /// Called when the user finishes or skips the tutorial, with the tutorial's
  /// own (still-mounted) [BuildContext] so the callback can navigate forward.
  /// If null, the screen is simply popped (the replay path from Profile, which
  /// sits on top of the app and pops cleanly). On first run there is nothing
  /// beneath the tutorial to pop to, so the caller passes a callback that
  /// routes into the app instead.
  final void Function(BuildContext context)? onComplete;

  /// The real auth service. When provided, finishing the *entire* tutorial
  /// (not skipping) claims the one-time 100-coin completion reward via the
  /// backend (idempotent — granted once per account ever, across the onboarding
  /// and replay paths) and shows a brief reveal. Null disables the reward (e.g.
  /// in tests or previews).
  final AuthService? authService;

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

  @override
  void initState() {
    super.initState();
    for (final step in _steps) {
      if (step.targetKey != null) {
        _keys.putIfAbsent(step.targetKey!, () => GlobalKey());
      }
    }
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

    if (completed && widget.authService != null) {
      final granted = await widget.authService!.claimTutorialReward();
      if (!mounted) return;
      if (granted) {
        await _showRewardReveal();
        if (!mounted) return;
      }
    }

    if (widget.onComplete != null) {
      widget.onComplete!(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showRewardReveal() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.parchment,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.parchmentBorder, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  'TUTORIAL COMPLETE',
                  style: HomeText.label(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '+$kTutorialRewardCoins coins',
                  style: HomeText.title(size: 30, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Nice work — your reward is in the bag. Now go earn some more!',
                  style: HomeText.body(size: 15, color: AppColors.textMid),
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

    return Scaffold(
      backgroundColor: AppColors.parchment,
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
                onSkip: _skip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
