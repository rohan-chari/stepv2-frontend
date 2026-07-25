import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../styles.dart';
import 'home_chrome.dart';

/// What a character's power is called and what it does, in the player's words.
///
/// The copy is deliberately QUALITATIVE. The herd bonus's step numbers come
/// from the backend's env-tunable balance config, so spelling them out here
/// would go stale the moment they're retuned — and the app would then be
/// confidently wrong about its own scoring.
class CharacterPower {
  const CharacterPower({
    required this.name,
    required this.detail,
    required this.glyph,
  });

  final String name;
  final String detail;
  final IconData glyph;

  /// Resolves an equipped character `assetKey` to its power. Null, missing and
  /// unrecognized values are all the default capybara — the same rule
  /// [animalSpriteFor] uses, so a character this build doesn't bundle degrades
  /// to the capybara copy instead of showing nothing.
  static CharacterPower forAnimal(String? animal) =>
      _powers[animal] ?? _powers[kDefaultAnimal]!;

  static const Map<String, CharacterPower> _powers = {
    kDefaultAnimal: CharacterPower(
      name: 'HERD BONUS',
      detail:
          'Capybaras look after their own. Every other capybara racing '
          'alongside you tops up the whole herd with bonus steps each day.',
      glyph: Icons.groups_2_rounded,
    ),
    'corgi_puppy': CharacterPower(
      name: 'ZOOMIES',
      detail:
          'Short bursts of pure chaos. A couple of times a day your steps '
          'count for far more — and you never know when it starts.',
      glyph: Icons.bolt_rounded,
    ),
    'turtle': CharacterPower(
      name: 'SHELL',
      detail:
          'Slow and steady, and armored. Attacks thrown your way sometimes '
          'bounce straight off the shell and do nothing at all.',
      glyph: Icons.shield_rounded,
    ),
  };
}

/// A collapsed, tappable notice of the equipped character's power, sitting with
/// the capy hero so it reads as "this is *my* character's power" (spec §9).
///
/// It expands IN PLACE — no dialog, no route — in the home surface's existing
/// motion language (a short eased size/fade, like the quick-action pills). The
/// expanded state is session-only by design: nothing is persisted, and nothing
/// is fetched.
///
/// The caller is responsible for hiding this entirely unless the server says
/// character powers are on; the chip must never assert a power that the
/// backend's kill switch has turned off.
class CharacterPowerChip extends StatefulWidget {
  const CharacterPowerChip({super.key, required this.animal});

  /// Equipped character `assetKey`; null = the default capybara.
  final String? animal;

  @override
  State<CharacterPowerChip> createState() => _CharacterPowerChipState();
}

class _CharacterPowerChipState extends State<CharacterPowerChip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final power = CharacterPower.forAnimal(widget.animal);
    // The night palette migrates pillGold to twilight violet, which disappears
    // against the dark tile fill; feedGold stays a legible gold there.
    final accent = colors.isDark ? colors.feedGold : colors.pillGold;

    return Semantics(
      button: true,
      expanded: _expanded,
      label: 'Your character power: ${power.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: colors.woodDarker.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _expanded
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.18),
              width: 2,
            ),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(power.glyph, size: 20, color: accent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'YOUR POWER',
                            style: HomeText.label(
                              size: 10,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            power.name,
                            style: PixelText.title(size: 15, color: accent),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    power.detail,
                    style: HomeText.body(
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
