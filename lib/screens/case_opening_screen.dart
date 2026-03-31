import 'package:flutter/material.dart';
import '../styles.dart';
import '../widgets/case_opening_strip.dart';
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
};

const _powerupEntries = [
  (type: 'LEG_CRAMP', name: 'Leg Cramp', description: 'Freeze a rival\'s steps for 2 hours'),
  (type: 'RED_CARD', name: 'Red Card', description: 'Remove 10% of the leader\'s steps'),
  (type: 'SHORTCUT', name: 'Shortcut', description: 'Steal 1,000 steps from a rival'),
  (type: 'COMPRESSION_SOCKS', name: 'Compression Socks', description: 'Shield against the next attack'),
  (type: 'PROTEIN_SHAKE', name: 'Protein Shake', description: '+1,500 bonus steps instantly'),
  (type: 'RUNNERS_HIGH', name: "Runner's High", description: '2x steps for 3 hours'),
  (type: 'SECOND_WIND', name: 'Second Wind', description: 'Bonus steps based on how far behind'),
  (type: 'STEALTH_MODE', name: 'Stealth Mode', description: 'Hide your progress for 4 hours'),
  (type: 'WRONG_TURN', name: 'Wrong Turn', description: 'Reverse a rival\'s steps for 1 hour'),
  (type: 'FANNY_PACK', name: 'Fanny Pack', description: 'Unlock an extra powerup slot'),
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
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            SizedBox.expand(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Crate at top
                if (!_revealed) ...[
                  const SpinningCrate(size: 70),
                  const SizedBox(height: 8),
                  Text(
                    'OPENING MYSTERY BOX...',
                    style: PixelText.title(size: 18, color: AppColors.coinLight),
                  ),
                  const SizedBox(height: 30),
                  // Scrolling strip
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CaseOpeningStrip(
                      resultType: widget.resultType,
                      resultRarity: widget.resultRarity,
                      onComplete: _onStripComplete,
                    ),
                  ),
                ],
                // Reveal card
                if (_revealed) ...[
                  _buildRevealCard(),
                ],
                const Spacer(flex: 3),
              ],
            ),
            ),
            // Question mark button — top right
            Positioned(
              top: 8,
              right: 12,
              child: GestureDetector(
                onTap: () => _showPowerupGuide(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.pillGoldDark,
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.pillGoldShadow,
                        offset: Offset(0, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.pillGold, AppColors.pillGoldDark],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '?',
                      style: PixelText.pill(size: 18, color: AppColors.textDark),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPowerupGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                    style: PixelText.title(size: 18, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: _powerupEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = _powerupEntries[index];
                        return Row(
                          children: [
                            PowerupIcon(type: entry.type, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    style: PixelText.title(
                                      size: 13,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  Text(
                                    entry.description,
                                    style: PixelText.body(
                                      size: 11,
                                      color: AppColors.textMid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          border: Border.all(color: rarityColor, width: 3),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: rarityColor.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rarity badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: rarityColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.resultRarity.toUpperCase(),
                style: PixelText.pill(size: 12, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            // Powerup icon
            PowerupIcon(type: widget.resultType, size: 56),
            const SizedBox(height: 12),
            // Powerup name
            Text(
              name,
              style: PixelText.title(size: 22, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
            if (widget.autoActivated) ...[
              const SizedBox(height: 8),
              Text(
                'Auto-activated! Extra slot unlocked.',
                style: PixelText.body(size: 14, color: AppColors.pillGreen),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            // Dismiss button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.pillGreen,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.pillGreenShadow,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  'NICE!',
                  style: PixelText.pill(size: 18),
                ),
              ),
            ),
          ],
        ),
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
