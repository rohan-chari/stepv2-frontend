import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../screens/race_detail_screen.dart';
import '../services/activation_analytics_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/attack_outcome_modal.dart';
import '../widgets/celebration_confetti.dart';
import '../widgets/game_container.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';
import 'demo_auth_service.dart';
import 'demo_race_api_service.dart';
import 'demo_race_engine.dart';
import 'demo_race_script.dart';

/// The onboarding demo race (spec §5.1, §5.7b, §8.5).
///
/// This is **not a new screen**. It is the real [RaceDetailScreen] in
/// `demoMode`, fed by [DemoRaceApiService], with a coach docked at the bottom
/// and a win card at the end.
///
/// The coach deliberately does **not** dim or swallow anything: the user has to
/// be able to tap the thing it points at, so it marks the target with a ring
/// drawn behind an [IgnorePointer] and speaks from a post at the bottom edge.
/// Everything else on the real screen stays live, which is why beats are
/// derived from engine *state* rather than from a tap sequence.
class DemoRaceHost extends StatefulWidget {
  const DemoRaceHost({
    super.key,
    required this.authService,
    required this.onDone,
    this.backendApiService,
    this.engine,
    this.analytics,
    this.onRealBoxOpened,
  });

  /// The user's REAL auth service. Reads flow through it (id, name, coins);
  /// the race screen sees a [DemoAuthService] wrapper whose writes are no-ops.
  final AuthService authService;

  /// Called once, with `true` when the user finished the demo and `false` when
  /// they skipped or backed out. The onboarding step is marked seen by the
  /// launcher on return either way (F8), so this never has to.
  final void Function(bool completed) onDone;

  /// A REAL api service, used for activation telemetry only. Events must not
  /// ride the demo service — they would carry a fabricated raceId (§5.6).
  final BackendApiService? backendApiService;

  /// Injectable for tests. The demo owns its engine otherwise.
  final DemoRaceEngine? engine;

  final ActivationAnalyticsService? analytics;

  /// The real app's first-mystery-box notification trigger.
  ///
  /// Accepted here and **deliberately never forwarded** to [RaceDetailScreen].
  /// The relocated notification ask fires on the user's first REAL box; a demo
  /// box must not burn it (G3), and the prompt must never fire over a fake
  /// race. Taking the callback and dropping it makes that invariant explicit
  /// — and testable.
  final Future<void> Function()? onRealBoxOpened;

  @override
  State<DemoRaceHost> createState() => _DemoRaceHostState();
}

