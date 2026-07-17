import 'dart:ui';

import 'package:flutter/material.dart';
import '../styles.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/case_opening_strip.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';

const _powerupNames = {
  'LEG_CRAMP': 'Leg Cramp',
  'RED_CARD': 'Red Card',
  'SHORTCUT': 'Shortcut',
  'COMPRESSION_SOCKS': 'Compression Socks',
  'PROTEIN_SHAKE': 'Protein Shake',
  'RUNNERS_HIGH': "Runner's High",
  'SECOND_WIND': 'Second Wind',
  'STEALTH_MODE': 'Stealth Mode',
  'WRONG_TURN': 'Wrong Turn',
  'FANNY_PACK': 'Fanny Pack',
  'TRAIL_MIX': 'Trail Mix',
  'DETOUR_SIGN': 'Detour Sign',
  'LUCKY_HORSESHOE': 'Lucky Horseshoe',
  'CAMPFIRE_REST': 'Campfire Rest',
  'TRAIL_MAGNET': 'Trail Magnet',
  'POCKET_WATCH': 'Pocket Watch',
  'TRAIL_MINE': 'Trail Mine',
  'PINECONE_TOSS': 'Pinecone Toss',
  'SNEAKY_SWAP': 'Sneaky Swap',
  'MIRROR': 'Mirror',
  'CLEANSE': 'Cleanse',
  'IMPOSTER': 'Imposter',
  'RAINSTORM': 'Rainstorm',
  'SIGNAL_JAMMER': 'Signal Jammer',
};

const _powerupEntries = [
  (
    type: 'LEG_CRAMP',
    name: 'Leg Cramp',
    description: 'Freeze a rival\'s steps for 2 hours',
  ),
  (
    type: 'RED_CARD',
    name: 'Red Card',
    description: 'Remove 5% of the leader\'s steps',
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

  const CaseOpeningScreen({super.key, required this.openMysteryBox});

  @override
  State<CaseOpeningScreen> createState() => _CaseOpeningScreenState();
}

class _CaseOpeningScreenState extends State<CaseOpeningScreen> {
  bool _revealed = false;
  bool _resultReady = false;
  String _resultType = '';
  String _resultRarity = 'COMMON';
  bool _autoActivated = false;

  // The server roll fires HERE, from the reel's swipe gate — never on screen
  // open. Backing out with the X before swiping leaves the box unopened in
  // the inventory. Returns false (re-arming the reel) if the roll fails.
  Future<bool> _rollResult() async {
    try {
      final result = await widget.openMysteryBox();
      if (!mounted) return false;
      final openResult = result['result'] as Map<String, dynamic>? ?? result;
      setState(() {
        _resultType = openResult['type'] as String? ?? '';
        _resultRarity = openResult['rarity'] as String? ?? 'COMMON';
        _autoActivated = openResult['autoActivated'] == true;
        _resultReady = true;
      });
      return true;
    } catch (_) {
      if (mounted) showErrorToast(context, 'Failed to open mystery box');
      return false;
    }
  }

  void _onStripComplete() {
    if (_revealed || !_resultReady) return;
    setState(() => _revealed = true);
  }

  void _closeOverlay() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: ColoredBox(
                color: AppColors.roofDark.withValues(alpha: 0.78),
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
                const AdBannerSlot(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningContent() {
    return GameContainer(
      key: const ValueKey('opening'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      frameColor: AppColors.accent,
      surfaceColor: AppColors.parchmentLight,
      glowColor: AppColors.coinMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MYSTERY BOX',
                  style: HomeText.display(size: 28, color: HomeColors.ink),
                ),
              ),
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
              color: HomeColors.muted,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          CaseOpeningStrip(
            resultType: _resultType,
            resultRarity: _resultRarity,
            onSpinRequested: _rollResult,
            onComplete: _onStripComplete,
          ),
        ],
      ),
    );
  }

  String? _descriptionFor(String type) {
    for (final entry in _powerupEntries) {
      if (entry.type == type) return entry.description;
    }
    return null;
  }

  Widget _buildRevealCard() {
    final rarityColor = _rarityColor(_resultRarity);
    final name = _powerupNames[_resultType] ?? _resultType;
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
        surfaceColor: AppColors.parchmentLight,
        glowColor: rarityColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'UNBOXED',
              textAlign: TextAlign.center,
              style: HomeText.display(size: 32, color: HomeColors.ink),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: rarityColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _resultRarity.toUpperCase(),
                  style: PixelText.pill(size: 12, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.parchmentDark,
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
              style: PixelText.title(size: 24, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: PixelText.body(size: 13, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
            if (_autoActivated) ...[
              const SizedBox(height: 8),
              Text(
                'Auto-activated. Extra slot unlocked.',
                style: PixelText.body(size: 14, color: AppColors.pillGreen),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            PillButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(),
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  void _showPowerupGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchmentLight,
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
                      color: AppColors.woodMid,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'POWERUP GUIDE',
                    style: PixelText.title(size: 20, color: AppColors.textDark),
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
                          frameColor: AppColors.parchmentBorder,
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
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      entry.description,
                                      style: PixelText.body(
                                        size: 12,
                                        color: AppColors.textMid,
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

  static Color _rarityColor(String rarity) {
    switch (rarity.toUpperCase()) {
      case 'RARE':
        return AppColors.coinDark;
      case 'UNCOMMON':
        return const Color(0xFF4A90D9);
      default:
        return AppColors.woodMid;
    }
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
            color: AppColors.pillGold,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.pillGoldDark, width: 2),
            boxShadow: const [
              BoxShadow(
                color: AppColors.pillGoldShadow,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '?',
              style: PixelText.pill(size: 18, color: AppColors.textDark),
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
            color: AppColors.errorLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error, width: 2),
            boxShadow: const [
              BoxShadow(
                color: AppColors.error,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
