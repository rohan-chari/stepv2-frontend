import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/powerup_icon.dart';
import '../referral_screen.dart';

enum _ShopSection { store, inventory }

class ShopTab extends StatefulWidget {
  const ShopTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.onShopChanged,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final ValueChanged<Map<String, dynamic>>? onShopChanged;

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _backendApiService;
  Map<String, dynamic>? _catalog;
  Loadable<Map<String, dynamic>> _catalogState = const Loadable.initial();

  // Powerup store + inventory. Read defensively: if the new endpoints are
  // missing (older backend) these stay empty and the powerup sections hide.
  List<Map<String, dynamic>> _powerupStoreItems = const [];
  Map<String, int> _powerupInventory = const {};
  bool _powerupsAvailable = false;

  bool _loading = true;
  bool _saving = false;
  _ShopSection _section = _ShopSection.store;

  @override
  void initState() {
    super.initState();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final previous = _catalog;
    if (mounted) {
      setState(() {
        _loading = true;
        _catalogState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _catalogState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      final catalog = await _backendApiService.fetchShopCatalog(
        identityToken: token,
      );
      final coins = catalog['coins'] as int?;
      if (coins != null) {
        await widget.authService.updateCoins(coins);
      }

      // Powerups are loaded best-effort and never block the cosmetics catalog.
      await _loadPowerups(token);

      if (mounted) {
        setState(() {
          _catalog = catalog;
          _catalogState = Loadable.success(catalog);
          _loading = false;
        });
      }
      widget.onShopChanged?.call(catalog);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogState = Loadable.error(error.message, data: previous);
      });
      showErrorToast(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogState = Loadable.error(
          'Could not load the shop. Please try again.',
          data: previous,
        );
      });
      showErrorToast(context, 'Could not load the shop. Please try again.');
    }
  }

  /// Best-effort load of the powerup store + inventory. Any failure (e.g. an
  /// older backend without these endpoints) leaves the powerup sections empty
  /// and hidden — it never breaks the cosmetics shop.
  Future<void> _loadPowerups(String token) async {
    try {
      final results = await Future.wait([
        _backendApiService.fetchPowerupShopCatalog(identityToken: token),
        _backendApiService.fetchPowerupInventory(identityToken: token),
      ]);
      final storeItems =
          (results[0]['items'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final inventoryItems =
          (results[1]['items'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];

      final inventory = <String, int>{};
      for (final row in inventoryItems) {
        final type = row['powerupType'] as String?;
        final qty = (row['quantity'] as num?)?.toInt() ?? 0;
        if (type != null && qty > 0) inventory[type] = qty;
      }

      _powerupStoreItems = storeItems;
      _powerupInventory = inventory;
      _powerupsAvailable = true;
    } catch (_) {
      _powerupStoreItems = const [];
      _powerupInventory = const {};
      _powerupsAvailable = false;
    }
  }

  Future<void> _purchase(Map<String, dynamic> item) async {
    if (_saving) return;

    final token = widget.authService.authToken;
    final itemId = item['id'] as String?;
    if (token == null || token.isEmpty || itemId == null) return;

    setState(() => _saving = true);
    try {
      final result = await _backendApiService.purchaseShopItem(
        identityToken: token,
        itemId: itemId,
        idempotencyKey:
            '${widget.authService.userId ?? 'user'}-${DateTime.now().microsecondsSinceEpoch}',
      );
      final coins = result['coins'] as int?;
      if (coins != null) {
        await widget.authService.updateCoins(coins);
      }
      await _loadCatalog();
      if (mounted) {
        showInfoToast(context, '${item['name'] ?? 'Accessory'} unlocked.');
      }
    } on ApiException catch (error) {
      if (mounted) showErrorToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Could not buy this accessory. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _purchasePowerup(Map<String, dynamic> item) async {
    if (_saving) return;

    final token = widget.authService.authToken;
    final sku = item['sku'] as String?;
    if (token == null || token.isEmpty || sku == null) return;

    setState(() => _saving = true);
    try {
      final result = await _backendApiService.purchasePowerupItem(
        identityToken: token,
        sku: sku,
        idempotencyKey:
            '${widget.authService.userId ?? 'user'}-pw-${DateTime.now().microsecondsSinceEpoch}',
      );
      final coins = result['coins'] as int?;
      if (coins != null) {
        await widget.authService.updateCoins(coins);
      }
      await _loadCatalog();
      if (mounted) {
        showInfoToast(context, '${item['name'] ?? 'Powerup'} purchased.');
      }
    } on ApiException catch (error) {
      if (mounted) showErrorToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Could not buy this powerup. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _equip(String slot, String? itemId) async {
    if (_saving) return;

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _backendApiService.equipAccessory(
        identityToken: token,
        slot: slot,
        itemId: itemId,
      );
      await _loadCatalog();
    } on ApiException catch (error) {
      if (mounted) showErrorToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Could not update your outfit. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final showBackButton = Navigator.canPop(context);
    final tabBarHeight = showBackButton ? bottomInset : 77.5 + bottomInset;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight),
            child: RefreshIndicator(
              onRefresh: _loadCatalog,
              color: AppColors.accent,
              backgroundColor: AppColors.parchment,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeader(showBackButton: showBackButton),
                  ),
                  SliverToBoxAdapter(child: _buildBody()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool showBackButton}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showBackButton) ...[
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.parchment,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'SHOP',
                      style: PixelText.title(
                        size: 30,
                        color: AppColors.parchment,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ),
                  CoinBalanceBadge(
                    coins: widget.authService.coins,
                    // "+" = earn more coins -> invite friends (referral).
                    onAddTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReferralScreen(
                          authService: widget.authService,
                          backendApiService: _backendApiService,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Spend coins on gear and powerups. Earn more by walking and racing.',
                style: PixelText.body(
                  size: 15,
                  color: AppColors.parchment.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 12),
              _buildSegmentControl(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentControl() {
    Widget segment(String label, _ShopSection section) {
      final selected = _section == section;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _section = section),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.parchment : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: PixelText.title(
                size: 13,
                color: selected ? AppColors.textDark : AppColors.parchment,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          segment('STORE', _ShopSection.store),
          const SizedBox(width: 3),
          segment('INVENTORY', _ShopSection.inventory),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final state = _catalogState;
    if (state.shouldShowInitialLoading || (_loading && _catalog == null)) {
      return const ColoredBox(
        color: AppColors.parchment,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: ListSkeleton(itemCount: 3),
        ),
      );
    }

    if (state.isError && !state.hasData) {
      return ColoredBox(
        color: AppColors.parchment,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: LoadErrorPanel(
            title: 'Couldn’t load the shop',
            message: state.error ?? 'Check your connection and try again.',
            onRetry: _loadCatalog,
          ),
        ),
      );
    }

    final items =
        (state.data?['items'] as List?)?.cast<Map<String, dynamic>>() ??
        (_catalog?['items'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return ColoredBox(
      color: AppColors.parchment,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isRefreshing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),
            if (_section == _ShopSection.store)
              ..._buildStore(items)
            else
              ..._buildInventory(items),
          ],
        ),
      ),
    );
  }

  // ── STORE: unowned cosmetics + re-buyable powerups ─────────────────────────
  List<Widget> _buildStore(List<Map<String, dynamic>> items) {
    final unownedCosmetics =
        items.where((i) => i['owned'] != true).toList();

    return [
      if (_powerupsAvailable && _powerupStoreItems.isNotEmpty) ...[
        _buildSectionHeader('POWERUPS'),
        for (int i = 0; i < _powerupStoreItems.length; i++)
          _PowerupStoreRow(
            item: _powerupStoreItems[i],
            index: i,
            ownedQuantity: _ownedQuantityFor(_powerupStoreItems[i]),
            saving: _saving,
            onBuy: () => _purchasePowerup(_powerupStoreItems[i]),
          ),
      ],
      _buildSectionHeader('ACCESSORIES'),
      if (unownedCosmetics.isEmpty)
        _buildEmptyState(
          icon: Icons.checkroom_rounded,
          message: 'You own all the gear! Check your Inventory.',
        )
      else
        for (int i = 0; i < unownedCosmetics.length; i++)
          _ShopItemRow(
            item: unownedCosmetics[i],
            index: i,
            saving: _saving,
            onBuy: () => _purchase(unownedCosmetics[i]),
            onEquip: () {},
            onClear: () {},
          ),
    ];
  }

  // ── INVENTORY: owned cosmetics + owned powerups ────────────────────────────
  List<Widget> _buildInventory(List<Map<String, dynamic>> items) {
    final ownedCosmetics = items.where((i) => i['owned'] == true).toList();
    final ownedPowerups = _powerupInventory.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return [
      if (ownedPowerups.isNotEmpty) ...[
        _buildSectionHeader('POWERUPS'),
        for (int i = 0; i < ownedPowerups.length; i++)
          _OwnedPowerupRow(
            powerupType: ownedPowerups[i].key,
            quantity: ownedPowerups[i].value,
            index: i,
          ),
      ],
      _buildSectionHeader('ACCESSORIES'),
      if (ownedCosmetics.isEmpty)
        _buildEmptyState(
          icon: Icons.inventory_2_rounded,
          message: 'No gear yet — buy some from the Store.',
        )
      else
        for (int i = 0; i < ownedCosmetics.length; i++)
          _ShopItemRow(
            item: ownedCosmetics[i],
            index: i,
            saving: _saving,
            onBuy: () {},
            onEquip: () => _equip(
              ownedCosmetics[i]['slot'] as String? ?? '',
              ownedCosmetics[i]['id'] as String?,
            ),
            onClear: () =>
                _equip(ownedCosmetics[i]['slot'] as String? ?? '', null),
          ),
    ];
  }

  int _ownedQuantityFor(Map<String, dynamic> item) {
    final fromInventory = _powerupInventory[item['powerupType'] as String?];
    if (fromInventory != null) return fromInventory;
    return (item['ownedQuantity'] as num?)?.toInt() ?? 0;
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.parchmentBorder.withValues(alpha: 0.72),
          ),
        ),
      ),
      child: Text(
        title,
        style: PixelText.title(
          size: 16,
          color: AppColors.textDark,
        ).copyWith(shadows: _textShadows),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: AppColors.textMid.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: PixelText.body(size: 14, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.item,
    required this.index,
    required this.saving,
    required this.onBuy,
    required this.onEquip,
    required this.onClear,
  });

  final Map<String, dynamic> item;
  final int index;
  final bool saving;
  final VoidCallback onBuy;
  final VoidCallback onEquip;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final owned = item['owned'] == true;
    final equipped = item['equipped'] == true;
    final name = item['name'] as String? ?? 'Accessory';
    final description = item['description'] as String? ?? '';
    final price = item['priceCoins'] as int? ?? 0;

    final stripeColor = index.isOdd
        ? AppColors.parchmentDark.withValues(alpha: 0.45)
        : Colors.transparent;

    return Container(
      color: stripeColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: equipped ? AppColors.accent : AppColors.parchmentBorder,
                width: equipped ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(5),
            child: Image.asset(
              'assets/images/accessories/${item['assetKey']}.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.checkroom_rounded,
                color: equipped ? AppColors.accent : AppColors.textMid,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: PixelText.title(
                          size: 15,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (equipped) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'EQUIPPED',
                          style: PixelText.title(
                            size: 9,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!owned)
            PillButton(
              label: '$price',
              icon: Icons.monetization_on_rounded,
              onPressed: saving ? null : onBuy,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            )
          else if (equipped)
            PillButton(
              label: 'CLEAR',
              icon: Icons.close_rounded,
              variant: PillButtonVariant.secondary,
              onPressed: saving ? null : onClear,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            )
          else
            PillButton(
              label: 'EQUIP',
              icon: Icons.check_rounded,
              onPressed: saving ? null : onEquip,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
        ],
      ),
    );
  }
}

/// A re-buyable powerup in the store (price + buy button + owned count).
class _PowerupStoreRow extends StatelessWidget {
  const _PowerupStoreRow({
    required this.item,
    required this.index,
    required this.ownedQuantity,
    required this.saving,
    required this.onBuy,
  });

  final Map<String, dynamic> item;
  final int index;
  final int ownedQuantity;
  final bool saving;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? 'Powerup';
    final description = item['description'] as String? ?? '';
    final price = (item['priceCoins'] as num?)?.toInt() ?? 0;
    final type = item['powerupType'] as String? ?? '';

    final stripeColor = index.isOdd
        ? AppColors.parchmentDark.withValues(alpha: 0.45)
        : Colors.transparent;

    return Container(
      color: stripeColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.parchmentBorder),
            ),
            padding: const EdgeInsets.all(7),
            child: PowerupIcon(type: type, size: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: PixelText.title(
                          size: 15,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ownedQuantity > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'OWNED x$ownedQuantity',
                          style: PixelText.title(
                            size: 9,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          PillButton(
            label: '$price',
            icon: Icons.monetization_on_rounded,
            onPressed: saving ? null : onBuy,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ],
      ),
    );
  }
}

/// An owned powerup in the inventory (icon + name + quantity badge).
class _OwnedPowerupRow extends StatelessWidget {
  const _OwnedPowerupRow({
    required this.powerupType,
    required this.quantity,
    required this.index,
  });

  final String powerupType;
  final int quantity;
  final int index;

  static const _names = {
    'IMPOSTER': 'Imposter',
    'MIRROR': 'Mirror',
    'CLEANSE': 'Cleanse',
  };

  @override
  Widget build(BuildContext context) {
    final name = _names[powerupType] ?? powerupType;
    final stripeColor = index.isOdd
        ? AppColors.parchmentDark.withValues(alpha: 0.45)
        : Colors.transparent;

    return Container(
      color: stripeColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.parchmentBorder),
            ),
            padding: const EdgeInsets.all(7),
            child: PowerupIcon(type: powerupType, size: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: PixelText.title(size: 15, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.parchmentBorder),
            ),
            child: Text(
              'x$quantity',
              style: PixelText.title(size: 13, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
