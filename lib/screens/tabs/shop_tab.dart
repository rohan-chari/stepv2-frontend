import 'package:flutter/material.dart';

import '../../config/animals.dart';
import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/accessory_thumbnail.dart';
import '../../widgets/arcade_fx.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/powerup_icon.dart';
import '../../constants/powerup_copy.dart';
import '../get_coins_screen.dart';

// Powerup types hidden from this build's store even if the backend still lists
// them. Currently only IMPOSTER, disabled server-side (item #3).
const _hiddenShopPowerupTypes = {'IMPOSTER'};

enum _ShopSection { store, inventory }

enum _ShopCategory { powerups, characters, accessories }

extension on _ShopCategory {
  String get label => switch (this) {
    _ShopCategory.powerups => 'POWERUPS',
    _ShopCategory.characters => 'CHARACTERS',
    _ShopCategory.accessories => 'ACCESSORIES',
  };
}

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
  _ShopCategory _category = _ShopCategory.powerups;

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

      // Imposter is disabled on this build (item #3). The backend catalog also
      // filters it out, but guard here too so a not-yet-deployed backend can't
      // surface a purchasable-but-inert Imposter tile.
      _powerupStoreItems = storeItems
          .where(
            (item) => !_hiddenShopPowerupTypes.contains(item['powerupType']),
          )
          .toList();
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
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight),
            child: RefreshIndicator(
              onRefresh: _loadCatalog,
              color: AppColors.of(context).accent,
              backgroundColor: AppColors.of(context).parchment,
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
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofDark, width: 1),
        ),
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
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppColors.of(context).textLight,
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
                        color: AppColors.of(context).textLight,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ),
                  CoinBalanceBadge(
                    coins: widget.authService.coins,
                    // "+" = earn more coins -> the Get Coins hub (watch an
                    // ad, invite friends, daily box).
                    onAddTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GetCoinsScreen(
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
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 12),
              _buildSegmentControl(),
              const SizedBox(height: 8),
              _buildCategoryPills(),
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
              color: selected
                  ? AppColors.of(context).parchment
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: PixelText.title(
                size: 13,
                color: selected
                    ? AppColors.of(context).textDark
                    : AppColors.of(context).parchment,
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

  /// Categories offered as pills. POWERUPS drops out entirely when the
  /// powerup endpoints are missing (older backend) — the same condition that
  /// hides the powerup section today, so those users never see a dead pill.
  List<_ShopCategory> get _visibleCategories => [
    if (_powerupsAvailable) _ShopCategory.powerups,
    _ShopCategory.characters,
    _ShopCategory.accessories,
  ];

  /// The active category, coerced into the visible set. Guards the case where
  /// powerups vanish after a refresh while POWERUPS is selected.
  _ShopCategory get _activeCategory {
    final visible = _visibleCategories;
    return visible.contains(_category) ? _category : visible.first;
  }

  Widget _buildCategoryPills() {
    final visible = _visibleCategories;
    final active = _activeCategory;

    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _categoryPill(visible[i], visible[i] == active)),
        ],
      ],
    );
  }

  Widget _categoryPill(_ShopCategory category, bool selected) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _category = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).pillGold
              : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.of(context).pillGoldDark
                : Colors.black.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Text(
          category.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PixelText.title(
            size: 11,
            color: selected
                ? AppColors.of(context).textDark
                : AppColors.of(context).parchment.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final state = _catalogState;
    if (state.shouldShowInitialLoading || (_loading && _catalog == null)) {
      return const _ShopLoadingSkeleton();
    }

    if (state.isError && !state.hasData) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: LoadErrorPanel(
          title: 'Couldn’t load the shop',
          message: state.error ?? 'Check your connection and try again.',
          onRetry: _loadCatalog,
        ),
      );
    }

    final items =
        (state.data?['items'] as List?)?.cast<Map<String, dynamic>>() ??
        (_catalog?['items'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isRefreshing)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.of(context).accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_section == _ShopSection.store)
            ..._buildStore(items)
          else
            ..._buildInventory(items),
        ],
      ),
    );
  }

  /// Parchment game-piece card — same language as the other tabs.
  BoxDecoration _shopCardDecoration() {
    return BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    );
  }

  /// A Clash-style grid of item tiles for the active category. The category
  /// name lives in the pill row now, so the grid carries no header of its own.
  Widget _buildSectionGroup(List<Widget> tiles, {required int staggerIndex}) {
    return StaggerIn(
      index: staggerIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 0.66,
            children: tiles,
          ),
        ],
      ),
    );
  }

  /// Full-detail bottom sheet for a tile: big art, the COMPLETE description
  /// (tiles are too small for it), and the primary action.
  Future<void> _showItemSheet({
    required Widget art,
    required String name,
    String? slotLabel,
    String? description,
    String? badge,
    List<Widget> actions = const [],
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.of(context).parchmentDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.of(
                      context,
                    ).roofDark.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: art,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                style: PixelText.title(
                  size: 20,
                  color: AppColors.of(context).textDark,
                ),
              ),
              if (slotLabel != null || badge != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (slotLabel != null)
                      _sheetChip(slotLabel, AppColors.of(context).textMid),
                    if (slotLabel != null && badge != null)
                      const SizedBox(width: 6),
                    if (badge != null)
                      _sheetChip(badge, AppColors.of(context).accent),
                  ],
                ),
              ],
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: PixelText.body(
                    size: 14,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.title(size: 10, color: color)),
    );
  }

  static const _slotLabels = {
    'HEAD': 'HEAD',
    'FACE': 'FACE',
    'NECK': 'NECK',
    'BACK': 'BACK',
    'FEET': 'FEET',
    'CHARACTER': 'CHARACTER',
  };

  Widget _cosmeticArt(Map<String, dynamic> item, {double iconSize = 28}) {
    final assetKey = item['assetKey'] as String? ?? '';
    final isCharacter = item['slot'] == 'CHARACTER';
    final equipped = item['equipped'] == true;
    return isCharacter
        ? AccessoryThumbnail(
            assetKey: assetKey,
            assetPath: animalSpriteFor(assetKey).asset,
            animationFrames: animalSpriteFor(assetKey).frameCount,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.pets_rounded,
              size: iconSize,
              color: equipped
                  ? AppColors.of(context).accent
                  : AppColors.of(context).textMid,
            ),
          )
        : AccessoryThumbnail(
            assetKey: assetKey,
            animationFrames: AccessoryThumbnail.framesOf(item),
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.checkroom_rounded,
              size: iconSize,
              color: equipped
                  ? AppColors.of(context).accent
                  : AppColors.of(context).textMid,
            ),
          );
  }

  /// STORE tile for a cosmetic/character: art + name + gold price strip.
  Widget _storeCosmeticTile(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Accessory';
    final price = item['priceCoins'] as int? ?? 0;
    return _ShopTile(
      art: _cosmeticArt(item),
      name: name,
      stripLabel: '$price',
      stripIcon: Icons.monetization_on_rounded,
      stripEnabled: !_saving,
      onStrip: () => _purchase(item),
      onTap: () => _showItemSheet(
        art: _cosmeticArt(item, iconSize: 48),
        name: name,
        slotLabel: _slotLabels[item['slot']],
        description: item['description'] as String? ?? '',
        actions: [
          PillButton(
            label: 'BUY · $price',
            icon: Icons.monetization_on_rounded,
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop();
                    _purchase(item);
                  },
          ),
        ],
      ),
    );
  }

  /// INVENTORY tile for a cosmetic/character: art + name + EQUIP/CLEAR strip.
  Widget _inventoryCosmeticTile(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Accessory';
    final equipped = item['equipped'] == true;
    final slot = item['slot'] as String? ?? '';
    final id = item['id'] as String?;
    void doEquip() => _equip(slot, id);
    void doClear() => _equip(slot, null);
    return _ShopTile(
      art: _cosmeticArt(item),
      name: name,
      badge: equipped ? 'EQUIPPED' : null,
      highlighted: equipped,
      stripLabel: equipped ? 'CLEAR' : 'EQUIP',
      stripIcon: equipped ? Icons.close_rounded : Icons.check_rounded,
      stripEnabled: !_saving,
      onStrip: equipped ? doClear : doEquip,
      onTap: () => _showItemSheet(
        art: _cosmeticArt(item, iconSize: 48),
        name: name,
        slotLabel: _slotLabels[item['slot']],
        badge: equipped ? 'EQUIPPED' : null,
        description: item['description'] as String? ?? '',
        actions: [
          PillButton(
            label: equipped ? 'CLEAR' : 'EQUIP',
            icon: equipped ? Icons.close_rounded : Icons.check_rounded,
            variant: equipped
                ? PillButtonVariant.secondary
                : PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop();
                    (equipped ? doClear : doEquip)();
                  },
          ),
        ],
      ),
    );
  }

  /// Powerup art that fills the tile like the cosmetics do: thumb-first
  /// via AccessoryThumbnail, PowerupIcon as the unknown-type fallback.
  Widget _powerupArt(String type, {double fallbackSize = 44}) {
    final path = PowerupIcon.assetPathFor(type);
    if (path == null) return PowerupIcon(type: type, size: fallbackSize);
    return AccessoryThumbnail(
      assetKey: type,
      assetPath: path,
      errorBuilder: (context, error, stackTrace) =>
          PowerupIcon(type: type, size: fallbackSize),
    );
  }

  /// STORE tile for a re-buyable powerup.
  Widget _storePowerupTile(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Powerup';
    final price = (item['priceCoins'] as num?)?.toInt() ?? 0;
    final type = item['powerupType'] as String? ?? '';
    final owned = _ownedQuantityFor(item);
    return _ShopTile(
      art: _powerupArt(type),
      name: name,
      badge: owned > 0 ? 'x$owned' : null,
      stripLabel: '$price',
      stripIcon: Icons.monetization_on_rounded,
      stripEnabled: !_saving,
      onStrip: () => _purchasePowerup(item),
      onTap: () => _showItemSheet(
        art: _powerupArt(type, fallbackSize: 64),
        name: name,
        badge: owned > 0 ? 'OWNED x$owned' : null,
        description: item['description'] as String? ?? '',
        actions: [
          PillButton(
            label: 'BUY · $price',
            icon: Icons.monetization_on_rounded,
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop();
                    _purchasePowerup(item);
                  },
          ),
        ],
      ),
    );
  }

  /// INVENTORY tile for an owned powerup (no action, just the count).
  Widget _ownedPowerupTile(String type, int quantity) {
    // Was a local 5-entry map, so any owned powerup outside it (Hitchhike,
    // Quick Rinse, Leech, X-Ray…) rendered as its raw enum name. Reads from the
    // consolidated copy source instead — an eighth duplicate the §9.4 checklist
    // didn't enumerate.
    final name = PowerupCopy.nameFor(type);
    return _ShopTile(
      art: _powerupArt(type),
      name: name,
      badge: 'x$quantity',
      stripLabel: 'x$quantity',
      stripIcon: Icons.inventory_2_rounded,
      stripEnabled: false,
      onStrip: null,
      onTap: () => _showItemSheet(
        art: _powerupArt(type, fallbackSize: 64),
        name: name,
        badge: 'OWNED x$quantity',
        description: 'Use it from a race to unleash it on your rivals.',
      ),
    );
  }

  static bool _isCharacter(Map<String, dynamic> item) =>
      item['slot'] == 'CHARACTER';

  /// Wraps a category's tiles, falling back to an empty state so a selected
  /// pill never lands on a blank page.
  List<Widget> _buildCategoryBody(
    List<Widget> tiles, {
    required IconData emptyIcon,
    required String emptyMessage,
  }) {
    if (tiles.isEmpty) {
      return [
        StaggerIn(
          index: 0,
          child: _buildEmptyState(icon: emptyIcon, message: emptyMessage),
        ),
      ];
    }
    return [_buildSectionGroup(tiles, staggerIndex: 0)];
  }

  // ── STORE: unowned cosmetics + re-buyable powerups ─────────────────────
  List<Widget> _buildStore(List<Map<String, dynamic>> items) {
    final unowned = items.where((i) => i['owned'] != true).toList();

    return switch (_activeCategory) {
      _ShopCategory.powerups => _buildCategoryBody(
        [for (final item in _powerupStoreItems) _storePowerupTile(item)],
        emptyIcon: Icons.bolt_rounded,
        emptyMessage: 'No powerups for sale right now.',
      ),
      _ShopCategory.characters => _buildCategoryBody(
        [
          for (final item in unowned.where(_isCharacter))
            _storeCosmeticTile(item),
        ],
        emptyIcon: Icons.pets_rounded,
        emptyMessage: 'You own every character! Check your Inventory.',
      ),
      _ShopCategory.accessories => _buildCategoryBody(
        [
          for (final item in unowned.where((i) => !_isCharacter(i)))
            _storeCosmeticTile(item),
        ],
        emptyIcon: Icons.checkroom_rounded,
        emptyMessage: 'You own all the gear! Check your Inventory.',
      ),
    };
  }

  // ── INVENTORY: owned cosmetics + owned powerups ────────────────────────
  List<Widget> _buildInventory(List<Map<String, dynamic>> items) {
    final owned = items.where((i) => i['owned'] == true).toList();

    return switch (_activeCategory) {
      _ShopCategory.powerups => _buildCategoryBody(
        [
          for (final entry
              in _powerupInventory.entries.where((e) => e.value > 0).toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            _ownedPowerupTile(entry.key, entry.value),
        ],
        emptyIcon: Icons.bolt_rounded,
        emptyMessage: 'No powerups yet — buy some from the Store.',
      ),
      _ShopCategory.characters => _buildCategoryBody(
        [
          for (final item in owned.where(_isCharacter))
            _inventoryCosmeticTile(item),
        ],
        emptyIcon: Icons.pets_rounded,
        emptyMessage: 'No extra characters yet — buy some from the Store.',
      ),
      _ShopCategory.accessories => _buildCategoryBody(
        [
          for (final item in owned.where((i) => !_isCharacter(i)))
            _inventoryCosmeticTile(item),
        ],
        emptyIcon: Icons.inventory_2_rounded,
        emptyMessage: 'No gear yet — buy some from the Store.',
      ),
    };
  }

  int _ownedQuantityFor(Map<String, dynamic> item) {
    final fromInventory = _powerupInventory[item['powerupType'] as String?];
    if (fromInventory != null) return fromInventory;
    return (item['ownedQuantity'] as num?)?.toInt() ?? 0;
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: _shopCardDecoration(),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: AppColors.of(context).textMid.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textMid,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder for the store. Mirrors the real layout — titled
/// sections over a 3-column grid of tile skeletons, each tile a game-piece
/// card with the art box, name line, and price strip in the real tile's
/// proportions (childAspectRatio 0.66).
class _ShopLoadingSkeleton extends StatelessWidget {
  const _ShopLoadingSkeleton();

  Widget _tile(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Art box
            Expanded(
              child: ColoredBox(
                color: AppColors.of(
                  context,
                ).parchmentDark.withValues(alpha: 0.6),
                child: const Center(
                  child: SkeletonBox(width: 46, height: 46, radius: 8),
                ),
              ),
            ),
            // Name
            Container(
              height: 34,
              alignment: Alignment.center,
              child: const SkeletonLine(width: 52, height: 10),
            ),
            // Price strip
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.of(context).parchmentDark,
                border: Border(
                  top: BorderSide(
                    color: AppColors.of(context).parchmentBorder,
                    width: 1.5,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: const SkeletonBox(width: 46, height: 14, radius: 7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, int tileCount) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      childAspectRatio: 0.66,
      children: [for (var i = 0; i < tileCount; i++) _tile(context)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // One category is shown at a time now, so the skeleton is a single
        // grid rather than a stack of headed sections.
        child: _section(context, 8),
      ),
    );
  }
}

/// Clash-style shop tile: art-dominant game-piece card with the name and a
/// bottom action strip (price / EQUIP / quantity). Tapping the tile opens the
/// detail sheet with the full description.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.art,
    required this.name,
    required this.stripLabel,
    required this.stripIcon,
    required this.stripEnabled,
    required this.onStrip,
    required this.onTap,
    this.badge,
    this.highlighted = false,
  });

  final Widget art;
  final String name;
  final String stripLabel;
  final IconData stripIcon;
  final bool stripEnabled;
  final VoidCallback? onStrip;
  final VoidCallback onTap;

  /// Small chip over the art (EQUIPPED / xN).
  final String? badge;

  /// Gold frame for equipped items.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).parchment,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted
                ? AppColors.of(context).pillGoldDark
                : AppColors.of(context).roofDark.withValues(alpha: 0.55),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Art area
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: AppColors.of(
                          context,
                        ).parchmentDark.withValues(alpha: 0.6),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Center(child: art),
                        ),
                      ),
                    ),
                    if (badge != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: highlighted
                                ? AppColors.of(context).pillGold
                                : AppColors.of(context).roofMid,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: highlighted
                                  ? AppColors.of(context).pillGoldDark
                                  : AppColors.of(context).roofDark,
                            ),
                          ),
                          child: Text(
                            badge!,
                            style: PixelText.title(
                              size: 8,
                              color: highlighted
                                  ? AppColors.of(context).textDark
                                  : AppColors.of(context).parchment,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Name
              Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(
                    size: 11,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              // Action strip
              GestureDetector(
                onTap: stripEnabled ? onStrip : null,
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: onStrip == null
                        ? AppColors.of(context).parchmentDark
                        : AppColors.of(
                            context,
                          ).pillGold.withValues(alpha: stripEnabled ? 1 : 0.5),
                    border: Border(
                      top: BorderSide(
                        color: onStrip == null
                            ? AppColors.of(context).parchmentBorder
                            : AppColors.of(context).pillGoldDark,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        stripIcon,
                        size: 13,
                        color: onStrip == null
                            ? AppColors.of(context).textMid
                            : AppColors.of(context).pillGoldShadow,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          stripLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.title(
                            size: 12,
                            color: onStrip == null
                                ? AppColors.of(context).textMid
                                : AppColors.of(context).textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
