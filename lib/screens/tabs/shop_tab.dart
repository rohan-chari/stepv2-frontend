import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/animals.dart';
import '../../models/loadable.dart';
import '../../services/ad_service.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/remote_asset_cache.dart';
import '../../styles.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../widgets/accessory_thumbnail.dart';
import '../../widgets/arcade_fx.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_glyph.dart';
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

/// The watch-ads-to-unlock rules (spec §7 / contract §4.3).
///
/// The server owns these numbers so they can be retuned without an App Store
/// cycle. [legacy] reproduces exactly what shipped binaries compile in, and is
/// what we fall back to when the backend is older than the `adUnlock` block —
/// a missing block must never change today's behaviour.
class _AdUnlockConfig {
  const _AdUnlockConfig({
    required this.maxShortfall,
    required this.coinsPerAd,
    required this.maxAds,
    required this.remainingToday,
  });

  final int maxShortfall;
  final int coinsPerAd;
  final int maxAds;

  /// Ad unlocks left today. `null` means the backend didn't say — treat that as
  /// "allowed" so an older backend keeps working; only an explicit `0` hides
  /// the button, which is what makes us fail BEFORE the ad rather than after.
  final int? remainingToday;

  static const legacy = _AdUnlockConfig(
    maxShortfall: 150,
    coinsPerAd: 50,
    maxAds: 3,
    remainingToday: null,
  );

  bool get hasUnlockLeft => remainingToday == null || remainingToday! > 0;

  /// Reads the block defensively: any missing or non-numeric field falls back
  /// to its legacy value rather than zeroing the flow out.
  static _AdUnlockConfig fromJson(Object? raw) {
    if (raw is! Map) return legacy;
    int intOr(String key, int fallback) {
      final value = raw[key];
      final parsed = value is num ? value.toInt() : null;
      return parsed != null && parsed > 0 ? parsed : fallback;
    }

    final remainingRaw = raw['remainingToday'];
    return _AdUnlockConfig(
      maxShortfall: intOr('maxShortfall', legacy.maxShortfall),
      coinsPerAd: intOr('coinsPerAd', legacy.coinsPerAd),
      maxAds: intOr('maxAds', legacy.maxAds),
      remainingToday: remainingRaw is num ? remainingRaw.toInt() : null,
    );
  }
}

/// How the tile should offer an unaffordable item.
enum _AffordRoute { affordable, watchAds, getCoins }

enum _ShopSection { store, inventory }

/// Where a [_ShopTile]'s chip sits over the art.
enum _TileBadgeAlignment { right, center }

enum _ShopCategory { powerups, characters, accessories }

extension on _ShopCategory {
  String get label => switch (this) {
    _ShopCategory.powerups => 'POWERUPS',
    _ShopCategory.characters => 'CHARACTERS',
    _ShopCategory.accessories => 'ACCESSORIES',
  };
}

/// Powerup store sub-filter (item 9). Matches the additive `category` field on
/// each catalog item; an older backend that omits it defaults every item to
/// `utility` (see `_powerupCategoryOf`), so ALL/UTILITY still show everything.
enum _PowerupFilter { all, offense, defense, utility }

extension on _PowerupFilter {
  String get label => switch (this) {
    _PowerupFilter.all => 'ALL',
    _PowerupFilter.offense => 'OFFENSE',
    _PowerupFilter.defense => 'DEFENSE',
    _PowerupFilter.utility => 'UTILITY',
  };

  /// Sentence-case name for the item-1 sheet and the collapsed summary. The
  /// SHOUTING [label] belonged to the pills that no longer exist.
  String get title => switch (this) {
    _PowerupFilter.all => 'All',
    _PowerupFilter.offense => 'Offense',
    _PowerupFilter.defense => 'Defense',
    _PowerupFilter.utility => 'Utility',
  };

  /// The `category` value this filter keeps; null = keep everything.
  String? get category => switch (this) {
    _PowerupFilter.all => null,
    _PowerupFilter.offense => 'offense',
    _PowerupFilter.defense => 'defense',
    _PowerupFilter.utility => 'utility',
  };
}

/// Powerup store sort order (item 9). Default is [nameAsc].
enum _PowerupSort { nameAsc, priceAsc, priceDesc }

extension on _PowerupSort {
  // The long `label` form belonged to the old `Sort: …` pill that item 1
  // replaced; the sheet and the collapsed summary both use `title`/`detail`.

  /// Short form for the item-1 sheet rows and the collapsed summary, which has
  /// to survive a 320dp phone alongside the filter name.
  String get title => switch (this) {
    _PowerupSort.nameAsc => 'Name A–Z',
    _PowerupSort.priceAsc => 'Price ↑',
    _PowerupSort.priceDesc => 'Price ↓',
  };

