import 'package:flutter/material.dart';
import '../models/character_wardrobe.dart';
import '../styles.dart';
import 'coin_glyph.dart';
import 'race_ui.dart';
import 'shop_tile_name.dart';

/// Character merchandise uses the shop's art window, name band and action strips.
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
    final buy = purchasable ? onBuy : null;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.parchmentBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                key: const Key('shop-character-art'),
                decoration: BoxDecoration(
                  color: colors.parchmentDark,
                  border: Border(
                    bottom: BorderSide(color: colors.parchmentBorder, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
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
            ),
            Container(
              key: Key('shop-character-name-${character.key}'),
              height: 32,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: ShopTileName(name: character.name, color: colors.textDark),
            ),
            if (character.owned) ...[
              _action(
                context,
                'edit',
                'Edit',
                character.canEdit ? onEdit : null,
                gold: false,
              ),
              _action(
                context,
                'equip',
                character.active ? 'ACTIVE' : 'Equip',
                !character.active && character.canActivate ? onEquip : null,
              ),
            ] else
              _strip(
                context,
                key: Key(
                  purchasable
                      ? 'shop-character-buy-${character.key}'
                      : 'shop-character-unavailable-${character.key}',
                ),
                label: purchasable ? '$price' : 'Unavailable',
                leading: purchasable ? const CoinGlyph() : null,
                available: purchasable,
                enabled: buy != null,
              ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: character.owned,
      button: !character.owned && purchasable,
      enabled: !character.owned && purchasable ? buy != null : null,
      onTap: !character.owned ? buy : null,
      label:
          '${character.name}, ${character.owned ? 'owned' : 'unowned'}${character.active ? ', active' : ''}${!character.owned && purchasable ? ', buy for $price coins' : ''}',
      child: ExcludeSemantics(
        excluding: !character.owned && purchasable,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: !character.owned ? buy : null,
          child: card,
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    String action,
    String label,
    VoidCallback? onTap, {
    bool gold = true,
  }) => Semantics(
    button: true,
    enabled: onTap != null,
    onTap: onTap,
    label: character.active && action == 'equip'
        ? '${character.name} is active'
        : '$label ${character.name}',
    child: ExcludeSemantics(
      child: InkWell(
        key: Key('shop-character-$action-${character.key}'),
        onTap: onTap,
        child: _strip(
          context,
          label: label,
          available: onTap != null,
          enabled: onTap != null,
          gold: gold,
        ),
      ),
    ),
  );

  Widget _strip(
    BuildContext context, {
    Key? key,
    required String label,
    required bool available,
    required bool enabled,
    bool gold = true,
    Widget? leading,
  }) {
    final colors = AppColors.of(context);
    return Container(
      key: key,
      height: 26,
      decoration: BoxDecoration(
        color: !available
            ? colors.parchmentDark
            : gold
            ? colors.pillGold.withValues(alpha: enabled ? .22 : .10)
            : colors.parchment,
        border: Border(
          top: BorderSide(
            color: available && gold
                ? colors.pillGoldDark
                : colors.parchmentBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 13,
                color: available ? colors.textDark : colors.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
