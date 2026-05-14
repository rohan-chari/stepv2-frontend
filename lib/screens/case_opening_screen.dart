import 'package:flutter/material.dart';
import '../styles.dart';
import '../widgets/arcade_page.dart';
import '../widgets/case_opening_strip.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';

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
];

/// Full-screen overlay for opening a mystery box with CSGO-style animation.
class CaseOpeningScreen extends StatefulWidget {
  final String resultType;
  final String resultRarity;
  final bool autoActivated;

  const CaseOpeningScreen({
    super.key,
    required this.resultType,
    required this.resultRarity,
    this.autoActivated = false,
  });

  @override
  State<CaseOpeningScreen> createState() => _CaseOpeningScreenState();
}

class _CaseOpeningScreenState extends State<CaseOpeningScreen> {
  bool _revealed = false;

  void _onStripComplete() {
    if (mounted) {
      setState(() => _revealed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchmentLight,
      body: ArcadePageBackground(
        showHeader: false,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
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
              Positioned(
                top: 4,
                right: 10,
                child: _GuideButton(onTap: () => _showPowerupGuide(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpeningContent() {
    return Column(
      key: const ValueKey('opening'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        Text(
          'MYSTERY BOX',
          textAlign: TextAlign.center,
          style: HomeText.display(size: 32, color: HomeColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Swipe the reel to crack it open',
          textAlign: TextAlign.center,
          style: HomeText.body(
            size: 15,
            color: HomeColors.muted,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        GameContainer(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          frameColor: AppColors.accent,
          surfaceColor: AppColors.accent,
          glowColor: AppColors.coinMid,
          child: CustomPaint(
            painter: const ArcadeCheckerPainter(),
            child: Column(
              children: [
                const SpinningCrate(size: 92),
                const SizedBox(height: 6),
                Text(
                  'READY TO OPEN',
                  style: PixelText.title(
                    size: 16,
                    color: AppColors.parchmentLight,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        CaseOpeningStrip(
          resultType: widget.resultType,
          resultRarity: widget.resultRarity,
          onComplete: _onStripComplete,
        ),
      ],
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

  Widget _buildRevealCard() {
    final rarityColor = _rarityColor(widget.resultRarity);
    final name = _powerupNames[widget.resultType] ?? widget.resultType;

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
      child: Column(
        key: const ValueKey('reveal'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          Text(
            'UNBOXED',
            textAlign: TextAlign.center,
            style: HomeText.display(size: 34, color: HomeColors.ink),
          ),
          const SizedBox(height: 18),
          GameContainer(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            frameColor: rarityColor,
            glowColor: rarityColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: rarityColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.resultRarity.toUpperCase(),
                    style: PixelText.pill(size: 12, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: AppColors.parchmentDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: rarityColor, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: PowerupIcon(
                    type: widget.resultType,
                    size: 82,
                    spinning: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: PixelText.title(size: 24, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
                if (widget.autoActivated) ...[
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
        ],
      ),
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
