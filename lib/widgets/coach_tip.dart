import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/onboarding_state_service.dart';
import '../styles.dart';

/// The concepts evicted from the ten-step tutorial don't disappear — they are
/// taught the first time the user actually reaches the surface they belong to.
///
/// This batch ships the *mechanism* plus exactly three tips (spec §5.11.6). The
/// rest are a deliberate follow-up, so this enum is intentionally short and a
/// test asserts its length. Note what is **not** here: nothing fires on a box
/// open. Boxes and powerups are taught by tutorial steps 3–4, and the
/// notification ask already owns that moment; two interruptions on one trigger
/// would be worse than the problem being solved.
enum CoachTipId { milestoneClaim, friendsAdd, leaderboardScope }

String coachTipCopy(CoachTipId id) => switch (id) {
  CoachTipId.milestoneClaim => 'Tap it to claim your coins.',
  CoachTipId.friendsAdd =>
    'Add friends to race them. Invite one and you both earn coins.',
  CoachTipId.leaderboardScope =>
    'Switch between everyone and just your friends.',
};

String _storageId(CoachTipId id) => switch (id) {
  CoachTipId.milestoneClaim => 'milestone_claim',
  CoachTipId.friendsAdd => 'friends_add',
  CoachTipId.leaderboardScope => 'leaderboard_scope',
};

/// Persisted seen-set for one-shot coach tips. A tip that has been shown once
/// never returns, so this is deliberately write-once per id.
class CoachTipStore {
  final Set<CoachTipId> _memory = <CoachTipId>{};

  Future<bool> hasSeen(CoachTipId id) async {
    if (_memory.contains(id)) return true;
    final prefs = await SharedPreferences.getInstance();
    final seen =
        prefs.getStringList(OnboardingStateService.keyCoachTipsSeen) ??
        const <String>[];
    return seen.contains(_storageId(id));
  }

  Future<void> markSeen(CoachTipId id) async {
    _memory.add(id);
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{
      ...?prefs.getStringList(OnboardingStateService.keyCoachTipsSeen),
      _storageId(id),
    };
    await prefs.setStringList(
      OnboardingStateService.keyCoachTipsSeen,
      seen.toList(),
    );
  }
}

/// Process-wide store, so two surfaces mounted in the same session agree about
/// what has already been shown without threading an instance through the tree.
/// The durable record is SharedPreferences; this only saves a read.
final CoachTipStore coachTipStore = CoachTipStore();

/// Wraps a surface and, the first time it is reached, floats a small coach tip
/// beneath it.
///
/// Design notes. The tutorial's spotlight is a full-screen takeover; that would
/// be wildly disproportionate for one sentence, and it swallows taps, which is
/// exactly wrong at a moment the user is mid-action. So a tip is a small
/// parchment card that sits *next to* the thing it explains, leaves the app
/// fully interactive, and has one dismissal. It slides up rather than fading so
/// it reads as attached to the element above it, not as a floating toast.
class CoachTipHost extends StatefulWidget {
  const CoachTipHost({
    super.key,
    required this.tip,
    required this.child,
    required this.store,
    this.enabled = true,
    this.onShown,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final CoachTipId tip;
  final Widget child;
  final CoachTipStore store;

  /// Space around the tip card.
  ///
  /// The default matches a surface that supplies its own 16pt gutters (the
  /// home tab's milestone section). A host that is *already* inside a padded
  /// column must pass zero horizontal margin, or the card ends up inset twice
  /// and visibly narrower than the control it explains — which is exactly how
  /// it shipped on the Friends tab.
  final EdgeInsets margin;

  /// The trigger condition — "the user actually reached this surface". False
  /// keeps the tip latent without consuming it.
  final bool enabled;

  final VoidCallback? onShown;

  @override
  State<CoachTipHost> createState() => _CoachTipHostState();
}

class _CoachTipHostState extends State<CoachTipHost>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  // Eagerly constructed: a `late final` here is only created on first access,
  // which means dispose() would build a controller against a deactivated
  // element for the (common) case where the tip never shows.
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _maybeShow();
  }

  @override
  void didUpdateWidget(covariant CoachTipHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) _maybeShow();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _maybeShow() async {
    if (!widget.enabled || _visible) return;
    if (await widget.store.hasSeen(widget.tip)) return;
    if (!mounted) return;
    // Consumed on show, not on dismiss: a user who backs out of the screen has
    // still been told, and a tip that could return is not a one-shot.
    await widget.store.markSeen(widget.tip);
    if (!mounted) return;
    setState(() => _visible = true);
    _entrance.forward();
    widget.onShown?.call();
  }

  void _dismiss() {
    _entrance.reverse().whenComplete(() {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    final colors = AppColors.of(context);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _entrance,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.25),
              end: Offset.zero,
            ).animate(curve),
            child: Padding(
              padding: widget.margin,
              // Same parchment game-piece language as every other card in the
              // app (races/leaderboard `_boardCardDecoration`): 14pt radius, a
              // roofDark keyline, and the hard 4pt drop with no blur. The
              // earlier accent-bordered, 12pt-radius, 3pt-shadow card was the
              // only surface using those values and read as a foreign toast.
              child: DecoratedBox(
                key: const Key('coach-tip-card'),
                decoration: BoxDecoration(
                  color: colors.parchment,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.roofDark.withValues(alpha: 0.55),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        size: 18,
                        color: colors.pillGoldDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          coachTipCopy(widget.tip),
                          style: PixelText.body(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // A gold pill, not a bare text button: dismissal is the
                      // one action on this card, and the rest of the app spells
                      // actions as pills.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _dismiss,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: colors.pillGold,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.pillGoldDark),
                          ),
                          child: Text(
                            'GOT IT',
                            style: PixelText.title(
                              size: 11,
                              color: colors.textDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