class _DemoRaceHostState extends State<DemoRaceHost>
    with SingleTickerProviderStateMixin {
  late final DemoRaceEngine _engine;
  late final DemoAuthService _demoAuth;
  late final DemoRaceApiService _demoApi;
  late final ActivationAnalyticsService _analytics;

  final GlobalKey _stageKey = GlobalKey();
  final GlobalKey _powerupsKey = GlobalKey();
  final GlobalKey _clockKey = GlobalKey();

  Rect? _anchorRect;
  late final AnimationController _nudge;
  DemoBeat? _lastBeat;
  Timer? _attackTimer;
  Timer? _finishTimer;
  bool _finalCountdownStarted = false;
  bool _blockedModalShown = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _engine =
        widget.engine ??
        DemoRaceEngine(
          myUserId: widget.authService.userId ?? 'demo-you',
          myDisplayName: widget.authService.displayName ?? 'You',
        );
    _engine.onChanged = _onEngineChanged;
    _engine.onDemoEvent = _recordDemoEvent;

    _demoAuth = DemoAuthService(widget.authService);
    _demoApi = DemoRaceApiService(_engine);
    _analytics =
        widget.analytics ??
        ActivationAnalyticsService(backendApiService: widget.backendApiService);

    unawaited(
      _analytics.record(
        'tutorial_opened',
        context: const {'source': 'onboarding'},
      ),
    );
    _nudge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  /// Swallows an off-script tray tap and shakes the coach instead.
  ///
  /// Returning false here is the whole point: the box reel is pushed BEFORE
  /// its API call, so refusing any later would leave the user watching a reel
  /// that resolves to nothing.
  bool _gateTap(Map<String, dynamic> item) {
    final onScript = _engine.isOnScriptTap(
      isMysteryBox: (item['status'] as String?) == 'MYSTERY_BOX',
      type: item['type'] as String?,
    );
    if (onScript) return true;
    _nudge.forward(from: 0);
    unawaited(_analytics.record('tutorial_offscript_tap'));
    return false;
  }

  @override
  void dispose() {
    _nudge.dispose();
    _attackTimer?.cancel();
    _finishTimer?.cancel();
    _engine.onChanged = null;
    _engine.onDemoEvent = null;
    _demoAuth.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  void _recordDemoEvent(String name) {
    unawaited(_analytics.record(name));
  }

  /// Re-measures the anchor and drives the beats that are not user taps.
  ///
  /// §8.2: failing open is mandatory. If anything in here throws, the demo
  /// exits to the next onboarding step rather than trapping the user.
  void _afterFrame() {
    if (!mounted) return;
    try {
      _measureAnchor();
      _syncBeat();
    } catch (_) {
      _finish(completed: false);
    }
  }

  /// The key this beat's anchor points at, or null for an unanchored beat.
  GlobalKey? _anchorKey() => switch (kDemoBeatAnchor[_engine.beat]) {
    DemoAnchor.powerups => _powerupsKey,
    DemoAnchor.clock => _clockKey,
    _ => null,
  };

  void _measureAnchor() {
    final key = _anchorKey();
    if (key == null) {
      if (_anchorRect != null) setState(() => _anchorRect = null);
      return;
    }
    final ctx = key.currentContext;
    final stageCtx = _stageKey.currentContext;
    if (ctx == null || stageCtx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    final stage = stageCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || stage == null || !stage.attached) {
      return;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: stage) & box.size;
    if (rect != _anchorRect) setState(() => _anchorRect = rect);
  }

  void _syncBeat() {
    final beat = _engine.beat;

    // Beat 6 is deliberately not a tap: being attacked is the one lesson that
    // has to happen TO the user. The shield is already up, so it lands as a
    // save rather than a punishment.
    if (beat == DemoBeat.blockedAttack &&
        !_engine.attackResolved &&
        _attackTimer == null) {
      _attackTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        final result =
            _engine.resolveScriptedAttack()['result'] as Map<String, dynamic>;
        _showBlockedOutcome(result);
      });
    }

    // Beat 8: the floor lifts and the clock runs out.
    if (beat == DemoBeat.finish && !_finalCountdownStarted) {
      _finalCountdownStarted = true;
      _engine.startFinalCountdown(_engine.now());
      _finishTimer = Timer(DemoRaceEngine.finalCountdown, () {
        if (!mounted) return;
        _engine.completeRace();
      });
    }

    if (_lastBeat != beat) {
      _lastBeat = beat;
      unawaited(_scrollAnchorIntoView());
    }
  }

  /// The tray lives inside the real screen's scroll view, so a beat that points
  /// at it has to make sure it is on screen — the user must be able to tap it.
  ///
  /// The re-measure after the scroll settles is NOT optional. `_afterFrame`
  /// only runs on mount and on engine changes, so without it `_anchorRect`
  /// keeps whatever value it had when the beat flipped — measured mid-flight,
  /// before this scroll moved the tray. That stale rect is what put the ring
  /// and the scrim's cut-out over the activity panel at the bottom of the
  /// screen instead of around the powerup boxes.
  Future<void> _scrollAnchorIntoView() async {
    final anchor = kDemoBeatAnchor[_engine.beat];
    final key = _anchorKey();
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return;
    try {
      await Scrollable.ensureVisible(
        ctx,
        // The clock lives in the hero header, so beat 8 scrolls all the way
        // back to the top; the tray just needs to clear the coach post.
        alignment: anchor == DemoAnchor.clock ? 0.0 : 0.35,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // Fall through — a failed scroll must still re-measure, otherwise the
      // mark is left pointing at wherever the tray used to be.
    }
    if (!mounted) return;
    _measureAnchor();
  }

  Future<void> _showBlockedOutcome(Map<String, dynamic> result) async {
    if (_blockedModalShown) return;
    _blockedModalShown = true;
    // The REAL blocked-outcome reveal, classified from the real `outcome` /
    // `blocked` discriminators — the same widget the live screen shows. The
    // subtitle is overridden because this attack came AT the user; the shipped
    // default is written from the attacker's side.
    await showAttackOutcomeModal(
      context,
      result,
      subtitleOverride:
          '${DemoRaceEngine.rivalLeaderName} tried to steal your steps',
    );
  }

  // -- Exits ------------------------------------------------------------------

  Future<void> _finish({required bool completed}) async {
    if (_finishing) return;
    _finishing = true;

    if (completed) {
      // D5 / §6.2: the SAME ledger key the settings tutorial uses, so a user
      // who does both gets 100 coins total, not 200.
      try {
        await widget.authService.claimTutorialReward();
      } catch (_) {}
      unawaited(
        _analytics.record(
          'tutorial_completed',
          context: const {'source': 'onboarding'},
        ),
      );
    } else {
      unawaited(
        _analytics.record(
          'tutorial_skipped',
          context: {
            'source': 'onboarding',
            // Per-beat drop-off. The wire type is a decimal STRING (F7).
            'step': _engine.beat.stepValue,
          },
        ),
      );
    }
    widget.onDone(completed);
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final beat = _engine.beat;
    final copy = kDemoBeatCopy[beat]!;

    return PopScope(
      // §5.7b/D3: back and swipe-back are the skip affordance, never a silent
      // exit — the gate must always end up satisfied.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(completed: false);
      },
      // The race screen scrolls freely during the demo (§16h — wandering into
      // chat or the odds sheet must not break the script). Every one of those
      // scrolls moves the anchored tray, so the mark has to re-measure or it
      // drifts off the thing it is pointing at.
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _measureAnchor();
          return false; // never swallow — the real screen still owns the scroll
        },
        child: Stack(
          key: _stageKey,
          children: [
            Positioned.fill(
              child: RaceDetailScreen(
                authService: _demoAuth,
                raceId: DemoRaceEngine.raceId,
                backendApiService: _demoApi,
                demoMode: true,
                // notificationService and onBoxOpened are BOTH withheld: no OS
                // prompt can fire over a fake race, and a demo box can never
                // burn the real first-box notification trigger (G3).
                tutorialPowerupsKey: _powerupsKey,
                tutorialClockKey: _clockKey,
                demoTapGate: _gateTap,
              ),
            ),

            // Focus scrim. The demo shows the WHOLE race screen — leaderboard,
            // powerup tray, activity/chat — so without this every region competes
            // at equal weight and nothing says "look here". It dims everything
            // except the anchor, which is what makes the coach post read as an
            // instruction rather than one more panel.
            //
            // IgnorePointer is load-bearing: unlike the spotlight tutorial's
            // opaque scrim, this must never swallow a tap. The highlighted
            // control stays live, and so does the rest of the screen.
            if (beat != DemoBeat.win)
              Positioned.fill(
                child: IgnorePointer(
                  child: _FocusScrim(hole: _anchorRect, beat: beat),
                ),
              ),

            // The mark. Behind an IgnorePointer so the highlighted control stays
            // tappable — this is the central difference from the spotlight
            // tutorial, whose opaque scrim swallows every tap.
            if (_anchorRect != null && beat != DemoBeat.win)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CoachRing(
                    rect: _anchorRect!,
                    color: palette.pillGold,
                  ),
                ),
              ),

            if (beat != DemoBeat.win)
              Positioned(
                right: 12,
                top: MediaQuery.of(context).padding.top + 10,
                child: _SkipChip(onTap: () => _finish(completed: false)),
              ),

            if (beat != DemoBeat.win)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).padding.bottom + 14,
                child: _NudgeShake(
                  controller: _nudge,
                  child: _CoachPost(
                    key: ValueKey(beat),
                    beat: beat,
                    title: copy.title,
                    body: copy.body,
                    cta: copy.cta,
                    pointsUp: _anchorRect != null,
                    onCta: switch (beat) {
                      DemoBeat.intro => _engine.acknowledgeIntro,
                      DemoBeat.blockedAttack => _engine.acknowledgeAttack,
                      _ => null,
                    },
                  ),
                ),
              ),

            // Beat 8's lesson IS the clock, so the clock has to be the loudest
            // thing on screen. The hero chip renders it at 15px in white —
            // right for a race you are already in, far too quiet for the moment
            // you are being taught what running out feels like. This restates
            // it directly under the marked chip rather than restyling the
            // shared hero, which real races also render.
            if (beat == DemoBeat.finish && _anchorRect != null)
              Positioned(
                left: 0,
                right: 0,
                top: _anchorRect!.bottom + 16,
                child: IgnorePointer(
                  child: _FinalCountdown(
                    remaining: () => _engine.remainingAt(_engine.now()),
                  ),
                ),
              ),

            if (beat == DemoBeat.win)
              Positioned.fill(
                child: _WinCard(
                  displayName: _engine.myDisplayName,
                  onContinue: () => _finish(completed: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The mark
// -----------------------------------------------------------------------------

/// A hand-drawn-feeling ring around the thing the coach is pointing at.
///
/// Chrome, not artwork: a dashed rounded rect plus a soft breathing glow. It
/// never dims the screen and never intercepts a gesture.
class _CoachRing extends StatefulWidget {
  const _CoachRing({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  State<_CoachRing> createState() => _CoachRingState();
}

class _CoachRingState extends State<_CoachRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _CoachRingPainter(
          rect: widget.rect,
          color: widget.color,
          t: Curves.easeInOut.transform(_controller.value),
        ),
      ),
    );
  }
}

class _CoachRingPainter extends CustomPainter {
  const _CoachRingPainter({
    required this.rect,
    required this.color,
    required this.t,
  });

  final Rect rect;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final inflated = rect.inflate(10 + t * 4);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(14));

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.16 + t * 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Dashed stroke, drawn by hand along the path so the ring reads as chalk
    // on a trail sign rather than a CSS outline.
    final dash = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final metric
        in Path().let((p) => p..addRRect(rrect)).computeMetrics()) {
      var distance = t * 12;
      while (distance < metric.length) {
        final end = (distance + 9).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), dash);
        distance = end + 7;
      }
    }
  }

  @override
  bool shouldRepaint(_CoachRingPainter old) =>
      old.rect != rect || old.t != t || old.color != color;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// -----------------------------------------------------------------------------