  /// The full sentence shown under the short title in the sheet, so "Price ↑"
  /// never has to be guessed at.
  String get detail => switch (this) {
    _PowerupSort.nameAsc => 'Alphabetical',
    _PowerupSort.priceAsc => 'Cheapest first',
    _PowerupSort.priceDesc => 'Priciest first',
  };
}

class ShopTab extends StatefulWidget {
  const ShopTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.onShopChanged,
    this.adControllerBuilder,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final ValueChanged<Map<String, dynamic>>? onShopChanged;

  /// Builds a fresh rewarded-ad controller for the powerup-unlock flow (item
  /// 10). Overridable in tests; defaults to a real [AdService] pointed at the
  /// powerup-unlock ad unit (falling back to the extra-spin/test unit).
  final ExtraSpinAdController Function()? adControllerBuilder;

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

  // Powerup store sub-filter + sort (item 9). Persisted in screen state.
  _PowerupFilter _powerupFilter = _PowerupFilter.all;
  _PowerupSort _powerupSort = _PowerupSort.nameAsc;

  // Ad-unlock rules. The server serves them in the catalog's `adUnlock` block
  // (contract §4.3); when it is absent — an older backend — we keep the
  // compiled-in legacy behaviour byte for byte.
  _AdUnlockConfig _adUnlock = _AdUnlockConfig.legacy;

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

