import 'package:flutter/material.dart';
import '../models/character_wardrobe.dart';
import '../styles.dart';
import 'coin_glyph.dart';
import 'race_ui.dart';

class ShopCharacterCard extends StatelessWidget {
  const ShopCharacterCard({
    super.key,
    required this.character,
    this.onEdit,
    this.onEquip,
    this.onBuy,
  });
  final ShopCharacter character;
  final VoidCallback? onEdit, onEquip, onBuy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final price = wardrobeCoinPrice(character.item['priceCoins']);
    final purchasable = character.canPurchase && price != null;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          '${character.name}, ${character.owned ? 'owned' : 'unowned'}${character.active ? ', active' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
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
        child: Column(
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
                        size: constraints.biggest.shortestSide.clamp(24, 240),
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
            if (character.owned) ...[
              Text(
                character.active ? 'ACTIVE' : 'OWNED',
                style: PixelText.title(
                  size: 10,
                  color: character.active ? colors.coinDark : colors.textMid,
                ),
              ),
              if (character.active)
                _action(
                  context,
                  'edit',
                  'Edit',
                  character.canEdit ? onEdit : null,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        context,
                        'edit',
                        'Edit',
                        character.canEdit ? onEdit : null,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        context,
                        'equip',
                        'Equip',
                        character.canActivate ? onEquip : null,
                        gold: true,
                      ),
                    ),
                  ],
                ),
            ] else if (purchasable) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CoinGlyph(size: 14),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      '$price',
                      style: PixelText.number(size: 13, color: colors.coinDark),
                    ),
                  ),
                ],
              ),
              _action(
                context,
                'buy',
                'Buy',
                onBuy,
                gold: true,
                semanticLabel: 'Buy ${character.name} for $price coins',
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Unavailable',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 11, color: colors.textMid),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    String action,
    String label,
    VoidCallback? onTap, {
    bool gold = false,
    String? semanticLabel,
  }) {
    final colors = AppColors.of(context);
    final id = 'shop-character-$action-${character.key}';
    return Semantics(
      button: true,
      onTap: onTap,
      enabled: onTap != null,
      label: semanticLabel ?? '$label ${character.name}',
      child: ExcludeSemantics(
        child: InkWell(
          key: Key(id),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Opacity(
                  opacity: onTap == null ? .5 : 1,
                  child: Container(
                    key: Key('$id-tag'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: gold ? colors.pillGold : colors.parchmentLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: gold
                            ? colors.pillGoldDark
                            : colors.parchmentBorder,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: PixelText.body(size: 10, color: colors.textDark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
