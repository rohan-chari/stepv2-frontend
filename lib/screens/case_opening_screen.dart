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
        child: Column(
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