// The off-script nudge
// -----------------------------------------------------------------------------

/// A short damped horizontal shake, played when the user taps something the
/// current beat is not asking for.
///
/// Deliberately motion-only — no error text, no modal. Trying the next box was
/// a reasonable thing to do, not a mistake to scold; the job is just to throw
/// the eye back to the coach, which already says what the step wants.
class _NudgeShake extends StatelessWidget {
  const _NudgeShake({required this.controller, required this.child});

  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, inner) {
        final t = controller.value;
        // Three decaying swings that land back at exactly 0 when t == 1.
        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 11 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: inner);
      },
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// The final countdown
// -----------------------------------------------------------------------------

/// The last seconds, restated loud and in the error red under the marked hero
/// chip.
///
/// Owns its own 1s ticker on purpose: the host only rebuilds when the ENGINE
/// changes, and during the final countdown the engine emits nothing between
/// beat 8 starting and the race completing — so a value computed in the host's
/// build would sit frozen for the whole six seconds.
class _FinalCountdown extends StatefulWidget {
  const _FinalCountdown({required this.remaining});

  final Duration Function() remaining;

  @override
  State<_FinalCountdown> createState() => _FinalCountdownState();
}

class _FinalCountdownState extends State<_FinalCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final left = widget.remaining();
    final seconds = left.inSeconds;
    final mmss =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final text = seconds >= 60 ? mmss : '$seconds';

    return Center(
      child: TweenAnimationBuilder<double>(
        // Re-keyed each whole second so the number pulses as it drops.
        key: ValueKey(seconds),
        tween: Tween(begin: 1.18, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Text(
          text,
          style: PixelText.number(size: 76, color: palette.error).copyWith(
            shadows: [
              Shadow(
                color: palette.error.withValues(alpha: 0.55),
                blurRadius: 24,
              ),
              const Shadow(color: Color(0xCC000000), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The focus scrim
// -----------------------------------------------------------------------------

/// Dims the race screen everything-except-the-anchor, so the coach post and the
/// control it points at are the only things at full brightness.
///
/// Deliberately NOT opaque: the race is still running underneath and the user
/// should see it move. This is a spotlight of attention, not of interaction —
/// the caller wraps it in an `IgnorePointer` so every tap still lands.
class _FocusScrim extends StatelessWidget {
  const _FocusScrim({required this.hole, required this.beat});

  final Rect? hole;
  final DemoBeat beat;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Re-keyed per beat so the dim re-settles as the anchor moves, rather
      // than snapping.
      key: ValueKey(beat),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, v, _) => CustomPaint(
        size: Size.infinite,
        painter: _FocusScrimPainter(hole: hole, t: v),
      ),
    );
  }
}

class _FocusScrimPainter extends CustomPainter {
  const _FocusScrimPainter({required this.hole, required this.t});

  final Rect? hole;
  final double t;

  // Enough to push the background back without hiding the race. Above ~0.55 the
  // leaderboard stops reading as "live" and the demo loses its point.
  static const _maxDim = 0.46;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    var path = full;

    if (hole != null) {
      // Matches the coach ring's inflate so the dashed ring sits ON the edge of
      // the lit area instead of floating inside a dark band.
      final cut = Path()
        ..addRRect(
          RRect.fromRectAndRadius(hole!.inflate(12), const Radius.circular(16)),
        );
      path = Path.combine(PathOperation.difference, full, cut);
    }

    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: _maxDim * t),
    );
  }

  @override
  bool shouldRepaint(_FocusScrimPainter old) => old.hole != hole || old.t != t;
}

// -----------------------------------------------------------------------------
// The coach post
// -----------------------------------------------------------------------------

/// A trail signpost docked at the bottom edge: two short wooden legs, a
/// parchment board, and — when the coach is pointing at something — a blaze
/// chevron aimed up the screen at it.
class _CoachPost extends StatelessWidget {
  const _CoachPost({
    super.key,
    required this.beat,
    required this.title,
    required this.body,
    required this.cta,
    required this.pointsUp,
    required this.onCta,
  });

  final DemoBeat beat;
  final String title;
  final String body;
  final String? cta;
  final bool pointsUp;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, (1 - v) * 26),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pointsUp)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Icon(
                Icons.keyboard_double_arrow_up_rounded,
                size: 26,
                color: palette.pillGold,
              ),
            ),
          GameContainer(
            key: const Key('demo-coach-card'),
            frameColor: palette.pillGold,
            // The halo is what lifts the board off the panels behind it. The
            // race screen's own cards all use the default hard drop shadow, so
            // a glow is the cheapest way to say "this one is not part of the
            // furniture" without hardcoding a surface colour that would fight
            // the night palette.
            glowColor: palette.pillGold,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The numbering earns its place: this really is a fixed
                // nine-beat sequence, and knowing how much is left is what
                // stops a new user bailing at beat 3.
                //
                // Sizes below track PixelText's own defaults (title 30 / body
                // 17.5). The originals — 19/14/10 — were far enough under the
                // design system that the board read as caption text on a screen
                // full of louder elements.
                Text(
                  'STEP ${beat.number} OF 9',
                  style: PixelText.body(
                    size: 12,
                    color: palette.textMid,
                  ).copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: PixelText.title(size: 23, color: palette.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: PixelText.body(size: 16, color: palette.textMid),
                ),
                if (cta != null) ...[
                  const SizedBox(height: 14),
                  PillButton(
                    key: const Key('demo-coach-cta'),
                    label: cta!,
                    variant: PillButtonVariant.primary,
                    fullWidth: true,
                    fontSize: 14,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: onCta,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkipChip extends StatelessWidget {
  const _SkipChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return GestureDetector(
      key: const Key('demo-skip'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: palette.woodDarker.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 2,
          ),
        ),
        child: Text(
          'SKIP',
          style: PixelText.body(size: 11, color: Colors.white),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The win card
// -----------------------------------------------------------------------------

class _WinCard extends StatelessWidget {
  const _WinCard({required this.displayName, required this.onContinue});

  final String displayName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Material(
      key: const Key('demo-win-card'),
      color: Colors.black.withValues(alpha: 0.72),
      child: Stack(
        children: [
          // A race finish is the one place confetti is allowed.
          const Positioned.fill(child: CelebrationConfetti()),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.86, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: GameContainer(
                  frameColor: palette.medalGold,
                  glowColor: palette.medalGold,
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '1ST',
                        style: PixelText.title(
                          size: 46,
                          color: palette.medalGold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You took the lead with a Shortcut and held it.',
                        textAlign: TextAlign.center,
                        style: PixelText.body(size: 14, color: palette.textMid),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SpinningCoin(size: 30),
                          const SizedBox(width: 10),
                          Text(
                            '+100',
                            style: PixelText.title(
                              size: 30,
                              color: palette.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Starter coins, on us.',
                        style: PixelText.body(size: 12, color: palette.textMid),
                      ),
                      const SizedBox(height: 22),
                      PillButton(
                        key: const Key('demo-win-continue'),
                        label: 'CONTINUE',
                        variant: PillButtonVariant.primary,
                        fullWidth: true,
                        fontSize: 15,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: onContinue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
