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
    this.onGetGold,
  });
  final ShopCharacter character;
  final VoidCallback? onEdit, onEquip, onBuy, onDirectBuy, onGetGold;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final price = wardrobeCoinPrice(character.item['priceCoins']);
    final purchasable = character.canPurchase && price != null;
    final opensPurchaseSheet =
        price != null && (purchasable || character.goldExclusive);
    final directPurchasable =
        character.directPurchaseAvailable &&
        character.directStoreProductId != null;
    final goldAction =
        character.goldAccess &&
        !character.hasAccess &&
        !purchasable &&
        !directPurchasable;
    final buy = opensPurchaseSheet ? onBuy : null;
    final card = Container(
      key: character.goldAccess ? const Key('bara-gold-card-frame') : null,
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(14),
        // Gold framing is identified by the key above; it must not alter the
        // full-width merchandise action geometry.
        border: null,
      ),
      // The border is decorative and must not shrink the merchandise action
      // bands. Keeping layout padding here made Gold cards' Edit/Equip rows
      // two pixels narrower than the card and broke the full-width contract.
      padding: EdgeInsets.zero,
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
                            accessories: character.hasAccess
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
            if (character.hasAccess) ...[
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
            ] else if (opensPurchaseSheet)
              _strip(
                context,
                key: Key('shop-character-buy-${character.key}'),
                label: character.goldExclusive ? 'BUY' : '$price',
                leading: character.goldExclusive ? null : const CoinGlyph(),
                available: true,
                enabled: onBuy != null,
              )
            else if (directPurchasable)
              _strip(
                context,
                key: Key('shop-character-direct-${character.key}'),
                label: 'BUY',
                available: onDirectBuy != null,
                enabled: onDirectBuy != null,
              )
            else if (goldAction)
              _strip(
                context,
                key: Key('shop-character-get-gold-${character.key}'),
                label: 'Get Gold',
                available: onGetGold != null,
                enabled: onGetGold != null,
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
    final cleanedCard = character.goldAccess
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Stack(clipBehavior: Clip.none, children: [card]),
          )
        : card;
    return Semantics(
      container: true,
      explicitChildNodes: character.hasAccess,
      button:
          !character.hasAccess &&
          (opensPurchaseSheet || directPurchasable || goldAction),
      enabled: !character.hasAccess && opensPurchaseSheet
          ? buy != null
          : !character.hasAccess && directPurchasable
          ? onDirectBuy != null
          : !character.hasAccess && goldAction
          ? onGetGold != null
          : null,
      onTap: !character.hasAccess
          ? opensPurchaseSheet
                ? buy
                : directPurchasable
                ? onDirectBuy
                : goldAction
                ? onGetGold
                : null
          : null,
      label:
          '${character.name}, ${character.owned
              ? 'owned'
              : character.hasAccess
              ? 'Included with Gold'
              : 'unowned'}${character.active ? ', active' : ''}${!character.hasAccess && purchasable ? ', buy for $price coins' : ''}',
      child: ExcludeSemantics(
        excluding: !character.hasAccess && opensPurchaseSheet,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: !character.hasAccess
              ? opensPurchaseSheet
                    ? buy
                    : directPurchasable
                    ? onDirectBuy
                    : goldAction
                    ? onGetGold
                    : null
              : null,
          child: cleanedCard,
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
