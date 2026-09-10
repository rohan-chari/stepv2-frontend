import 'package:flutter/material.dart';
import '../models/character_wardrobe.dart';
import '../styles.dart';
import 'race_ui.dart';
import 'pill_button.dart';

class ShopCharacterCard extends StatelessWidget {
  const ShopCharacterCard({
    super.key,
    required this.character,
    required this.onPressed,
    this.onEdit,
  });
  final ShopCharacter character;
  final VoidCallback onPressed;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label:
          '${character.name}, ${character.owned ? 'owned' : 'locked'}${character.active ? ', active' : ''}',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: colors.parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: character.active
                  ? colors.pillGoldDark
                  : colors.parchmentBorder,
              width: character.active ? 2 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: const Key('shop-character-art'),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
                          child: Transform.scale(
                            key: const Key('shop-character-art-scale'),
                            scale: 1.1,
                            child: RacerAvatar(
                              rank: 1,
                              size: constraints.biggest.shortestSide.clamp(
                                24,
                                240,
                              ),
                              showMedalRing: false,
                              animal: character.animal,
                              accessories: character.owned
                                  ? character.outfit?.items ?? []
                                  : [],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    character.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 13, color: colors.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    character.active
                        ? 'ACTIVE'
                        : character.owned
                        ? 'OWNED'
                        : 'LOCKED',
                    style: PixelText.title(
                      size: 10,
                      color: character.active
                          ? colors.coinDark
                          : colors.textMid,
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 44,
                      child: PillButton(
                        key: Key('shop-character-edit-${character.key}'),
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        variant: PillButtonVariant.secondary,
                        fontSize: 12,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        onPressed: onEdit,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
