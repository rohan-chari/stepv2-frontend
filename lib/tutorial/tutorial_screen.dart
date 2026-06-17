import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../styles.dart';
import 'spotlight_overlay.dart';
import 'tutorial_mock_screens.dart';

enum TutorialMockPage { home, races, ranked, leaderboard, friends }

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
      page: TutorialMockPage.races,
      targetKey: 'races.box',
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
  const TutorialScreen({super.key, this.onComplete});

  /// Called when the user finishes or skips the tutorial, with the tutorial's
  /// own (still-mounted) [BuildContext] so the callback can navigate forward.
  /// If null, the screen is simply popped (the replay path from Profile, which
  /// sits on top of the app and pops cleanly). On first run there is nothing
  /// beneath the tutorial to pop to, so the caller passes a callback that
  /// routes into the app instead.
  final void Function(BuildContext context)? onComplete;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final List<TutorialStep> _steps = _buildSteps();
  int _index = 0;
  Rect? _targetRect;
  final Map<String, GlobalKey> _keys = {};
  final GlobalKey _stageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    for (final step in _steps) {
      if (step.targetKey != null) {
        _keys.putIfAbsent(step.targetKey!, () => GlobalKey());
      }
    }
    _scheduleRectUpdate();
  }

  void _scheduleRectUpdate() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTargetRect();
    });
  }

  void _updateTargetRect() {
    final step = _steps[_index];
    if (step.targetKey == null) {
      setState(() => _targetRect = null);
      return;
    }
    final ctx = _keys[step.targetKey!]?.currentContext;
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
      _finish();
      return;
    }
    setState(() {
      _index += 1;
      _targetRect = null;
    });
    _scheduleRectUpdate();
  }

  void _back() {
    if (_index == 0) return;
    setState(() {
      _index -= 1;
      _targetRect = null;
    });
    _scheduleRectUpdate();
  }

  void _skip() {
    _finish();
  }

  void _finish() {
    if (widget.onComplete != null) {
      widget.onComplete!(context);
    } else {
      Navigator.of(context).pop();
    }
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
              child: TutorialMockHost(page: step.page, keys: _keys),
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
