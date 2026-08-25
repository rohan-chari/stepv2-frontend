import 'dart:ui';

import 'package:flutter/material.dart';
import '../styles.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/case_opening_strip.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/odds_sheet.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../constants/powerup_copy.dart';

const _powerupEntries = [
  (
    type: 'LEG_CRAMP',
    name: 'Leg Cramp',
    description: 'Freeze a rival\'s steps for 2 hours',
  ),
  (
    type: 'RED_CARD',
    name: 'Red Card',
    description: 'Remove 10% of the leader\'s steps',
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
    description: 'Pull your next mystery box closer',
  ),
  (
    type: 'POCKET_WATCH',
    name: 'Pocket Watch',
    description: 'Extend all active timed buffs',
  ),
  (
    type: 'TRAIL_MINE',
    name: 'Trail Mine',
    description: 'Drop a trap at your current steps',
  ),
  (
    type: 'PINECONE_TOSS',
    name: 'Pinecone Toss',
    description: 'Hit the runner ahead or behind',
  ),
  (
    type: 'SNEAKY_SWAP',
    name: 'Sneaky Swap',
    description: 'View and swap a rival powerup',
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
];

/// Full-screen overlay for opening a mystery box with CSGO-style animation.
class CaseOpeningScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() openMysteryBox;

  /// Raw `powerupData.dropOdds` from getRaceProgress (spec §5.3). Null on an
  /// older backend; malformed on a backend this build doesn't understand.
  /// Either way the ODDS affordance is hidden entirely — a wrong odds display
  /// is worse than none.
  final Map<String, dynamic>? dropOdds;

  /// Server-authoritative `rarityByType`; the reel's bundled table is a
  /// fallback. Null on an older backend.
  final Map<String, String>? rarityByType;

  /// Invoked once the reel LANDS on the result (spec §6), carrying the raw
  /// server response. The host commits the visible-inventory transition here —
  /// never on the API response — so the rolled powerup (or an auto-activated
  /// Fanny Pack row deletion) can't appear behind the still-spinning reel.
  final void Function(Map<String, dynamic> result)? onRevealed;

  /// Lifecycle hooks used by the demo to keep its pending roll aligned with
  /// the reel. They never affect the live backend opening path.
  final VoidCallback? onRollStarted;
  final VoidCallback? onRollFailed;
  final VoidCallback? onCancelled;

  /// Item 11 (batch 2026-08-08) — the rewarded-ad reroll.
  ///
  /// Non-null ONLY when the host wants the button: the race detail screen
  /// passes it when the backend advertised `powerupData.boxReroll == true`
  /// (which itself requires the server kill switch ON and this client
  /// declaring `ads`). Null everywhere else, which is how
  /// [MultiCaseOpeningScreen] (OPEN ALL), the hand-forked daily-reward reel
  /// and demo mode all stay free of it without knowing this feature exists.
  ///
  /// Given the revealed powerup's id, performs ad + reroll and resolves the
  /// NEW `{type, rarity}` — or null if the user backed out or it failed.
  final Future<Map<String, dynamic>?> Function(String powerupId)? onReroll;

  /// Renders the reel inside the onboarding demo race (spec §5.7c / G8).
  /// Suppression only: it hides this screen's two `AdBannerSlot`s, which the
  /// race screen's own banner fix does not reach. Nothing about the reel, the
  /// odds sheet or the reveal changes.
  final bool demoMode;

  const CaseOpeningScreen({
    super.key,
    required this.openMysteryBox,
    this.onRevealed,
    this.onRollStarted,
    this.onRollFailed,
    this.onCancelled,
    this.dropOdds,
    this.rarityByType,
    this.onReroll,
    this.demoMode = false,
  });

  @override
  State<CaseOpeningScreen> createState() => _CaseOpeningScreenState();
}

