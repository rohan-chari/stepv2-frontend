import 'package:flutter/material.dart';
import '../models/character_wardrobe.dart';
import '../styles.dart';
import 'race_ui.dart';
import 'locked_shop_art.dart';

class ShopCharacterCard extends StatelessWidget {
  const ShopCharacterCard({
    super.key,
    required this.character,
    required this.onPressed,
  });
  final ShopCharacter character;
  final VoidCallback onPressed;
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
                    child: LockedShopArt(
                      key: const Key('shop-character-art'),
                      locked: !character.owned,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
