import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../styles.dart';
import 'spotlight_overlay.dart';
import 'tutorial_mock_screens.dart';

enum TutorialMockPage { home, races, leaderboard, friends }

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

const List<TutorialStep> _steps = [
  TutorialStep(
    page: TutorialMockPage.home,
    targetKey: 'home.steps',
    title: 'Track today',
    body:
        'Bara reads steps from Apple Health and keeps your progress front and center.',
  ),
  TutorialStep(
    page: TutorialMockPage.home,
    targetKey: 'home.goal',
    title: 'Set the goal',
    body:
        'Tap Edit Goal any time. Goal progress powers streaks, rewards, and friendly races.',
  ),
  TutorialStep(
    page: TutorialMockPage.home,
    targetKey: 'home.coins',
    title: 'Earn coins',
    body:
        'Coins come from goals, races, and rewards. Spend them in the shop or race with them.',
  ),
  TutorialStep(
    page: TutorialMockPage.races,
    targetKey: 'races.card',
    title: 'Join a race',
    body:
        'Race friends over a step target. Every synced step moves your place on the board.',
  ),
  TutorialStep(
    page: TutorialMockPage.races,
    targetKey: 'races.box',
    title: 'Mystery boxes',
    body:
        'Walking during races earns boxes with powerups. Open queued boxes before extras expire.',
  ),
  TutorialStep(
    page: TutorialMockPage.leaderboard,
    targetKey: 'leaderboard.rank',
    title: 'Climb the board',
    body:
        'Compare steps and race results against your crew each week.',
  ),
  TutorialStep(
    page: TutorialMockPage.friends,
    targetKey: 'friends.search',
    title: 'Add friends',
    body:
        'Search by display name to add people. Friends unlock races and rankings.',
  ),
];

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, this.onComplete});

  /// Called when the user finishes or skips the tutorial. If null, the screen
  /// is simply popped.
  final VoidCallback? onComplete;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
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
      widget.onComplete!();
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