class _CaseOpeningScreenState extends State<CaseOpeningScreen> {
  bool _revealed = false;
  bool _resultReady = false;
  // True once the server roll has begun and the reel is committed to spinning;
  // gates dismissal (PopScope + X) until the result is revealed. Reset to false
  // if the roll fails so the user can back out of the re-armed reel.
  bool _spinning = false;
  String _resultType = '';
  String _resultRarity = 'COMMON';
  bool _autoActivated = false;
  Map<String, dynamic>? _result;

  // Item 11 — reroll state. `_rerollUsed` is client-side belt-and-braces; the
  // server is the authority (409 ALREADY_REROLLED) because `rerolledAt` is
  // stamped on the row.
  bool _rerollUsed = false;
  bool _rerolling = false;

  /// The revealed powerup's id, or null when the payload didn't carry one —
  /// in which case there is nothing to reroll and the button stays hidden.
  String? get _revealedPowerupId {
    final result = _result;
    if (result == null) return null;
    final openResult = result['result'] as Map<String, dynamic>? ?? result;
    final id = openResult['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Whether to offer the reroll: the host wired it, we're not in the demo,
  /// the reveal has landed, this box hasn't already been rerolled, and we know
  /// which powerup to reroll.
  bool get _canReroll =>
      widget.onReroll != null &&
      !widget.demoMode &&
      _revealed &&
      !_rerollUsed &&
      _revealedPowerupId != null;

  Future<void> _handleReroll() async {
    final powerupId = _revealedPowerupId;
    final reroll = widget.onReroll;
    if (powerupId == null || reroll == null || _rerolling) return;

    setState(() => _rerolling = true);
    try {
      final rerolled = await reroll(powerupId);
      if (!mounted) return;
      if (rerolled == null) {
        // Backed out of the ad, or the reroll failed. The host has already
        // surfaced any error; leave the original result standing.
        setState(() => _rerolling = false);
        return;
      }

      // Re-spin the reel to the new result: drop back to the ARMED,
      // pre-reveal state with the new outcome already resolved. The user
      // swipes once more and the strip lands on the new powerup — no second
      // server roll (`_resultReady` is already true, so the swipe gate spins
      // straight to it), and they get to watch the reroll rather than having
      // the answer swapped under them.
      setState(() {
        _rerollUsed = true;
        _rerolling = false;
        _resultType = rerolled['type'] as String? ?? _resultType;
        _resultRarity = rerolled['rarity'] as String? ?? _resultRarity;
        // The reroll never auto-activates (it rerolls an already-HELD powerup).
        _autoActivated = false;
        // Rebuild `_result` around the rerolled outcome (keeping `id`): the
        // second reveal fires onRevealed with `_result`, and the host feeds it
        // to _optimisticallyApplyBoxOpen — a stale copy here would rewrite the
        // inventory row back to the PRE-reroll type behind the reel.
        final prev =
            (_result?['result'] as Map<String, dynamic>?) ??
            _result ??
            const <String, dynamic>{};
        _result = <String, dynamic>{
          'result': <String, dynamic>{
            ...prev,
            'type': _resultType,
            'rarity': _resultRarity,
            'autoActivated': false,
          },
        };
        _revealed = false;
        _resultReady = true;
        // Armed, not spinning: the strip shows its swipe gate again.
        _spinning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _rerolling = false);
    }
  }

  // Whether the overlay can currently be dismissed: before the roll starts
  // (nothing consumed) or after the reveal has landed. Never mid-spin.
  bool get _canDismiss => _revealed || !_spinning;

  // Parsed once per build-cycle input rather than per build: null whenever the
  // payload is absent OR incoherent, which is what hides the affordance.
  OddsBreakdown? _parsedDropOdds;
  bool _parsedDropOddsFor = false;

  OddsBreakdown? get _dropOdds {
    if (!_parsedDropOddsFor) {
      _parsedDropOdds = OddsBreakdown.parseDropOdds(widget.dropOdds);
      _parsedDropOddsFor = true;
    }
    return _parsedDropOdds;
  }

  @override
  void didUpdateWidget(CaseOpeningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dropOdds, widget.dropOdds)) {
      _parsedDropOddsFor = false;
    }
  }

  // The server roll fires HERE, from the reel's swipe gate — never on screen
  // open. Backing out with the X before swiping leaves the box unopened in
  // the inventory. Returns false (re-arming the reel) if the roll fails.
  Future<bool> _rollResult() async {
    // Re-armed with the outcome already resolved (the post-reroll swipe): spin
    // straight to it. Without this gate the fresh strip's swipe fires a SECOND
    // POST /open for a box that is no longer a box — a 400 and a bogus
    // "Failed to open mystery box" toast over a perfectly good reroll.
    if (_resultReady) {
      setState(() => _spinning = true);
      return true;
    }
    widget.onRollStarted?.call();
    setState(() => _spinning = true);
    try {
      final result = await widget.openMysteryBox();
      if (!mounted) return false;
      final openResult = result['result'] as Map<String, dynamic>? ?? result;
      setState(() {
        _result = result;
        _resultType = openResult['type'] as String? ?? '';
        _resultRarity = openResult['rarity'] as String? ?? 'COMMON';
        _autoActivated = openResult['autoActivated'] == true;
        _resultReady = true;
      });
      return true;
    } catch (_) {
      // Roll failed: the reel re-arms, so let the user back out again.
      if (mounted) {
        setState(() => _spinning = false);
        widget.onRollFailed?.call();
        showErrorToast(context, 'Failed to open mystery box');
      }
      return false;
    }
  }

  void _onStripComplete() {
    if (_revealed || !_resultReady) return;
    setState(() => _revealed = true);
    // Commit the inventory transition only now that the reel has landed.
    final result = _result;
    if (result != null) widget.onRevealed?.call(result);
  }

  void _closeOverlay() {
    // A committed spin cannot be dismissed midway (spec §6).
    if (!_canDismiss) return;
    if (!_revealed) widget.onCancelled?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the Android back button and the iOS swipe-back gesture while the
      // reel is mid-spin; allow it before the roll and after the reveal.
      canPop: _canDismiss,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: ColoredBox(
                  color: AppColors.of(context).roofDark.withValues(alpha: 0.78),
                  child: const CustomPaint(
                    painter: ArcadeCheckerPainter(
                      tileColor: Color(0x0AFFFFFF),
                      stripeColor: Color(0x14000000),
                      drawBottomStripe: false,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  AdBannerSlot(
                    placement: AdBannerPlacement.boxTop,
                    reserveSpaceWhileLoading: true,
                    hidden: widget.demoMode,
                  ),
                  if (!widget.demoMode)
                    const AdBannerSpacing(placement: AdBannerPlacement.boxTop),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _revealed
                                ? _buildRevealCard()
                                : _buildOpeningContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom banner, in-flow below the centered card so it reserves
                  // its own space and never covers the Continue button. Collapses
                  // to zero size unless banners are enabled AND an ad loads.
                  if (!widget.demoMode) const AdBannerSpacing(),
                  AdBannerSlot(
                    reserveSpaceWhileLoading: true,
                    hidden: widget.demoMode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpeningContent() {
    return GameContainer(
      key: const ValueKey('opening'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      frameColor: AppColors.of(context).accent,
      surfaceColor: AppColors.of(context).parchmentLight,
      glowColor: AppColors.of(context).coinMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MYSTERY BOX',
                  style: HomeText.display(
                    size: 28,
                    color: AppColors.of(context).ink,
                  ),
                ),
              ),
              // Renders nothing unless the server sent well-formed dropOdds.
              OddsAffordance(
                odds: _dropOdds,
                title: 'DROP ODDS',
                subtitle: 'Exactly what this box can roll for you right now.',
              ),
              if (_dropOdds != null) const SizedBox(width: 8),
              _GuideButton(onTap: () => _showPowerupGuide(context)),
              const SizedBox(width: 8),
              _CloseButton(onTap: _closeOverlay),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe the reel to crack it open',
            style: HomeText.body(
              size: 14,
              color: AppColors.of(context).muted,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          CaseOpeningStrip(
            resultType: _resultType,
            resultRarity: _resultRarity,
            onSpinRequested: _rollResult,
            onComplete: _onStripComplete,
            rarityByType: widget.rarityByType,
          ),
        ],
      ),
    );
  }

  // Prefer the backend copy catalog so duration text stays truthful when the
  // backend restandardizes powerup windows (spec §3.4/§6). The bundled
  // `_powerupEntries` string is only a last-resort fallback for a type the
  // catalog somehow doesn't cover.
  String? _descriptionFor(String type) {
    final catalogDesc = PowerupCopy.descriptionFor(type);
    if (catalogDesc.trim().isNotEmpty) {
      return catalogDesc;
    }
    for (final entry in _powerupEntries) {
      if (entry.type == type) return entry.description;
    }
    return null;
  }

  Widget _buildRevealCard() {
    // Shared with every other reel surface (case_opening_strip.caseRarityColor)
    // — this screen used to carry a byte-identical private copy.
    final rarityColor = caseRarityColor(_resultRarity);
    final name = PowerupCopy.nameFor(_resultType);
    final description = _descriptionFor(_resultType);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: GameContainer(
        key: const ValueKey('reveal'),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        frameColor: rarityColor,
        surfaceColor: AppColors.of(context).parchmentLight,
        glowColor: rarityColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'UNBOXED',
              textAlign: TextAlign.center,
              style: HomeText.display(
                size: 32,
                color: AppColors.of(context).ink,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.of(context).parchmentDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: rarityColor, width: 2),
                ),
                alignment: Alignment.center,
                child: PowerupIcon(type: _resultType, size: 82, spinning: true),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: PixelText.title(
                size: 24,
                color: AppColors.of(context).textDark,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: PixelText.body(
                  size: 13,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_autoActivated) ...[
              const SizedBox(height: 8),
              Text(
                'Auto-activated. Extra slot unlocked.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).pillGreen,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),
            PillButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              onPressed: _rerolling ? null : () => Navigator.of(context).pop(),
              fullWidth: true,
            ),
            if (_canReroll) ...[
              const SizedBox(height: 10),
              PillButton(
                key: const Key('case-reroll-button'),
                label: 'REROLL · WATCH AD',
                icon: Icons.ondemand_video_rounded,
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                loading: _rerolling,
                onPressed: _rerolling ? null : _handleReroll,
              ),
              const SizedBox(height: 4),
              Text(
                'One reroll per box. The new roll is final.',
                style: PixelText.body(
                  size: 11,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showPowerupGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchmentLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).woodMid,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'POWERUP GUIDE',
                    style: PixelText.title(
                      size: 20,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: _powerupEntries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = _powerupEntries[index];
                        return GameContainer(
                          padding: const EdgeInsets.all(10),
                          frameColor: AppColors.of(context).parchmentBorder,
                          child: Row(
                            children: [
                              PowerupIcon(
                                type: entry.type,
                                size: 34,
                                spinning: true,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: PixelText.title(
                                        size: 14,
                                        color: AppColors.of(context).textDark,
                                      ),
                                    ),
                                    Text(
                                      _descriptionFor(entry.type) ??
                                          entry.description,
                                      style: PixelText.body(
                                        size: 12,
                                        color: AppColors.of(context).textMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _GuideButton extends StatelessWidget {
  const _GuideButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.of(context).pillGold,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.of(context).pillGoldDark,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.of(context).pillGoldShadow,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '?',
              style: PixelText.pill(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.of(context).errorLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.of(context).error, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.of(context).error,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.of(context).textDark,
            ),
          ),
        ),
      ),
    );
  }
}