      // The ad-unlock rules ride on either catalog (contract §4.3). Prefer the
      // powerup store's copy when it carried one, else the cosmetics catalog's,
      // else the legacy compiled-in rules.
      _adUnlock = _powerupAdUnlockBlock != null
          ? _AdUnlockConfig.fromJson(_powerupAdUnlockBlock)
          : _AdUnlockConfig.fromJson(catalog['adUnlock']);

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
      final adUnlock = results[0]['adUnlock'];
      _powerupAdUnlockBlock = adUnlock is Map ? adUnlock : null;
    } catch (_) {
      _powerupStoreItems = const [];
      _powerupInventory = const {};
      _powerupsAvailable = false;
      _powerupAdUnlockBlock = null;
    }
  }

  /// The raw `adUnlock` block from the powerup store catalog, or null when the
  /// backend didn't serve one.
  Map<dynamic, dynamic>? _powerupAdUnlockBlock;

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
      if (mounted) {
        showErrorToast(context, error.message);
      }
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

  String _equipErrorMessage(ApiException error) {
    // ACCESSORY_CONFLICT is additive: frozen backends and all existing
    // failures still retain their original server-provided copy. A malformed
    // newer error payload gets a useful message instead of a blank toast.
    if (error.code == 'ACCESSORY_CONFLICT' && error.message.trim().isEmpty) {
      return 'That accessory conflicts with your current outfit.';
    }
    return error.message;
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
      if (mounted) showErrorToast(context, _equipErrorMessage(error));
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
            child: AppRefreshIndicator(
              onRefresh: _loadCatalog,
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
      decoration: BoxDecoration(color: AppColors.of(context).roofLight),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
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
              // Powerup-store filter + sort live in the (fixed) header so they
              // don't disturb the body's stagger-in tile list.
              if (_section == _ShopSection.store &&
                  _activeCategory == _ShopCategory.powerups) ...[
                // Batch 2026-08-09 item 3: was 2px — visibly cramped against
                // the 8px gap above the pills. The two header gaps now match.
                const SizedBox(height: 8),
                _buildPowerupControls(),
              ],
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
                    : AppColors.of(context).textLight,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('shop-segment-control'),
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
      key: const Key('shop-category-pills'),
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
      key: Key('shop-category-${category.label}'),
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
                : AppColors.of(context).textLight.withValues(alpha: 0.88),
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
      // Explicit constraints pin the sheet edge-to-edge; without them the M3
      // defaults float it as an inset card, unlike every other sheet here.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
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
                      // textAccent, not accent: identical in daylight, but the
                      // night palette keeps textAccent legible on parchment
                      // where the night accent green sinks into it.
                      _sheetChip(badge, AppColors.of(context).textAccent),
                  ],
                ),
              ],
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: PixelText.body(
                    size: 15,
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
      child: Text(label, style: PixelText.title(size: 11, color: color)),
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
            // A CHARACTER the binary doesn't bundle resolves from the CDN
            // manifest's `characters` section, not `accessories`.
            remoteKind: RemoteAssetKind.characters,
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

  /// The equipped CHARACTER's assetKey, or null for the default capybara.
  ///
  /// The backend serializes `equipped[slot]` as an OBJECT
  /// (`shopCosmetics.js` `serializeEquippedAccessory`), never a String. Reading
  /// it as `String?` threw a `TypeError` during build and blanked the
  /// CHARACTERS inventory page the moment a corgi/turtle was equipped
  /// (batch 2026-07-27 item 21).
  ///
  /// Deliberately total: any shape the backend might send — a future scalar, a
  /// malformed row, an absent key — resolves to "no character equipped" rather
  /// than throwing. The backend may be a different version than this build.
  String? _equippedCharacterAssetKey() {
    final row = (_catalog?['equipped'] as Map?)?['CHARACTER'];
    if (row is Map) return row['assetKey'] as String?;
    if (row is String) return row; // defensive: never emitted today
    return null;
  }

  /// Item 6 — the always-present Capybara tile at the head of Inventory →
  /// CHARACTERS.
  ///
  /// Purely local. "Equipped" means the backend's `equipped['CHARACTER']` is
  /// null, which is exactly how the backend itself reads capybara
  /// (`isCapybara` = no CHARACTER row), so this can never disagree with the
  /// server. EQUIP is the existing `_equip('CHARACTER', null)` clear call — no
  /// new endpoint, no fake catalog row, safe on every backend version.
  Widget _capybaraInventoryTile() {
    final equipped = _equippedCharacterAssetKey() == null;
    final sprite = animalSpriteFor(kDefaultAnimal);
    Widget art({double iconSize = 30}) => AccessoryThumbnail(
      assetKey: kDefaultAnimal,
      assetPath: sprite.asset,
      animationFrames: sprite.frameCount,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.pets_rounded,
        size: iconSize,
        color: equipped
            ? AppColors.of(context).accent
            : AppColors.of(context).textMid,
      ),
    );
    void doEquip() => _equip('CHARACTER', null);

    return _ShopTile(
      key: const Key('shop-capybara-tile'),
      art: art(),
      name: 'Capybara',
      badge: equipped ? 'EQUIPPED' : null,
      badgeAlignment: _TileBadgeAlignment.center,
      highlighted: equipped,
      // No CLEAR: clearing the capybara has no meaning — it IS the cleared
      // state. An equipped capybara's strip is inert, like an owned powerup's.
      stripLabel: equipped ? 'EQUIPPED' : 'EQUIP',
      stripIcon: Icons.check_rounded,
      stripEnabled: !equipped && !_saving,
      onStrip: equipped ? null : doEquip,
      onTap: () => _showItemSheet(
        art: art(iconSize: 48),
        name: 'Capybara',
        slotLabel: _slotLabels['CHARACTER'],
        badge: equipped ? 'EQUIPPED' : null,
        description:
            'The original. Steady, sociable, and always in your corner. '
            'Capybaras top each other up with bonus steps every day.',
        actions: [
          if (!equipped)
            PillButton(
              label: 'EQUIP',
              icon: Icons.check_rounded,
              variant: PillButtonVariant.primary,
              fontSize: 14,
              fullWidth: true,
              onPressed: _saving
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      doEquip();
                    },
            ),
        ],
      ),
    );
  }

  /// STORE tile for a cosmetic/character: art + name + gold price strip.
  ///
  /// The price strip opens the detail sheet, same as the tile body — a user
  /// mis-tapped the strip while reading descriptions and was instantly
  /// charged. The sheet's BUY button is the only purchase path.
  Widget _storeCosmeticTile(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Accessory';
    final price = item['priceCoins'] as int? ?? 0;
    // Cosmetics get the same watch-ads top-up powerups have (spec §7), driven
    // by the same server-served rules.
    final route = _routeFor(price);
    final adsNeeded = _adsNeededFor(price);
    void openSheet() => _showItemSheet(
      art: _cosmeticArt(item, iconSize: 48),
      name: name,
      slotLabel: _slotLabels[item['slot']],
      description: item['description'] as String? ?? '',
      actions: [
        ?_adUnlockCapNotice(price),
        switch (route) {
          _AffordRoute.affordable => PillButton(
            label: 'BUY · $price',
            leading: const CoinGlyph(size: 16),
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
          _AffordRoute.watchAds => PillButton(
            label: adsNeeded == 1
                ? 'WATCH 1 AD TO UNLOCK'
                : 'WATCH $adsNeeded ADS TO UNLOCK',
            icon: Icons.smart_display_rounded,
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop();
                    _unlockCosmeticWithAds(item, adsNeeded);
                  },
          ),
          _AffordRoute.getCoins => PillButton(
            label: 'GET MORE COINS',
            icon: Icons.add_circle_rounded,
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            onPressed: () {
              Navigator.of(context).pop();
              _openGetCoins();
            },
          ),
        },
      ],
    );
    return _ShopTile(
      art: _cosmeticArt(item),
      name: name,
      // Item 23 — the strip is the PRICE, in every affordability state. It
      // stopped advertising the action ("Get coins" / "Watch 2 ads"), which is
      // what pushed the number off the tile and needed a second price chip
      // over the art to put it back. One number, one place. The sheet still
      // carries the route-specific CTA, and the tile opens it either way.
      stripLabel: '$price',
      stripLeading: const CoinGlyph(),
      stripEnabled: !_saving,
      onStrip: openSheet,
      onTap: openSheet,
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
      badgeAlignment: _TileBadgeAlignment.center,
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
  ///
  /// Same as the cosmetic tile: the price strip opens the detail sheet, and
  /// only the sheet's BUY button purchases.
  // ── Item 9: powerup store filter + sort ────────────────────────────────
  /// The category bucket for a powerup item. An older backend without the
  /// additive `category` field defaults to `utility` so the item still shows
  /// under ALL and UTILITY rather than disappearing.
  String _powerupCategoryOf(Map<String, dynamic> item) {
    final c = (item['category'] as String?)?.toLowerCase();
    if (c == 'offense' || c == 'defense' || c == 'utility') return c!;
    return 'utility';
  }

  int _byName(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (a['name'] as String? ?? '').toLowerCase().compareTo(
        (b['name'] as String? ?? '').toLowerCase(),
      );

  /// The powerup store items after the active filter + sort. Never mutates
  /// `_powerupStoreItems`.
  List<Map<String, dynamic>> _visiblePowerupStoreItems() {
    final wanted = _powerupFilter.category;
    final list = _powerupStoreItems
        .where((i) => wanted == null || _powerupCategoryOf(i) == wanted)
        .toList();
    int price(Map<String, dynamic> m) =>
        (m['priceCoins'] as num?)?.toInt() ?? 0;
    switch (_powerupSort) {
      case _PowerupSort.nameAsc:
        list.sort(_byName);
      case _PowerupSort.priceAsc:
        list.sort((a, b) {
          final c = price(a).compareTo(price(b));
          return c != 0 ? c : _byName(a, b);
        });
      case _PowerupSort.priceDesc:
        list.sort((a, b) {
          final c = price(b).compareTo(price(a));
          return c != 0 ? c : _byName(a, b);
        });
    }
    return list;
  }

  // ── Item 1: ONE control for filter + sort ──────────────────────────────
  //
  // Four `Expanded` pills plus a `PopupMenuButton` labelled
  // "Sort: Price: Low→High" could never fit a 320dp phone: the pills clipped to
  // ellipsis at 10pt and the sort label had no maxLines at all, so its Row
  // overflowed. Both are now one full-width button opening a single sheet with
  // a Filter group and a Sort group. Filter/sort SEMANTICS are untouched — same
  // enums, same `_visiblePowerupStoreItems()`, same All + Name (A–Z) defaults.

  /// The collapsed summary, e.g. "Offense · Price ↑".
  String get _filterSortSummary =>
      '${_powerupFilter.title} · ${_powerupSort.title}';

  Widget _buildPowerupControls() {
    final colors = AppColors.of(context);
    return GestureDetector(
      key: const Key('shop-filter-sort-button'),
      behavior: HitTestBehavior.opaque,
      onTap: _showFilterSortSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.parchment,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.parchmentBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 15, color: colors.textMid),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _filterSortSummary,
                key: const Key('shop-filter-sort-label'),
                // The whole point of the item: this can clip, never overflow.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.body(size: 12.5, color: colors.textDark),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: colors.textMid,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterSortSheet() async {
    final colors = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.parchment,
      // Eight options plus two group headers overflow a short viewport (and any
      // viewport once the OS text scale is turned up), so the sheet is bounded
      // and scrolls rather than clipping the SORT group off the bottom.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final sheetColors = AppColors.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetColors.parchmentBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _sheetGroupLabel(sheetContext, 'FILTER'),
                for (final filter in _PowerupFilter.values)
                  _sheetOption(
                    context: sheetContext,
                    key: Key('shop-filter-option-${filter.title}'),
                    title: filter.title,
                    selected: _powerupFilter == filter,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _powerupFilter = filter);
                    },
                  ),
                const SizedBox(height: 12),
                _sheetGroupLabel(sheetContext, 'SORT'),
                for (final sort in _PowerupSort.values)
                  _sheetOption(
                    context: sheetContext,
                    key: Key('shop-sort-option-${sort.title}'),
                    title: sort.title,
                    detail: sort.detail,
                    selected: _powerupSort == sort,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _powerupSort = sort);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetGroupLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: PixelText.title(size: 11, color: AppColors.of(context).textMid),
      ),
    );
  }

  Widget _sheetOption({
    required BuildContext context,
    required Key key,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    String? detail,
  }) {
    final colors = AppColors.of(context);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.pillGold.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colors.pillGoldDark : colors.parchmentBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(size: 13, color: colors.textDark),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PixelText.body(size: 11, color: colors.textMid),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 17, color: colors.textDark),
          ],
        ),
      ),
    );
  }

  // ── Item 10: watch-ads-to-unlock / get-coins on an unaffordable tile ────

  /// Which action an item at [price] offers, entirely from the server's
  /// `adUnlock` rules (spec §7). A `remainingToday` of 0 removes the ad route
  /// altogether — the daily cap has to fail BEFORE the ad, never after it.
  _AffordRoute _routeFor(int price) {
    final shortfall = price - widget.authService.coins;
    if (shortfall <= 0) return _AffordRoute.affordable;
    if (shortfall > _adUnlock.maxShortfall) return _AffordRoute.getCoins;
    if (!_adUnlock.hasUnlockLeft) return _AffordRoute.getCoins;
    return _AffordRoute.watchAds;
  }

  int _adsNeededFor(int price) {
    if (_routeFor(price) != _AffordRoute.watchAds) return 0;
    final shortfall = price - widget.authService.coins;
    return math.max(
      1,
      math.min(_adUnlock.maxAds, (shortfall / _adUnlock.coinsPerAd).ceil()),
    );
  }

  /// A one-line explanation for the detail sheet when the ONLY reason the ad
  /// route is missing is that today's unlock is already spent. Without it the
  /// sheet silently looks like the item is simply too expensive.
  Widget? _adUnlockCapNotice(int price) {
    if (_adUnlock.hasUnlockLeft) return null;
    final shortfall = price - widget.authService.coins;
    if (shortfall <= 0 || shortfall > _adUnlock.maxShortfall) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        'You’ve used today’s ad unlock. Come back tomorrow.',
        textAlign: TextAlign.center,
        style: PixelText.body(size: 13, color: AppColors.of(context).textMid),
      ),
    );
  }

  void _openGetCoins() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GetCoinsScreen(
          authService: widget.authService,
          backendApiService: _backendApiService,
        ),
      ),
    );
  }

  ExtraSpinAdController _newAdController() =>
      widget.adControllerBuilder?.call() ??
      AdService(adUnitId: AdService.powerupUnlockAdUnitId);

  /// Watches [adsNeeded] rewarded ads back-to-back, then asks the server to
  /// unlock the powerup (which zeroes coins + grants it). The SERVER is the
  /// authority on the shortfall + ad count via SSV — this only drives the ads
  /// and calls the endpoint. Bailing on any ad aborts with no grant and no coin
  /// change. Degrades safely if ads are unsupported or the endpoint is absent.
  Future<void> _unlockPowerupWithAds(
    Map<String, dynamic> item,
    int adsNeeded,
  ) async {
    if (_saving) return;
    final token = widget.authService.authToken;
    final sku = item['sku'] as String?;
    if (token == null || token.isEmpty || sku == null || adsNeeded < 1) return;

    final controller = _newAdController();
    if (!controller.isSupported) {
      showErrorToast(context, 'Ads aren’t available on this device.');
      return;
    }

    final userId = widget.authService.userId ?? 'user';
    // SSV custom-data tag scopes each verified watch to this flow (item 10).
    final customData = 'powerup_unlock:$userId:$sku';
    final name = item['name'] as String? ?? 'Powerup';

    setState(() => _saving = true);
    try {
      for (var k = 1; k <= adsNeeded; k++) {
        if (!mounted) return;
        showInfoToast(context, 'Ad $k of $adsNeeded…');
        await controller.load(userId: userId, localDate: customData);
        if (!controller.isReady) {
          if (mounted) {
            showErrorToast(context, 'Ad didn’t load. No coins spent.');
          }
          return;
        }
        final earned = await controller.showAndAwaitReward();
        if (!earned) {
          if (mounted) {
            showErrorToast(context, 'Ad not finished. No coins spent.');
          }
          return;
        }
      }

      final result = await _backendApiService.unlockPowerupWithAds(
        identityToken: token,
        sku: sku,
        idempotencyKey:
            '${widget.authService.userId ?? 'user'}-pwunlock-${DateTime.now().microsecondsSinceEpoch}',
        localDate: _localDate(),
      );
      final coins = result['coins'] as int?;
      if (coins != null) {
        await widget.authService.updateCoins(coins);
      }
      await _loadCatalog();
      if (mounted) showInfoToast(context, '$name unlocked!');
    } on ApiException catch (error) {
      if (mounted) showErrorToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Couldn’t unlock this powerup. Please try again.',
        );
      }
    } finally {
      controller.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The device's local calendar day, so the server's once-per-day ad-unlock
  /// cap uses the user's midnight rather than UTC's (contract §4.1/§4.2).
  String _localDate() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  /// The cosmetic/character twin of [_unlockPowerupWithAds], against the
  /// sibling `POST /shop/:sku/unlock-with-ads` endpoint (contract §4.2). A
  /// backend that doesn't have it 404s; the API layer caches that as
  /// unsupported for the session and we route the user to Get-coins instead —
  /// no crash, no retry loop.
  Future<void> _unlockCosmeticWithAds(
    Map<String, dynamic> item,
    int adsNeeded,
  ) async {
    if (_saving) return;
    final token = widget.authService.authToken;
    final sku = item['sku'] as String?;
    if (token == null || token.isEmpty || sku == null || adsNeeded < 1) return;

    if (!_backendApiService.shopAdUnlockSupported) {
      _openGetCoins();
      return;
    }

    final controller = _newAdController();
    if (!controller.isSupported) {
      showErrorToast(context, 'Ads aren’t available on this device.');
      return;
    }

    final userId = widget.authService.userId ?? 'user';
    // Distinct SSV custom-data prefix from the powerup flow (contract §4.2).
    final customData = 'shop_unlock:$userId:$sku';
    final name = item['name'] as String? ?? 'Item';

    setState(() => _saving = true);
    try {
      for (var k = 1; k <= adsNeeded; k++) {
        if (!mounted) return;
        showInfoToast(context, 'Ad $k of $adsNeeded…');
        await controller.load(userId: userId, localDate: customData);
        if (!controller.isReady) {
          if (mounted) {
            showErrorToast(context, 'Ad didn’t load. No coins spent.');
          }
          return;
        }
        final earned = await controller.showAndAwaitReward();
        if (!earned) {
          if (mounted) {
            showErrorToast(context, 'Ad not finished. No coins spent.');
          }
          return;
        }
      }

      final result = await _backendApiService.unlockShopItemWithAds(
        identityToken: token,
        sku: sku,
        idempotencyKey:
            '${widget.authService.userId ?? 'user'}-shopunlock-${DateTime.now().microsecondsSinceEpoch}',
        localDate: _localDate(),
      );
      final coins = result['coins'] as int?;
      if (coins != null) {
        await widget.authService.updateCoins(coins);
      }
      await _loadCatalog();
      if (mounted) showInfoToast(context, '$name unlocked!');
    } on ApiException catch (error) {
      if (!mounted) return;
      // A 404 means this backend has no cosmetic ad-unlock at all. Say so once
      // and send the user down the coin route rather than looping on ads.
      if (error.statusCode == 404) {
        _openGetCoins();
        return;
      }
      showErrorToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Couldn’t unlock this item. Please try again.');
      }
    } finally {
      controller.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _storePowerupTile(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Powerup';
    final price = (item['priceCoins'] as num?)?.toInt() ?? 0;
    final type = item['powerupType'] as String? ?? '';
    final owned = _ownedQuantityFor(item);

    // Affordability drives the strip + sheet action (item 10). Read coins
    // defensively off the auth service.
    final coins = widget.authService.coins;
    final affordable = coins >= price;
    final route = _routeFor(price);
    final canAdUnlock = route == _AffordRoute.watchAds;
    final adsNeeded = _adsNeededFor(price);

    void openSheet() => _showItemSheet(
      art: _powerupArt(type, fallbackSize: 64),
      name: name,
      badge: owned > 0 ? 'OWNED x$owned' : null,
      description: item['description'] as String? ?? '',
      actions: [
        ?_adUnlockCapNotice(price),
        _powerupSheetAction(item, price, affordable, canAdUnlock, adsNeeded),
      ],
    );

    return _ShopTile(
      art: _powerupArt(type),
      name: name,
      badge: owned > 0 ? 'x$owned' : null,
      // Item 23 — the strip is the PRICE, always. See _storeCosmeticTile.
      stripLabel: '$price',
      stripLeading: const CoinGlyph(),
      stripEnabled: !_saving,
      onStrip: openSheet,
      onTap: openSheet,
    );
  }

  /// The primary action button for a powerup detail sheet: BUY when affordable,
  /// the scaled watch-ads unlock when within 150 coins, else a Get-coins route.
  Widget _powerupSheetAction(
    Map<String, dynamic> item,
    int price,
    bool affordable,
    bool canAdUnlock,
    int adsNeeded,
  ) {
    if (affordable) {
      return PillButton(
        label: 'BUY · $price',
        leading: const CoinGlyph(size: 16),
        variant: PillButtonVariant.secondary,
        fontSize: 14,
        fullWidth: true,
        onPressed: _saving
            ? null
            : () {
                Navigator.of(context).pop();
                _purchasePowerup(item);
              },
      );
    }
    if (canAdUnlock) {
      return PillButton(
        label: adsNeeded == 1
            ? 'WATCH 1 AD TO UNLOCK'
            : 'WATCH $adsNeeded ADS TO UNLOCK',
        icon: Icons.smart_display_rounded,
        variant: PillButtonVariant.secondary,
        fontSize: 13,
        fullWidth: true,
        onPressed: _saving
            ? null
            : () {
                Navigator.of(context).pop();
                _unlockPowerupWithAds(item, adsNeeded);
              },
      );
    }
    return PillButton(
      label: 'GET MORE COINS',
      icon: Icons.add_circle_rounded,
      variant: PillButtonVariant.secondary,
      fontSize: 14,
      fullWidth: true,
      onPressed: () {
        Navigator.of(context).pop();
        _openGetCoins();
      },
    );
  }

  /// INVENTORY tile for an owned powerup (no action, just the count).
  Widget _ownedPowerupTile(String type, int quantity) {
    // Was a local 5-entry map, so any owned powerup outside it (Hitchhike,
    // Quick Rinse, Leech, X-Ray…) rendered as its raw enum name. Reads from the
    // consolidated copy source instead — an eighth duplicate the §9.4 checklist
    // didn't enumerate.
    final name = PowerupCopy.nameFor(type);
    // The real per-powerup copy; the generic line is only the unknown-type
    // fallback (a future backend powerup this build has no copy for).
    final description = PowerupCopy.descriptionFor(type);
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
        description: description.isNotEmpty
            ? description
            : 'Use it from a race to unleash it on your rivals.',
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
        [
          for (final item in _visiblePowerupStoreItems())
            _storePowerupTile(item),
        ],
        emptyIcon: Icons.bolt_rounded,
        emptyMessage: _powerupFilter == _PowerupFilter.all
            ? 'No powerups for sale right now.'
            : 'No ${_powerupFilter.label.toLowerCase()} powerups right now.',
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
        emptyMessage: 'No powerups yet. Buy some from the Store.',
      ),
      _ShopCategory.characters => _buildCategoryBody(
        [
          // Item 6 — the capybara is the compiled-in default, not a shop item,
          // so it is never `owned` and had no tile. The only route back was the
          // CLEAR strip on whichever character you were wearing, which nobody
          // found. This synthetic tile is client-side only: no catalog row, no
          // backend call beyond the equip that already exists, so it works
          // against every backend version.
          _capybaraInventoryTile(),
          for (final item in owned.where(_isCharacter))
            _inventoryCosmeticTile(item),
        ],
        emptyIcon: Icons.pets_rounded,
        emptyMessage: 'No extra characters yet. Buy some from the Store.',
      ),
      _ShopCategory.accessories => _buildCategoryBody(
        [
          for (final item in owned.where((i) => !_isCharacter(i)))
            _inventoryCosmeticTile(item),
        ],
        emptyIcon: Icons.inventory_2_rounded,
        emptyMessage: 'No gear yet. Buy some from the Store.',
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
      // Item 7: the skeleton had drifted from the real tile — a 12 clip against
      // a 14 container, a 0.6-alpha art fill, and a 34dp name band where the
      // real one is 38. All three now match, so the grid doesn't visibly resettle
      // when the catalog lands.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Art box
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.of(context).parchmentDark,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.of(context).parchmentBorder,
                      width: 1,
                    ),
                  ),
                ),
                child: const Center(
                  child: SkeletonBox(width: 46, height: 46, radius: 8),
                ),
              ),
            ),
            // Name
            Container(
              key: const Key('shop-skeleton-name-band'),
              height: 38,
              alignment: Alignment.center,
              child: const SkeletonLine(width: 52, height: 10),
            ),
            // Price strip
            Container(
              height: 34,
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
    super.key,
    required this.art,
    required this.name,
    required this.stripLabel,
    required this.stripEnabled,
    required this.onStrip,
    required this.onTap,
    this.stripIcon,
    this.stripLeading,
    this.badge,
    this.badgeAlignment = _TileBadgeAlignment.right,
    this.highlighted = false,
  }) : assert(
         stripIcon != null || stripLeading != null,
         'the strip needs a glyph',
       );

  final Widget art;
  final String name;

  final String stripLabel;

  /// The strip's glyph. [stripLeading] wins when both are given — how a price
  /// strip shows the paw coin while EQUIP/CLEAR/xN keep their Material icons.
  final IconData? stripIcon;
  final Widget? stripLeading;
  final bool stripEnabled;
  final VoidCallback? onStrip;
  final VoidCallback onTap;

  /// Small chip over the art (EQUIPPED / xN).
  final String? badge;

  /// Where that chip sits. `xN` is a corner marker and stays top-right;
  /// EQUIPPED is a statement about the whole tile, so it is centred over the
  /// art rather than tucked into a corner.
  final _TileBadgeAlignment badgeAlignment;

  Widget _badgeChip(BuildContext context) => Container(
    key: const Key('shop-tile-badge'),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
      // `textLight`, NOT `parchment` (spec §6). `parchment` is a SURFACE
      // token — cream by day, near-black navy at night — so using it as a
      // text color painted near-black on the dark-green `roofMid` pill.
      // `textLight` is cream in both palettes, which is what the day design
      // intended. The `highlighted` branch is already correct.
      style: PixelText.title(
        size: 10,
        color: highlighted
            ? AppColors.of(context).textDark
            : AppColors.of(context).textLight,
      ),
    ),
  );

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
        // Item 7 — the "weird rectangle". The clip was 12 while the container
        // was 14, so a 2px ring of the OUTER parchment showed inside the border
        // and the art box floated free of the frame. Matching the two closes
        // the ring; the art box below then carries its own fill and edge.
        child: ClipRRect(
          key: const Key('shop-tile-clip'),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Art area
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // Item 7 — was a 0.6-alpha `parchmentDark` overlay
                      // directly above an unseparated, lighter name band, which
                      // read as a stray fill rather than an intentional frame.
                      // Now a solid theme token plus a hairline bottom rule, so
                      // the art sits in a deliberate inset window. Silhouette,
                      // shadow and grid metrics are untouched.
                      child: Container(
                        key: const Key('shop-tile-art-box'),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).parchmentDark,
                          border: Border(
                            bottom: BorderSide(
                              color: AppColors.of(context).parchmentBorder,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Center(child: art),
                        ),
                      ),
                    ),
                    if (badge != null)
                      // Item 22 — EQUIPPED is a statement about the whole
                      // tile, so it reads centred over the art. Pinning both
                      // edges gives the Center a full-width box; the xN
                      // quantity marker keeps its original top-right inset.
                      badgeAlignment == _TileBadgeAlignment.center
                          ? Positioned(
                              top: 4,
                              left: 0,
                              right: 0,
                              child: Center(child: _badgeChip(context)),
                            )
                          : Positioned(
                              top: 4,
                              right: 4,
                              child: _badgeChip(context),
                            ),
                  ],
                ),
              ),
              // Name. The box height tracks the type size (spec §8): two lines
              // of 13pt pixel type need ~38dp, and under-sizing the box is what
              // clips the second line.
              //
              // The grid is four tiles wide, so a tile is only ~68–85dp across.
              // Pinning every name at 13pt would push two-word names like
              // "Ghost Pepper" and "Signal Jammer" into an ellipsis on a 360dp
              // phone — a regression on the 11pt they fit at today. So the name
              // takes 13pt when it fits and steps down toward the old size only
              // as far as it must: short names get the bigger type, long ones
              // are never worse off than before.
              Container(
                height: 38,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _FittedTileName(
                  name: name,
                  color: AppColors.of(context).textDark,
                ),
              ),
              // Action strip
              GestureDetector(
                onTap: stripEnabled ? onStrip : null,
                child: Container(
                  height: 34,
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
                      stripLeading ??
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
                            size: 13,
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

/// The tile's item name at the largest size that still fits two lines.
///
/// Spec §8 raised the nominal name size to 13pt, but the shop grid is four
/// tiles wide (a ~68dp tile on a 320dp phone), so a fixed 13pt would ellipsise
/// names that fit today. This picks the biggest size from [_sizes] whose
/// two-line layout fits the tile, so the type gets bigger wherever there's room
/// and never smaller than what shipped.
class _FittedTileName extends StatelessWidget {
  const _FittedTileName({required this.name, required this.color});

  final String name;
  final Color color;

  /// Largest first. The floor is deliberately below the old 11pt: on the
  /// narrowest phones a long name would otherwise still ellipsise.
  static const _sizes = [13.0, 12.0, 11.0, 10.0, 9.0];

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var chosen = _sizes.last;
        for (final size in _sizes) {
          final painter = TextPainter(
            text: TextSpan(
              text: name,
              style: PixelText.title(size: size),
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            textDirection: direction,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          final fits =
              !painter.didExceedMaxLines &&
              painter.height <= constraints.maxHeight;
          painter.dispose();
          if (fits) {
            chosen = size;
            break;
          }
        }
        return Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: PixelText.title(size: chosen, color: color),
        );
      },
    );
  }
}
