/// One row of the admin powerup-shop catalog (spec §5.1).
///
/// `name` is carried for display only — copy is owned by `PowerupCopy` and is
/// deliberately not editable here, so there is no setter for it anywhere.
class PowerupShopAdminItem {
  const PowerupShopAdminItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.powerupType,
    required this.priceCoins,
    required this.active,
    required this.testOnly,
    required this.sortOrder,
  });

  final String id;
  final String sku;
  final String name;
  final String powerupType;
  final int priceCoins;
  final bool active;
  final bool testOnly;
  final int sortOrder;

  /// Null when the row can't be identified or priced — a catalog entry this
  /// build can't render safely is skipped rather than shown with guessed
  /// values an admin might then save back.
  static PowerupShopAdminItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final price = raw['priceCoins'];
    if (price is! num || !price.isFinite) return null;

    String string(String key) {
      final value = raw[key];
      return value is String ? value : '';
    }

    final sortOrder = raw['sortOrder'];
    return PowerupShopAdminItem(
      id: id,
      sku: string('sku'),
      name: string('name'),
      powerupType: string('powerupType'),
      priceCoins: price.toInt(),
      active: raw['active'] == true,
      testOnly: raw['testOnly'] == true,
      sortOrder: sortOrder is num && sortOrder.isFinite ? sortOrder.toInt() : 0,
    );
  }
}
