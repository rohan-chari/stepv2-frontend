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
    this.onDirectBuy,
  });
  final ShopCharacter character;
  final VoidCallback? onEdit, onEquip, onBuy, onDirectBuy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final price = wardrobeCoinPrice(character.item['priceCoins']);
    final purchasable = character.canPurchase && price != null;
    final buy = purchasable ? onBuy : null;
    final card = Container(
      key: character.goldAccess ? const Key('bara-gold-card-frame') : null,
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: character.goldAccess
              ? (colors.isDark ? colors.medalGold : colors.pillGoldDark)
              : colors.parchmentBorder,
          width: character.goldAccess ? 2 : 1,
        ),
      ),
      padding: EdgeInsets.all(character.goldAccess ? 2 : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(character.goldAccess ? 12 : 14),
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
                  padding: const EdgeInsets.all(10),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: Transform.translate(
                        offset: character.key == 'mouse'
                            ? const Offset(-6, 0)
                            : Offset.zero,
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
            ] else if (purchasable)
              _strip(
                context,
                key: Key('shop-character-buy-${character.key}'),
                label: '$price',
                leading: const CoinGlyph(),
                available: true,
                enabled: buy != null,
              )
            else if (character.directPurchaseAvailable)
              _strip(
                context,
                key: Key('shop-character-direct-${character.key}'),
                label: 'DIRECT PURCHASE',
                available: onDirectBuy != null,
                enabled: onDirectBuy != null,
              )
            else
              _strip(
                context,
                key: Key('shop-character-unavailable-${character.key}'),
                label: 'Unavailable',
                available: false,
                enabled: false,
              ),
          ],
        ),
      ),
    );
    final framedCard = character.goldAccess
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                Positioned(
                  top: -8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      key: const Key('bara-gold-card-label'),
                      color: colors.parchment,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Bara Gold',
                        style: PixelText.title(
                          size: 9,
                          color: colors.isDark
                              ? colors.textLight
                              : colors.textDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : card;
    return Semantics(
      container: true,
      explicitChildNodes: character.owned,
      button:
          !character.owned &&
          (purchasable || character.directPurchaseAvailable),
      enabled: !character.owned && purchasable
          ? buy != null
          : !character.owned && character.directPurchaseAvailable
          ? onDirectBuy != null
          : null,
      onTap: !character.owned
          ? purchasable
                ? buy
                : character.directPurchaseAvailable
                ? onDirectBuy
                : null
          : null,
      label:
          '${character.name}, ${character.owned ? 'owned' : 'unowned'}${character.active ? ', active' : ''}${!character.owned && purchasable ? ', buy for $price coins' : ''}',
      child: ExcludeSemantics(
        excluding: !character.owned && purchasable,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: !character.owned
              ? purchasable
                    ? buy
                    : character.directPurchaseAvailable
                    ? onDirectBuy
                    : null
              : null,
          child: framedCard,
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
