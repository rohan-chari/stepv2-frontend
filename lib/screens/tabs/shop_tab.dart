import '../../widgets/game_toast.dart';
import '../../models/character_wardrobe.dart';
import '../../services/character_wardrobe_controller.dart';
import '../../widgets/shop_character_card.dart';
import '../character_wardrobe_screen.dart';
import '../../widgets/shop_category_bar.dart';
import '../../services/billing_controller.dart';
import '../../models/billing.dart';
import '../../widgets/billing_scope.dart';
import '../../widgets/shop_product_grid.dart';
import '../../widgets/coin_pack_offers.dart';
import '../bara_plus_screen.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../config/animals.dart';
import '../../models/loadable.dart';
import '../../services/ad_service.dart';
import '../../services/rewarded_coins_controller.dart';
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
import '../../widgets/game_container.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/powerup_icon.dart';
import '../../constants/powerup_copy.dart';
import '../../tutorial/spotlight_overlay.dart';
import '../../services/meta_app_events_service.dart';

// Powerup types retired from Store and Inventory. Old-backend residue is
// filtered defensively; historical race Activity remains readable elsewhere.
const _hiddenPowerupInventoryTypes = {'IMPOSTER'};
const _notForSalePowerupTypes = {'IMPOSTER', 'DECOY'};

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

enum _ShopCategory { featured, powerups, characters, accessories }

const _knownEquipmentSlots = <String>{
  'HEAD',
  'FACE',
  'NECK',
  'BACK',
  'FEET',
  'CHARACTER',
};

const _defaultCharacterSelectionId = '__default_capybara__';

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

enum ShopFocus { featured, coins, membership, items }

class ShopTab extends StatefulWidget {
  const ShopTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.onShopChanged,
    this.adControllerBuilder,
    this.getCoinsAdController,
    this.rewardedCoinsController,
    this.now,
    this.forceTutorialReplay = false,
    this.isTutorialPreview = false,
    this.initialFocus = ShopFocus.featured,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final ValueChanged<Map<String, dynamic>>? onShopChanged;

  /// Builds a fresh rewarded-ad controller for the powerup-unlock flow (item
  /// 10). Overridable in tests; defaults to a real [AdService] pointed at the
  /// powerup-unlock ad unit (falling back to the extra-spin/test unit).
  final ExtraSpinAdController Function()? adControllerBuilder;
  final ExtraSpinAdController? getCoinsAdController;
  final RewardedCoinsController? rewardedCoinsController;
  final DateTime Function()? now;
  final bool forceTutorialReplay;
  final bool isTutorialPreview;
  final ShopFocus initialFocus;

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> with WidgetsBindingObserver {
  final _storeScrollController = ScrollController();
  final _coinsKey = GlobalKey();
  final _powerupsKey = GlobalKey();
  final _charactersKey = GlobalKey();
  final _featuredKey = GlobalKey();
  final _headerKey = GlobalKey();
  double _toastTop = 100;
  final List<VoidCallback> _toasts = [];
  void _showInfo(BuildContext unused, String message) =>
      _toasts.add(showInfoToast(_headerKey.currentContext ?? context, message));
  void _showError(BuildContext unused, String message) => _toasts.add(
    showErrorToast(_headerKey.currentContext ?? context, message),
  );

  bool _membershipOpen = false;
  bool _characterActivating = false;
  BuildContext? _characterMenuContext;
  BuildContext? _membershipSheetContext;
  String? _membershipUserId;
  bool _deferTutorial = false;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _backendApiService;
  late final CharacterWardrobeController _wardrobes;
  Map<String, dynamic>? _catalog;
  Loadable<Map<String, dynamic>> _catalogState = const Loadable.initial();

  // Powerup store + inventory. Read defensively: if the new endpoints are
  // missing (older backend) these stay empty and the powerup sections hide.
  List<Map<String, dynamic>> _powerupStoreItems = const [];
  Map<String, int> _powerupInventory = const {};
  bool _powerupsAvailable = false;
  bool _powerupsAvailabilityResolved = false;

  bool _loading = true;
  bool _saving = false;
  final Map<String, String> _cosmeticPurchaseKeys = {};
  Map<String, dynamic>? _purchaseOverlayItem;
  OverlayEntry? _purchaseOverlayEntry;
  final _tutorialOverlaySpaceKey = GlobalKey();
  int? _tutorialStep;
  Rect? _tutorialTarget;
  bool _tutorialDecisionScheduled = false;
  bool _tutorialCatalogReady = false;
  bool _tutorialTransitioning = false;
  _ShopSection _section = _ShopSection.store;
  _ShopCategory _category = _ShopCategory.powerups;

  // Powerup store sub-filter + sort (item 9). Persisted in screen state.
  _PowerupFilter _powerupFilter = _PowerupFilter.all;
  _PowerupSort _powerupSort = _PowerupSort.nameAsc;
  Map<String, dynamic>? _selectedCosmeticItem;

  // Async Shop work is scoped to both the signed-in identity and a mutation
  // epoch. A response from a previous account, or a read that began before an
  // accepted write, must never repaint this account's outfit.
  int _shopSessionGeneration = 0;
  int _shopStateEpoch = 0;
  int _catalogRequestGeneration = 0;
  String? _shopSessionUserId;
  String? _shopSessionToken;

  // Ad-unlock rules. The server serves them in the catalog's `adUnlock` block
  // (contract §4.3); when it is absent — an older backend — we keep the
  // compiled-in legacy behaviour byte for byte.
  _AdUnlockConfig _adUnlock = _AdUnlockConfig.legacy;
  bool _hasValidServerAdUnlock = false;
  ExtraSpinAdController? _shopAdController;
  RewardedAdContext? _shopAdContext;
  RewardedAdContext? _shopActionContext;
  final Set<ExtraSpinAdController> _activeShopAdControllers = {};
  int _shopActionGeneration = 0;

  BillingController? _billing;
  int _billingDiscount = 0;
  BuildContext? _billingItemSheetContext;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final billing = BillingScope.maybeOf(context);
    if (identical(billing, _billing)) return;
    if (_membershipOpen) _closeMembershipForIdentityChange();
    _billing?.removeListener(_billingChanged);
    _billing = billing;
    _billingDiscount = billing?.snapshot.effectiveDiscountPercent ?? 0;
    billing?.addListener(_billingChanged);
  }

  void _billingChanged() {
    if (_membershipOpen && _billing?.userId != _membershipUserId) {
      _closeMembershipForIdentityChange();
    }
    final discount = _billing?.snapshot.effectiveDiscountPercent ?? 0;
    if (discount == _billingDiscount) return;
    _billingDiscount = discount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sheetContext = _billingItemSheetContext;
      if (sheetContext != null &&
          sheetContext.mounted &&
          ModalRoute.of(sheetContext)?.isCurrent == true) {
        Navigator.of(sheetContext).pop();
      }
      _clearPurchaseOverlay();
      _selectedCosmeticItem = null;
      unawaited(
        _loadCatalog().then((_) {
          if (mounted) return _wardrobes.load();
        }),
      );
    });
  }

  void _refreshChangedShopQuote() {
    final sheet = _billingItemSheetContext;
    if (sheet != null &&
        sheet.mounted &&
        ModalRoute.of(sheet)?.isCurrent == true) {
      Navigator.of(sheet).pop();
    }
    _selectedCosmeticItem = null;
    unawaited(_loadCatalog());
  }

  String? _memberPriceCopy(Map<String, dynamic> item) {
    if (_billing == null) return null;
    final original = item['basePriceCoins'];
    final current = item['priceCoins'];
    if (original is! num || current is! num || current >= original) return null;
    return 'Bara+ price · ${current.toInt()} coins (usually ${original.toInt()})';
  }

  @override
  void initState() {
    super.initState();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _wardrobes = CharacterWardrobeController(
      api: _backendApiService,
      auth: widget.authService,
      onAppearanceChanged: (appearance) {
        _shopStateEpoch++;
        _catalogRequestGeneration++;
        final next = {...?_catalog, ...appearance};
        setState(() {
          _catalog = next;
          _catalogState = Loadable.success(next);
        });
        widget.onShopChanged?.call(next);
      },
    )..addListener(_wardrobesChanged);
    _storeScrollController.addListener(() {
      if (_deferTutorial &&
          _storeScrollController.position.userScrollDirection ==
              ScrollDirection.reverse) {
        final powerups = _powerupsKey.currentContext?.findRenderObject();
        if (powerups is RenderBox &&
            powerups.hasSize &&
            powerups.localToGlobal(Offset.zero).dy <
                MediaQuery.sizeOf(context).height - 100) {
          _deferTutorial = false;
          _maybeScheduleTutorial();
        }
      }
      if (_storeScrollController.position.userScrollDirection ==
              ScrollDirection.reverse &&
          _storeScrollController.position.extentAfter < 300) {
        _wardrobes.load(more: true);
      }
    });
    _shopSessionUserId = widget.authService.userId;
    _shopSessionToken = widget.authService.authToken;
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleShopAuthChanged);
    _deferTutorial =
        widget.initialFocus == ShopFocus.coins ||
        widget.initialFocus == ShopFocus.membership;
    _loadCatalog();
    _maybeScheduleTutorial();
    if (_deferTutorial) _focusFeatured(widget.initialFocus, rebuild: false);
    if (widget.initialFocus == ShopFocus.items && !_shouldShowTutorial) {
      _scrollToSection(_powerupsKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recordMeta(MetaConversion.shopViewed);
      if (widget.initialFocus == ShopFocus.coins) {
        _recordMeta(MetaConversion.coinOffersViewed);
      }
    });
  }

  void _recordMeta(MetaConversion event) {
    if (!mounted ||
        widget.forceTutorialReplay ||
        _shouldShowTutorial ||
        BillingScope.maybeOf(context)?.isPreview == true) {
      return;
    }
    unawaited(MetaAppEventsService.instance.log(event));
  }

  @override
  void dispose() {
    for (final dismiss in _toasts) {
      dismiss();
    }
    _toasts.clear();
    _wardrobes.removeListener(_wardrobesChanged);
    _wardrobes.dispose();
    _storeScrollController.dispose();
    _billing?.removeListener(_billingChanged);
    _shopSessionGeneration++;
    _shopStateEpoch++;
    _catalogRequestGeneration++;
    _shopActionGeneration++;
    for (final controller in _activeShopAdControllers.toList()) {
      controller.dispose();
    }
    _activeShopAdControllers.clear();
    WidgetsBinding.instance.removeObserver(this);
    widget.authService.removeListener(_handleShopAuthChanged);
    _removePurchaseOverlayEntry();
    _disposeShopAdTarget();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final context = _shopAdContext;
    if (context != null && context.localDate != _localDate()) {
      _disposeShopAdTarget();
    }
  }

  void _handleShopAuthChanged() {
    final nextUserId = widget.authService.userId;
    final nextToken = widget.authService.authToken;
    final identityChanged =
        nextUserId != _shopSessionUserId || nextToken != _shopSessionToken;
    if (!identityChanged) {
      _maybeScheduleTutorial();
      return;
    }

    if (nextUserId != _shopSessionUserId) _closeMembershipForIdentityChange();
    final menuContext = _characterMenuContext;
    _characterMenuContext = null;
    _characterActivating = false;
    if (menuContext != null && menuContext.mounted) {
      final route = ModalRoute.of(menuContext);
      if (route != null) Navigator.of(menuContext).removeRoute(route);
    }
    _cosmeticPurchaseKeys.clear();
    _shopSessionUserId = nextUserId;
    _shopSessionToken = nextToken;
    _shopSessionGeneration++;
    _shopStateEpoch++;
    _catalogRequestGeneration++;
    _shopActionGeneration++;
    if (_activeShopAdControllers.isNotEmpty) {
      for (final controller in _activeShopAdControllers.toList()) {
        controller.dispose();
      }
      _activeShopAdControllers.clear();
    }
    final context = _shopAdContext;
    if (context != null && context.userId != widget.authService.userId) {
      _disposeShopAdTarget();
    }
    _removePurchaseOverlayEntry();
    for (final dismiss in _toasts) {
      dismiss();
    }
    _toasts.clear();
    if (!mounted) return;
    setState(() {
      _catalog = null;
      _catalogState = const Loadable.initial();
      _powerupStoreItems = const [];
      _powerupInventory = const {};
      _powerupsAvailable = false;
      _powerupsAvailabilityResolved = false;
      _selectedCosmeticItem = null;
      _purchaseOverlayItem = null;
      _tutorialStep = null;
      _tutorialTarget = null;
      _tutorialDecisionScheduled = false;
      _tutorialCatalogReady = false;
      _tutorialTransitioning = false;
      _loading = true;
      _saving = false;
    });
    unawaited(_loadCatalog());
    _maybeScheduleTutorial();
  }

  void _maybeScheduleTutorial() {
    if (_deferTutorial ||
        _tutorialDecisionScheduled ||
        !_tutorialCatalogReady ||
        widget.isTutorialPreview) {
      return;
    }
    final shouldShow =
        widget.forceTutorialReplay ||
        (widget.authService.hasShopTutorialServerState &&
            widget.authService.shopTutorialCompletedAt == null);
    if (!shouldShow) return;
    _tutorialDecisionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_launchTutorialWhenReady());
    });
  }

  void _removePurchaseOverlayEntry() {
    final entry = _purchaseOverlayEntry;
    _purchaseOverlayEntry = null;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
  }

  void _showPurchaseOverlay(Map<String, dynamic> item) {
    if (!mounted) return;
    _removePurchaseOverlayEntry();
    setState(() => _purchaseOverlayItem = item);
    final entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0xA6000000)),
          ),
          Positioned.fill(child: _buildPurchaseOverlay(item, overlayContext)),
        ],
      ),
    );
    _purchaseOverlayEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _clearPurchaseOverlay() {
    _removePurchaseOverlayEntry();
    if (mounted && _purchaseOverlayItem != null) {
      setState(() => _purchaseOverlayItem = null);
      _maybeScheduleTutorial();
    }
  }

  static const _tutorialTargets = <Key>[
    Key('shop-section-featured'),
    Key('shop-character-default'),
  ];
  static const _tutorialTitles = ['EXPLORE THE SHOP', 'YOUR CHARACTERS'];
  static const _tutorialBodies = [
    'Scroll from Featured coins and Bara+ to Powerups, then Characters & Accessories. Buy and Owned live inside Powerups.',
    'Owned and locked characters share one collection. Open an owned character to edit its saved outfit or make it active.',
  ];

  Element? _elementWithKey(Key key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  bool get _shouldShowTutorial =>
      widget.forceTutorialReplay ||
      (widget.authService.hasShopTutorialServerState &&
          widget.authService.shopTutorialCompletedAt == null);

  Rect? _mountedTutorialTargetRect(Key key) {
    final target = _elementWithKey(key);
    if (target == null || !target.mounted) return null;
    final renderObject = target.renderObject;
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    final overlaySpace = _tutorialOverlaySpaceKey.currentContext
        ?.findRenderObject();
    if (overlaySpace is! RenderBox || !overlaySpace.hasSize) return null;
    // The route can still be sliding in when the catalog resolves. Measure
    // in the overlay's space so its cutout doesn't retain a screen offset.
    final rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(overlaySpace),
      Offset.zero & renderObject.size,
    );
    return rect.left.isFinite &&
            rect.top.isFinite &&
            rect.right.isFinite &&
            rect.bottom.isFinite
        ? rect
        : null;
  }

  bool get _allTutorialTargetsMounted =>
      _mountedTutorialTargetRect(_tutorialTargets.first) != null;

  Future<Rect?> _measureTutorialTarget(int step) async {
    if (!mounted || step < 0 || step >= _tutorialTargets.length) return null;
    final key = _tutorialTargets[step];
    if (step == 1 && _wardrobes.state != WardrobeLoadState.loaded) {
      await _wardrobes.load();
      if (!mounted) return null;
      await WidgetsBinding.instance.endOfFrame;
    }
    final target = _elementWithKey(key);
    if (target == null || !target.mounted) return null;
    await Scrollable.ensureVisible(
      target,
      duration: step == 0 ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: .35,
    );
    if (!mounted) return null;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    return _mountedTutorialTargetRect(key);
  }

  Future<void> _launchTutorialWhenReady() async {
    if (!mounted ||
        !_tutorialCatalogReady ||
        !_shouldShowTutorial ||
        _purchaseOverlayItem != null ||
        !_allTutorialTargetsMounted) {
      _tutorialDecisionScheduled = false;
      return;
    }
    final rect = await _measureTutorialTarget(0);
    if (!mounted ||
        rect == null ||
        !_tutorialCatalogReady ||
        !_shouldShowTutorial ||
        _purchaseOverlayItem != null) {
      _tutorialDecisionScheduled = false;
      return;
    }
    setState(() {
      _tutorialStep = 0;
      _tutorialTarget = rect;
    });
  }

  Future<void> _showTutorialStep(int step) async {
    if (_tutorialTransitioning || _tutorialStep == null) return;
    _tutorialTransitioning = true;
    final rect = await _measureTutorialTarget(step);
    if (!mounted) return;
    _tutorialTransitioning = false;
    if (rect == null || _tutorialStep == null) return;
    setState(() {
      _tutorialStep = step;
      _tutorialTarget = rect;
    });
  }

  void _advanceTutorial() {
    final step = _tutorialStep;
    if (step == null) return;
    if (step == _tutorialTargets.length - 1) {
      unawaited(_launchWardrobeTutorial());
      return;
    }
    unawaited(_showTutorialStep(step + 1));
  }

  Future<void> _launchWardrobeTutorial() async {
    final character =
        _wardrobes.characters['default'] ??
        ShopCharacter.fromJson({
          'characterKey': 'default',
          'name': 'Capybara',
          'owned': true,
          'canEdit': true,
        });
    setState(() => _tutorialStep = null);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CharacterWardrobeScreen(
          character: character,
          controller: _wardrobes,
          onBuy: (_) async => null,
          tutorial: true,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _tutorialStep = 1);
    _finishTutorial();
  }

  void _backTutorial() {
    final step = _tutorialStep;
    if (step == null || step == 0) return;
    unawaited(_showTutorialStep(step - 1));
  }

  void _finishTutorial() {
    if (_tutorialStep == null) return;
    setState(() {
      _tutorialStep = null;
      _tutorialTarget = null;
      _tutorialTransitioning = false;
    });
    if (!widget.forceTutorialReplay &&
        widget.authService.hasShopTutorialServerState) {
      unawaited(widget.authService.completeShopTutorial());
    }
  }

  bool _sessionIsCurrent({
    required int generation,
    required String? userId,
    required String token,
    int? epoch,
    int? catalogRequest,
  }) {
    return mounted &&
        generation == _shopSessionGeneration &&
        userId == _shopSessionUserId &&
        token == _shopSessionToken &&
        widget.authService.userId == userId &&
        widget.authService.authToken == token &&
        (epoch == null || epoch == _shopStateEpoch) &&
        (catalogRequest == null || catalogRequest == _catalogRequestGeneration);
  }

  Future<void> _loadCatalog() async {
    // A refresh can change or remove the server-advertised SKU eligibility.
    // Drop the speculative target before accepting the new catalog rather
    // than allowing an ad bound to the previous payload to survive it.
    _disposeShopAdTarget();
    final previous = _catalog;
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    final generation = _shopSessionGeneration;
    final epoch = _shopStateEpoch;
    final catalogRequest = ++_catalogRequestGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _catalogState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      if (token == null || token.isEmpty) {
        if (mounted &&
            generation == _shopSessionGeneration &&
            userId == _shopSessionUserId &&
            catalogRequest == _catalogRequestGeneration) {
          setState(() {
            _loading = false;
            _catalogState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      final bootstrap = await _backendApiService.fetchShopBootstrap(
        identityToken: token,
        localDate: _localDate(),
      );
      final catalog = bootstrap.cosmetics;
      if (!_isValidCosmeticsCatalog(
        catalog,
        requireCompleteItems: bootstrap.supported,
      )) {
        throw const ApiException('Could not load the shop. Please try again.');
      }
      final coins = catalog['coins'];

      var powerups = bootstrap.powerups;
      var inventory = bootstrap.inventory;
      if (!_isValidPowerupCatalog(
        powerups,
        requireOwnedQuantity: bootstrap.supported,
      )) {
        powerups = null;
      }
      if (!_isValidPowerupInventory(inventory)) inventory = null;
      if (bootstrap.supported && powerups == null) {
        try {
          powerups = await _backendApiService.fetchPowerupShopCatalog(
            identityToken: token,
          );
        } catch (_) {}
      }
      if (bootstrap.supported && inventory == null) {
        try {
          inventory = await _backendApiService.fetchPowerupInventory(
            identityToken: token,
          );
        } catch (_) {}
      }
      if (!_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: epoch,
        catalogRequest: catalogRequest,
      )) {
        return;
      }

      setState(() {
        if (powerups != null && inventory != null) {
          _applyPowerupComponents(powerups, inventory);
        } else {
          _powerupStoreItems = const [];
          _powerupInventory = const {};
          _powerupsAvailable = false;
          _powerupAdUnlockBlock = null;
        }
        _powerupsAvailabilityResolved = true;
        _catalog = catalog;
        _catalogState = Loadable.success(catalog);
        _selectedCosmeticItem = _revalidatedSelection(catalog);
        _loading = false;
        _tutorialCatalogReady = true;
        _recomputeAdUnlock();
      });
      _maybeScheduleTutorial();
      widget.onShopChanged?.call(catalog);
      final acceptedCoins = powerups?['coins'] ?? coins;
      if (acceptedCoins is num &&
          _sessionIsCurrent(
            generation: generation,
            userId: userId,
            token: token,
            epoch: epoch,
            catalogRequest: catalogRequest,
          )) {
        await widget.authService.updateCoins(acceptedCoins.toInt());
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (token == null ||
          !_sessionIsCurrent(
            generation: generation,
            userId: userId,
            token: token,
            epoch: epoch,
            catalogRequest: catalogRequest,
          )) {
        return;
      }
      setState(() {
        _loading = false;
        _catalogState = Loadable.error(error.message, data: previous);
      });
      _showError(context, error.message);
    } catch (_) {
      if (!mounted) return;
      if (token == null ||
          !_sessionIsCurrent(
            generation: generation,
            userId: userId,
            token: token,
            epoch: epoch,
            catalogRequest: catalogRequest,
          )) {
        return;
      }
      setState(() {
        _loading = false;
        _catalogState = Loadable.error(
          'Could not load the shop. Please try again.',
          data: previous,
        );
      });
      _showError(context, 'Could not load the shop. Please try again.');
    }
  }

  /// Best-effort load of the powerup store + inventory. Any failure (e.g. an
  /// older backend without these endpoints) leaves the powerup sections empty
  /// and hidden — it never breaks the cosmetics shop.
  Future<bool> _loadPowerups(
    String token, {
    required int generation,
    required String? userId,
    required int epoch,
  }) async {
    try {
      final results = await Future.wait([
        _backendApiService.fetchPowerupShopCatalog(identityToken: token),
        _backendApiService.fetchPowerupInventory(identityToken: token),
      ]);
      if (!_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: epoch,
      )) {
        return false;
      }
      _applyPowerupComponents(results[0], results[1]);
      if (_catalog case final catalog?) {
        _loading = false;
        _catalogState = Loadable.success(catalog);
      }
      final coins = results[0]['coins'];
      if (coins is num &&
          _sessionIsCurrent(
            generation: generation,
            userId: userId,
            token: token,
            epoch: epoch,
          )) {
        await widget.authService.updateCoins(coins.toInt());
      }
      return true;
    } catch (_) {
      if (!_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: epoch,
      )) {
        return false;
      }
      _powerupStoreItems = const [];
      _powerupInventory = const {};
      _powerupsAvailable = false;
      _powerupsAvailabilityResolved = true;
      _powerupAdUnlockBlock = null;
      _recomputeAdUnlock();
      return false;
    }
  }

  void _applyPowerupComponents(
    Map<String, dynamic> powerups,
    Map<String, dynamic> inventoryEnvelope,
  ) {
    final rawStore = powerups['items'];
    final storeItems = <Map<String, dynamic>>[];
    if (rawStore is List) {
      for (final raw in rawStore) {
        if (raw is! Map ||
            !_isValidPowerupItem(raw, requireOwnedQuantity: false)) {
          continue;
        }
        storeItems.add({
          for (final entry in raw.entries)
            if (entry.key is String) entry.key as String: entry.value,
        });
      }
    }
    final inventory = <String, int>{};
    final rawInventory = inventoryEnvelope['items'];
    if (rawInventory is List) {
      for (final raw in rawInventory) {
        if (raw is! Map || !_isValidInventoryItem(raw)) continue;
        final type = raw['powerupType'];
        final quantity = raw['quantity'];
        if (type is String && quantity is num && quantity.toInt() > 0) {
          if (!_hiddenPowerupInventoryTypes.contains(type)) {
            inventory[type] = quantity.toInt();
          }
        }
      }
    }
    _powerupStoreItems = storeItems
        .where((item) => !_notForSalePowerupTypes.contains(item['powerupType']))
        .toList();
    _powerupInventory = inventory;
    _powerupsAvailable = true;
    _powerupsAvailabilityResolved = true;
    final adUnlock = powerups['adUnlock'];
    _powerupAdUnlockBlock = adUnlock is Map ? adUnlock : null;
    _recomputeAdUnlock();
  }

  bool _hasItemListWhere(
    Map<String, dynamic>? component,
    bool Function(Map<dynamic, dynamic>) isValid,
  ) {
    final items = component?['items'];
    return items is List && items.every((row) => row is Map && isValid(row));
  }

  bool _isValidCosmeticItem(
    Map<dynamic, dynamic> item, {
    required bool requireCompleteFields,
  }) {
    return item['id'] is String &&
        (item['id'] as String).isNotEmpty &&
        item['sku'] is String &&
        (item['sku'] as String).isNotEmpty &&
        item['name'] is String &&
        (!requireCompleteFields || item.containsKey('description')) &&
        (!item.containsKey('description') ||
            item['description'] == null ||
            item['description'] is String) &&
        item['slot'] is String &&
        item['priceCoins'] is num &&
        item['assetKey'] is String &&
        (!requireCompleteFields || item['owned'] is bool) &&
        (!requireCompleteFields || item['equipped'] is bool);
  }

  bool _isValidPowerupItem(
    Map<dynamic, dynamic> item, {
    required bool requireOwnedQuantity,
  }) {
    return item['sku'] is String &&
        (item['sku'] as String).isNotEmpty &&
        item['name'] is String &&
        item.containsKey('description') &&
        (item['description'] == null || item['description'] is String) &&
        item['priceCoins'] is num &&
        item['powerupType'] is String &&
        (item['powerupType'] as String).isNotEmpty &&
        (!item.containsKey('category') || item['category'] is String) &&
        (!item.containsKey('ownedQuantity') || item['ownedQuantity'] is num) &&
        (!requireOwnedQuantity || item['ownedQuantity'] is num);
  }

  bool _isValidInventoryItem(Map<dynamic, dynamic> item) {
    return item['powerupType'] is String &&
        (item['powerupType'] as String).isNotEmpty &&
        item['quantity'] is num;
  }

  bool _isValidPowerupCatalog(
    Map<String, dynamic>? catalog, {
    required bool requireOwnedQuantity,
  }) {
    return catalog?['coins'] is num &&
        _hasItemListWhere(
          catalog,
          (item) => _isValidPowerupItem(
            item,
            requireOwnedQuantity: requireOwnedQuantity,
          ),
        );
  }

  bool _isValidPowerupInventory(Map<String, dynamic>? inventory) {
    return _hasItemListWhere(inventory, _isValidInventoryItem);
  }

  bool _isValidCosmeticsCatalog(
    Map<String, dynamic>? catalog, {
    required bool requireCompleteItems,
  }) {
    return catalog != null &&
        catalog['coins'] is num &&
        catalog['ownedItemIds'] is List &&
        (catalog['ownedItemIds'] as List).every((id) => id is String) &&
        catalog['equipped'] is Map &&
        _hasItemListWhere(
          catalog,
          (item) => _isValidCosmeticItem(
            item,
            requireCompleteFields: requireCompleteItems,
          ),
        );
  }

  Map<String, dynamic>? _validEquipmentRow(
    String slot, {
    Map<String, dynamic>? catalog,
  }) {
    if (!_knownEquipmentSlots.contains(slot)) return null;
    final rawEquipment = (catalog ?? _catalog)?['equipped'];
    if (rawEquipment is! Map) return null;
    final rawRow = rawEquipment[slot];
    if (rawRow is! Map) return null;
    final id = rawRow['id'];
    final rowSlot = rawRow['slot'];
    if (id is! String || id.trim().isEmpty || rowSlot != slot) return null;
    return <String, dynamic>{
      for (final entry in rawRow.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  bool _isCosmeticEquipped(
    Map<String, dynamic> item, {
    Map<String, dynamic>? catalog,
  }) {
    final id = item['id'];
    final slot = item['slot'];
    if (id is! String ||
        id.trim().isEmpty ||
        slot is! String ||
        !_knownEquipmentSlots.contains(slot)) {
      return false;
    }
    return _validEquipmentRow(slot, catalog: catalog)?['id'] == id;
  }

  bool _isCosmeticOwned(
    Map<String, dynamic> item, {
    Map<String, dynamic>? catalog,
  }) {
    if (item['owned'] == true) return true;
    final id = item['id'];
    final rawOwned = (catalog ?? _catalog)?['ownedItemIds'];
    return id is String && rawOwned is List && rawOwned.contains(id);
  }

  Map<String, dynamic>? _revalidatedSelection(Map<String, dynamic> catalog) {
    final selected = _selectedCosmeticItem;
    if (selected == null || _activeCategory == _ShopCategory.powerups) {
      return null;
    }
    if (selected['id'] == _defaultCharacterSelectionId) {
      return _section == _ShopSection.inventory &&
              _activeCategory == _ShopCategory.characters
          ? selected
          : null;
    }
    final id = selected['id'];
    if (id is! String || id.isEmpty) return null;
    for (final item in _safeShopItems(catalog['items'])) {
      if (item['id'] != id) continue;
      final character = _isCharacter(item);
      if ((_activeCategory == _ShopCategory.characters) != character) {
        return null;
      }
      final owned = _isCosmeticOwned(item, catalog: catalog);
      if ((_section == _ShopSection.inventory) != owned) return null;
      return item;
    }
    return null;
  }

  /// The raw `adUnlock` block from the powerup store catalog, or null when the
  /// backend didn't serve one.
  Map<dynamic, dynamic>? _powerupAdUnlockBlock;

  void _recomputeAdUnlock() {
    final raw = _powerupAdUnlockBlock ?? _catalog?['adUnlock'];
    _adUnlock = _AdUnlockConfig.fromJson(raw);
    _hasValidServerAdUnlock = _validAdUnlockBlock(raw);
    if (!_hasValidServerAdUnlock) _disposeShopAdTarget();
  }

  bool _validAdUnlockBlock(Object? raw) {
    if (raw is! Map) return false;
    for (final key in const ['maxShortfall', 'coinsPerAd', 'maxAds']) {
      final value = raw[key];
      if (value is! num || value.toInt() <= 0) return false;
    }
    final remaining = raw['remainingToday'];
    return remaining == null || (remaining is num && remaining.toInt() >= 0);
  }

  Future<void> _purchase(Map<String, dynamic> item) async {
    if (_saving) return;

    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    final generation = _shopSessionGeneration;
    final startedEpoch = _shopStateEpoch;
    final itemId = item['id'] as String?;
    if (token == null || token.isEmpty || itemId == null) return;

    setState(() => _saving = true);
    _showPurchaseOverlay(item);
    try {
      final result = await _backendApiService.purchaseShopItem(
        identityToken: token,
        itemId: itemId,
        expectedPriceCoins: item['priceCoins'] is num
            ? (item['priceCoins'] as num).toInt()
            : null,
        idempotencyKey: _cosmeticPurchaseKeys.putIfAbsent(
          itemId,
          () =>
              '${widget.authService.userId ?? 'user'}-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      _cosmeticPurchaseKeys.remove(itemId);
      if (!_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: startedEpoch,
      )) {
        return;
      }
      final acceptedEpoch = ++_shopStateEpoch;
      final idempotent = _isIdempotent(result);
      if (idempotent || !_patchCosmeticPurchase(result)) {
        await _refreshCosmetics(
          token,
          generation: generation,
          userId: userId,
          epoch: acceptedEpoch,
          clearSelection: true,
        );
      } else {
        final coins = result['coins'];
        if (coins is num &&
            _sessionIsCurrent(
              generation: generation,
              userId: userId,
              token: token,
              epoch: acceptedEpoch,
            )) {
          await widget.authService.updateCoins(coins.toInt());
        }
      }
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: acceptedEpoch,
      )) {
        if (!mounted) return;
        _clearPurchaseOverlay();
        _showInfo(context, '${item['name'] ?? 'Accessory'} unlocked.');
        unawaited(_wardrobes.load());
      }
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) {
        _cosmeticPurchaseKeys.remove(itemId);
      }
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(
          context,
          error.code == 'PRICE_CHANGED'
              ? 'The price changed. Please review the updated shop price.'
              : error.message,
        );
        if (error.code == 'PRICE_CHANGED') {
          _refreshChangedShopQuote();
        }
      }
    } catch (_) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(context, 'Could not buy this accessory. Please try again.');
      }
    } finally {
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        setState(() => _saving = false);
        _maybeScheduleTutorial();
      }
    }
  }

  Future<void> _purchasePowerup(Map<String, dynamic> item) async {
    if (_saving) return;

    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    final generation = _shopSessionGeneration;
    final startedEpoch = _shopStateEpoch;
    final sku = item['sku'] as String?;
    if (token == null || token.isEmpty || sku == null) return;

    setState(() => _saving = true);
    _showPurchaseOverlay(item);
    try {
      final result = await _backendApiService.purchasePowerupItem(
        identityToken: token,
        sku: sku,
        expectedPriceCoins: item['priceCoins'] is num
            ? (item['priceCoins'] as num).toInt()
            : null,
        idempotencyKey:
            '${widget.authService.userId ?? 'user'}-pw-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: startedEpoch,
      )) {
        return;
      }
      final acceptedEpoch = ++_shopStateEpoch;
      final idempotent = _isIdempotent(result);
      if (idempotent || !_patchPowerupMutation(result, item)) {
        await _loadPowerups(
          token,
          generation: generation,
          userId: userId,
          epoch: acceptedEpoch,
        );
      } else {
        final coins = result['coins'];
        if (coins is num &&
            _sessionIsCurrent(
              generation: generation,
              userId: userId,
              token: token,
              epoch: acceptedEpoch,
            )) {
          await widget.authService.updateCoins(coins.toInt());
        }
      }
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
        epoch: acceptedEpoch,
      )) {
        _clearPurchaseOverlay();
        _showInfo(context, '${item['name'] ?? 'Powerup'} purchased.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(
          context,
          error.code == 'PRICE_CHANGED'
              ? 'The price changed. Please review the updated shop price.'
              : error.message,
        );
        if (error.code == 'PRICE_CHANGED') _refreshChangedShopQuote();
      }
    } catch (_) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(context, 'Could not buy this powerup. Please try again.');
      }
    } finally {
      if (_sessionIsCurrent(
        generation: generation,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        setState(() => _saving = false);
        _maybeScheduleTutorial();
      }
    }
  }

  bool _isIdempotent(Map<String, dynamic> result) {
    final purchase = result['purchase'];
    return result['idempotent'] == true ||
        (purchase is Map && purchase['idempotent'] == true);
  }

  Future<bool> _refreshCosmetics(
    String token, {
    required int generation,
    required String? userId,
    required int epoch,
    required bool clearSelection,
  }) async {
    final catalog = await _backendApiService.fetchShopCatalog(
      identityToken: token,
    );
    if (!_isValidCosmeticsCatalog(catalog, requireCompleteItems: false)) {
      throw const ApiException('Could not refresh the shop. Please try again.');
    }
    if (!_sessionIsCurrent(
      generation: generation,
      userId: userId,
      token: token,
      epoch: epoch,
    )) {
      return false;
    }
    final coins = catalog['coins'];
    final adUnlock = catalog['adUnlock'];
    if (adUnlock is Map) _powerupAdUnlockBlock = adUnlock;
    setState(() {
      _catalog = catalog;
      _catalogState = Loadable.success(catalog);
      _selectedCosmeticItem = clearSelection
          ? null
          : _revalidatedSelection(catalog);
      _recomputeAdUnlock();
    });
    widget.onShopChanged?.call(catalog);
    if (coins is num &&
        _sessionIsCurrent(
          generation: generation,
          userId: userId,
          token: token,
          epoch: epoch,
        )) {
      await widget.authService.updateCoins(coins.toInt());
    }
    return true;
  }

  bool _patchCosmeticPurchase(Map<String, dynamic> result) {
    final current = _catalog;
    final rawItem = result['item'];
    final coins = result['coins'];
    if (current == null || rawItem is! Map || coins is! num) return false;
    final item = <String, dynamic>{
      for (final entry in rawItem.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (!_isValidCosmeticItem(item, requireCompleteFields: true)) return false;
    final itemId = item['id'];
    if (itemId is! String || itemId.isEmpty) return false;
    final items = _safeShopItems(current['items']);
    final index = items.indexWhere((row) => row['id'] == itemId);
    if (index == -1) {
      items.add(item);
    } else {
      items[index] = item;
    }
    final owned = current['ownedItemIds'] is List
        ? (current['ownedItemIds'] as List).whereType<String>().toSet()
        : <String>{};
    owned.add(itemId);
    final next = {
      ...current,
      'coins': coins.toInt(),
      'items': items,
      'ownedItemIds': owned.toList(growable: false),
      if (result['adUnlock'] is Map) 'adUnlock': result['adUnlock'],
    };
    final adUnlock = result['adUnlock'];
    if (adUnlock is Map) _powerupAdUnlockBlock = adUnlock;
    setState(() {
      _catalog = next;
      _catalogState = Loadable.success(next);
      _selectedCosmeticItem = null;
      _loading = false;
      _recomputeAdUnlock();
    });
    widget.onShopChanged?.call(next);
    return true;
  }

  List<Map<String, dynamic>> _safeShopItems(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return [
      for (final row in raw)
        if (row is Map)
          <String, dynamic>{
            for (final entry in row.entries)
              if (entry.key is String) entry.key as String: entry.value,
          },
    ];
  }

  bool _patchPowerupMutation(
    Map<String, dynamic> result,
    Map<String, dynamic> storeItem,
  ) {
    final coins = result['coins'];
    final rawInventory = result['inventory'];
    final powerupType = storeItem['powerupType'];
    if (coins is! num || rawInventory is! Map || powerupType is! String) {
      return false;
    }
    final quantity = rawInventory['quantity'];
    if (quantity is! num ||
        rawInventory['powerupType'] != powerupType ||
        !mounted) {
      return false;
    }
    _powerupInventory = {..._powerupInventory, powerupType: quantity.toInt()};
    _powerupStoreItems = [
      for (final row in _powerupStoreItems)
        if (row['powerupType'] == powerupType)
          {...row, 'ownedQuantity': quantity.toInt()}
        else
          row,
    ];
    final adUnlock = result['adUnlock'];
    if (adUnlock is Map) _powerupAdUnlockBlock = adUnlock;
    setState(() {
      if (_catalog case final catalog?) {
        _loading = false;
        _catalogState = Loadable.success(catalog);
      }
      _recomputeAdUnlock();
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _headerKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final top = box.localToGlobal(Offset(0, box.size.height)).dy + 8;
        if ((top - _toastTop).abs() > .5) setState(() => _toastTop = top);
      }
    });
    return GameToastAnchor(
      top: _toastTop,
      child: PopScope(
        canPop: _purchaseOverlayItem == null,
        child: Stack(
          key: _tutorialOverlaySpaceKey,
          children: [
            Scaffold(
              backgroundColor: AppColors.of(context).roofLight,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ArcadeCheckerPainter(drawBottomStripe: false),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: topInset + 14),
                    child: Column(
                      children: [
                        KeyedSubtree(
                          key: _headerKey,
                          child: _buildHeader(
                            showBackButton: Navigator.canPop(context),
                          ),
                        ),
                        Expanded(
                          child: AppRefreshIndicator(
                            onRefresh: () async {
                              await _loadCatalog();
                              await _wardrobes.load();
                            },
                            child: CustomScrollView(
                              controller: _storeScrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildSectionHeader(
                                        'Featured',
                                        'featured',
                                        _featuredKey,
                                      ),
                                      _buildFeatured(),
                                      _buildSectionHeader(
                                        'Powerups',
                                        'powerups',
                                        _powerupsKey,
                                      ),
                                      _buildItemsHeader(),
                                      _buildBody(),
                                      _buildSectionHeader(
                                        'Characters & Accessories',
                                        'characters',
                                        _charactersKey,
                                      ),
                                      _buildCharacters(),
                                      SizedBox(
                                        height:
                                            MediaQuery.paddingOf(
                                              context,
                                            ).bottom +
                                            24,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_purchaseOverlayItem == null && _tutorialStep != null)
              Positioned.fill(
                child: SpotlightOverlay(
                  targetRect: _tutorialTarget,
                  title: _tutorialTitles[_tutorialStep ?? 0],
                  body: _tutorialBodies[_tutorialStep ?? 0],
                  stepIndex: _tutorialStep ?? 0,
                  stepCount: 6,
                  onNext: _advanceTutorial,
                  onBack: _tutorialStep == 0 ? null : _backTutorial,
                  onSkip: _finishTutorial,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseOverlay(
    Map<String, dynamic> item,
    BuildContext overlayContext,
  ) {
    final colors = AppColors.of(overlayContext);
    final rawName = item['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Item';
    final type = item['powerupType'];
    final art = type is String && type.isNotEmpty
        ? _powerupArt(type, fallbackSize: 70)
        : _cosmeticArt(item, iconSize: 70);
    return SafeArea(
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Purchasing $name',
          child: ExcludeSemantics(
            child: GameContainer(
              key: const Key('shop-purchase-overlay'),
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
              frameColor: colors.coinDark,
              surfaceColor: colors.parchment,
              glowColor: colors.coinMid,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 92, height: 92, child: Center(child: art)),
                    const SizedBox(height: 14),
                    Text(
                      'PURCHASING',
                      style: PixelText.title(size: 17, color: colors.textDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: PixelText.body(size: 14, color: colors.textMid),
                    ),
                    const SizedBox(height: 16),
                    PillButtonSpinner(color: colors.accent),
                  ],
                ),
              ),
            ),
          ),
        ),
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
                    TextButton.icon(
                      label: Text(
                        'Back',
                        style: PixelText.body(
                          size: 13,
                          color: AppColors.of(context).textLight,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'SHOP',
                        style: PixelText.title(
                          size: 30,
                          color: AppColors.of(context).textLight,
                        ).copyWith(shadows: _textShadows),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: CoinBalanceBadge(
                        coins: widget.authService.coins,
                        onAddTap: _openGetCoins,
                      ),
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

  Widget _buildItemsHeader() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSegmentControl(),
        // Powerup-store filter + sort live in the (fixed) header so they
        // don't disturb the body's stagger-in tile list.
        if (_section == _ShopSection.store) ...[
          // Batch 2026-08-09 item 3: was 2px — visibly cramped against
          // the 8px gap above the pills. The two header gaps now match.
          const SizedBox(height: 8),
          _buildPowerupControls(),
        ],
      ],
    ),
  );

  Widget _buildSegmentControl() {
    Widget segment(String label, _ShopSection section) {
      final selected = _section == section;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_section == section) return;
            _disposeShopAdTarget();
            setState(() {
              _section = section;
              _category = _ShopCategory.powerups;
              _selectedCosmeticItem = null;
              if (section == _ShopSection.inventory) _deferTutorial = false;
            });
            _maybeScheduleTutorial();
          },
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
          segment('BUY', _ShopSection.store),
          const SizedBox(width: 3),
          segment('OWNED', _ShopSection.inventory),
        ],
      ),
    );
  }

  /// Categories offered as pills. POWERUPS drops out entirely when the
  /// powerup endpoints are missing (older backend) — the same condition that
  /// hides the powerup section today, so those users never see a dead pill.
  List<_ShopCategory> get _visibleCategories => const [
    _ShopCategory.featured,
    _ShopCategory.powerups,
    _ShopCategory.characters,
  ];

  /// The active category, coerced into the visible set. Guards the case where
  /// powerups vanish after a refresh while POWERUPS is selected.
  _ShopCategory get _activeCategory {
    final visible = _visibleCategories;
    return visible.contains(_category)
        ? _category
        : visible.firstWhere(
            (category) => category != _ShopCategory.featured,
            orElse: () => _ShopCategory.featured,
          );
  }

  void _wardrobesChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToSection(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _selectCategory(_ShopCategory category) {
    if (category == _ShopCategory.featured) {
      _focusFeatured(ShopFocus.coins);
      return;
    }
    _scrollToSection(
      category == _ShopCategory.powerups ? _powerupsKey : _charactersKey,
    );
  }

  Widget _buildSectionHeader(String title, String id, GlobalKey anchor) =>
      Padding(
        key: anchor,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Semantics(
          header: true,
          child: Row(
            key: Key('shop-section-$id'),
            children: [
              Container(
                width: 5,
                height: 23,
                decoration: BoxDecoration(
                  color: AppColors.of(context).pillGold,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.of(context).pillGoldDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: PixelText.title(
                    size: 24,
                    color: AppColors.of(context).textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildCharacters() {
    if (_wardrobes.state == WardrobeLoadState.initial && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _wardrobes.state == WardrobeLoadState.initial &&
            !_loading) {
          _wardrobes.load();
        }
      });
    }
    final unavailable = _wardrobes.state == WardrobeLoadState.unsupported;
    final rows =
        unavailable ||
            (_shouldShowTutorial &&
                _wardrobes.characters.isEmpty &&
                _wardrobes.state != WardrobeLoadState.loading)
        ? _legacyCharacterRows()
        : _wardrobes.characters.values.toList();
    return Column(
      children: [
        if ((_wardrobes.state == WardrobeLoadState.loading ||
                _wardrobes.state == WardrobeLoadState.initial) &&
            rows.isEmpty)
          const _ShopLoadingSkeleton(cosmetic: true),
        if (unavailable || _wardrobes.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  unavailable
                      ? 'Saved wardrobes are currently unavailable. You can still browse and buy characters.'
                      : _wardrobes.error ?? '',
                  style: PixelText.body(
                    size: 14,
                    color: AppColors.of(context).textLight,
                  ),
                ),
                TextButton(
                  onPressed: _wardrobes.load,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ShopProductGrid(
          compact: true,
          gridKey: const Key('shop-cosmetic-grid'),
          children: [
            for (final row in rows)
              ShopCharacterCard(
                key: Key('shop-character-${row.key}'),
                character: row,
                onPressed: () => _openCharacterMenu(row),
              ),
          ],
        ),
        if (_wardrobes.state == WardrobeLoadState.paging)
          const CircularProgressIndicator(),
        if (_wardrobes.nextCursor != null &&
            _wardrobes.state != WardrobeLoadState.paging)
          TextButton(
            onPressed: () => _wardrobes.load(more: true),
            child: const Text('Load more'),
          ),
      ],
    );
  }

  List<ShopCharacter> _legacyCharacterRows() {
    final equipment = wardrobeMap(_catalog?['equipped']);
    final current = wardrobeMap(equipment['CHARACTER']);
    final rows = <ShopCharacter>[
      ShopCharacter.fromJson({
        'characterKey': 'default',
        'name': 'Capybara',
        'owned': true,
        'active': current.isEmpty,
        'canActivate': false,
        'canEdit': false,
        'canPurchase': false,
        'availability': 'unavailable',
      }),
    ];
    for (final item in wardrobeMaps(_catalog?['items']).where(_isCharacter)) {
      final id = wardrobeString(item['id']);
      if (id == null) continue;
      final owned = _isCosmeticOwned(item);
      rows.add(
        ShopCharacter.fromJson({
          'characterKey': id,
          'name': item['name'],
          'item': item,
          'owned': owned,
          'active': current['id'] == id,
          'canPurchase': !owned,
          'canActivate': false,
          'canEdit': false,
          'availability': 'unavailable',
        }),
      );
    }
    return rows;
  }

  Future<void> _openCharacterMenu(ShopCharacter character) async {
    final generation = _shopSessionGeneration;
    final userId = widget.authService.userId;
    final token = widget.authService.authToken;
    if (token == null) return;
    bool current() =>
        _sessionIsCurrent(generation: generation, userId: userId, token: token);
    if (_characterActivating) return;
    if (!character.owned && character.canPurchase) {
      _openStoreCosmeticSheet(character.item);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).parchment,
      builder: (context) {
        _characterMenuContext = context;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      character.name,
                      style: PixelText.title(
                        size: 22,
                        color: AppColors.of(context).textDark,
                      ),
                    ),
                    if (character.key == 'default')
                      Text(
                        'The original. Steady, sociable, and always in your corner.',
                        style: PixelText.body(
                          size: 13,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                    const SizedBox(height: 16),
                    PillButton(
                      label: 'Edit outfit',
                      onPressed: character.canEdit
                          ? () => Navigator.pop(context, 'edit')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    PillButton(
                      label: character.active
                          ? 'Active character'
                          : 'Use character',
                      onPressed:
                          !character.active &&
                              character.canActivate &&
                              _wardrobes.appearanceRevision != null &&
                              character.outfit?.revision != null
                          ? () => Navigator.pop(context, 'activate')
                          : null,
                    ),
                    if (!character.canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Saved outfit is currently unavailable.',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _characterMenuContext = null;
    if (!mounted || !current()) return;
    if (action == 'edit') {
      final category = await Navigator.of(context).push<ShopCategory>(
        MaterialPageRoute(
          builder: (_) => CharacterWardrobeScreen(
            character: character,
            controller: _wardrobes,
            onBuy: _openStoreCosmeticSheet,
          ),
        ),
      );
      if (mounted && current() && category != null) {
        _selectCategory(
          _ShopCategory.values.firstWhere(
            (value) => value.name == category.name,
          ),
        );
      }
    } else if (action == 'activate') {
      setState(() => _characterActivating = true);
      try {
        await _wardrobes.activate(character);
        if (mounted && current()) {
          _showInfo(context, '${character.name} is active.');
        }
      } on ApiException catch (error) {
        if (mounted && current()) {
          _showError(context, error.message);
          await _wardrobes.load();
        }
      } catch (_) {
        if (mounted && current()) {
          await _wardrobes.load();
          if (mounted && current()) {
            _showError(
              context,
              'Could not verify character activation. Please review the current look.',
            );
          }
        }
      } finally {
        if (mounted && current()) setState(() => _characterActivating = false);
      }
    }
  }

  Widget _buildBody() {
    final state = _catalogState;
    if (state.shouldShowInitialLoading || (_loading && _catalog == null)) {
      return const _ShopLoadingSkeleton(cosmetic: false);
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

    final items = _safeShopItems(state.data?['items'] ?? _catalog?['items']);

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

  /// An art-led grid of item tiles for the active category. The category
  /// name lives in the pill row now, so the grid carries no header of its own.
  Widget _buildSectionGroup(List<Widget> tiles, {required int staggerIndex}) =>
      StaggerIn(
        index: staggerIndex,
        child: ShopProductGrid(
          compact: true,
          gridKey: const Key('shop-product-grid'),
          spaciousPowerups: true,
          children: tiles,
        ),
      );

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
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).parchment,
      // Explicit constraints pin the sheet edge-to-edge; without them the M3
      // defaults float it as an inset card, unlike every other sheet here.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        _billingItemSheetContext = ctx;
        return SafeArea(
          child: SingleChildScrollView(
            key: const Key('shop-item-sheet'),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchmentBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchmentDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.of(context).parchmentBorder,
                        width: 1,
                      ),
                    ),
                    child: art,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: PixelText.title(
                    size: 20,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                if (slotLabel != null || badge != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (slotLabel != null)
                          _sheetChip(slotLabel, AppColors.of(context).textMid),
                        if (slotLabel != null && badge != null)
                          const SizedBox(width: 6),
                        if (badge != null)
                          _sheetChip(badge, AppColors.of(context).textAccent),
                      ],
                    ),
                  ),
                ],
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    description,
                    textAlign: TextAlign.left,
                    style: PixelText.body(
                      size: 15,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ...actions,
                ],
              ],
            ),
          ),
        );
      },
    ).whenComplete(() => _billingItemSheetContext = null);
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

  Widget _cosmeticArt(Map<String, dynamic> item, {double iconSize = 44}) {
    final assetKey = item['assetKey'] as String? ?? '';
    final isCharacter = item['slot'] == 'CHARACTER';
    final equipped = _isCosmeticEquipped(item);
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
  Future<ShopCategory?> _openStoreCosmeticSheet(
    Map<String, dynamic> item,
  ) async {
    Future<void>? operation;
    var getCoins = false;
    final name = item['name'] as String? ?? 'Accessory';
    final rawPrice = item['priceCoins'];
    final price = rawPrice is num ? rawPrice.toInt() : 0;
    // Cosmetics get the same watch-ads top-up powerups have (spec §7), driven
    // by the same server-served rules.
    final route = _routeFor(price);
    final adsNeeded = _adsNeededFor(price);
    final adContext = route == _AffordRoute.watchAds
        ? _shopContextFor(item, RewardedAdPlacement.cosmeticUnlock)
        : null;
    _warmShopAd(adContext);
    await _showItemSheet(
      art: _cosmeticArt(item, iconSize: 48),
      name: name,
      slotLabel: _slotLabels[item['slot']],
      description: item['description'] is String
          ? item['description'] as String
          : '',
      actions: [
        if (_memberPriceCopy(item) case final copy?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              copy,
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
        ?_adUnlockCapNotice(price),
        switch (route) {
          _AffordRoute.affordable => PillButton(
            label: 'BUY · $price',
            leading: const CoinGlyph(size: 16),
            variant: PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    Navigator.of(context).pop();
                    operation = _purchase(item);
                  },
          ),
          _AffordRoute.watchAds => PillButton(
            label: adsNeeded == 1
                ? 'WATCH 1 AD TO UNLOCK'
                : 'WATCH $adsNeeded ADS TO UNLOCK',
            icon: Icons.smart_display_rounded,
            variant: PillButtonVariant.rewardedAd,
            fontSize: 13,
            fullWidth: true,
            onPressed: _saving
                ? null
                : () {
                    _shopActionContext = adContext;
                    Navigator.of(context).pop();
                    operation = _unlockCosmeticWithAds(item, adsNeeded);
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
              getCoins = true;
              _openGetCoins();
            },
          ),
        },
      ],
    ).whenComplete(() {
      if (_shopActionContext != adContext) _disposeShopAdTarget();
    });
    await operation;
    return getCoins ? ShopCategory.featured : null;
  }

  Widget _powerupArt(String type, {double fallbackSize = 44}) {
    final path = PowerupIcon.assetPathFor(type);
    if (path == null) return PowerupIcon(type: type, size: fallbackSize);
    return AccessoryThumbnail(
      assetKey: type,
      assetPath: path,
      remoteKind: RemoteAssetKind.powerups,
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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.parchmentBorder, width: 1),
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
    _recordMeta(MetaConversion.coinOffersViewed);
    _focusFeatured(ShopFocus.coins);
  }

  void _focusFeatured(ShopFocus focus, {bool rebuild = true}) {
    void update() {
      _tutorialStep = null;
      _tutorialTarget = null;
    }

    if (rebuild) {
      setState(update);
    } else {
      update();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focus == ShopFocus.membership) {
        _openMembershipDetails();
      } else {
        final target = _coinsKey.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignment: 0,
              duration: const Duration(milliseconds: 240),
            ),
          );
        }
      }
    });
  }

  Future<void> _openMembershipDetails() async {
    if (_membershipOpen) return;
    _recordMeta(MetaConversion.membershipViewed);
    final billing = BillingScope.read(context);
    _membershipOpen = true;
    _membershipUserId = billing?.userId;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.of(context).parchmentLight,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .90,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          _membershipSheetContext = sheetContext;
          Widget body() => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Text(
                        'Bara+',
                        style: PixelText.title(
                          size: 24,
                          color: AppColors.of(sheetContext).textDark,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('shop-membership-close'),
                    tooltip: 'Close membership',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (billing != null &&
                  billing.plans.isEmpty &&
                  !billing.snapshot.isMember)
                TextButton(
                  key: const Key('shop-membership-retry'),
                  onPressed: billing.snapshot.busy ? null : billing.refresh,
                  child: const Text('Retry store connection'),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: GameToastAnchor(
                    top: _toastTop,
                    child: BaraPlusBody(
                      key: ValueKey('membership-${billing?.userId}'),
                      controller: billing,
                    ),
                  ),
                ),
              ),
            ],
          );
          return billing == null
              ? BillingScope.disabled(child: body())
              : BillingScope(
                  controller: billing,
                  child: ListenableBuilder(
                    listenable: billing,
                    builder: (context, _) => body(),
                  ),
                );
        },
      );
    } finally {
      _membershipOpen = false;
      _membershipSheetContext = null;
      _membershipUserId = null;
    }
  }

  void _closeMembershipForIdentityChange() {
    final sheet = _membershipSheetContext;
    if (sheet == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !sheet.mounted) return;
      final sheetRoute = ModalRoute.of(sheet);
      if (sheetRoute == null || !sheetRoute.isActive) return;
      final navigator = Navigator.of(sheet);
      navigator.removeRoute(sheetRoute);
    });
  }

  Widget _buildFeatured() {
    final colors = AppColors.of(context);
    final billing = BillingScope.maybeOf(context);
    final membershipAvailable =
        billing != null &&
        (billing.plans.isNotEmpty ||
            billing.snapshot.status != BillingStatus.free ||
            billing.canManageSubscription);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: KeyedSubtree(
            key: const Key('billing-shop-membership'),
            child: Semantics(
              button: true,
              label: 'Bara+ membership details',
              child: Material(
                key: const Key('shop-membership-toggle'),
                color: colors.parchment,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openMembershipDetails,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: colors.coinDark,
                          size: 32,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bara+',
                                style: PixelText.title(
                                  size: 23,
                                  color: colors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                billing?.snapshot.isPermanent == true
                                    ? 'PERMANENT'
                                    : billing?.snapshot.isMember == true
                                    ? 'MEMBER'
                                    : 'MEMBERSHIP',
                                style: PixelText.body(
                                  size: 12,
                                  color: colors.textMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: colors.textMid),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: _coinsKey,
          child: CoinPackOffers(
            key: ValueKey('coins-${billing?.userId}'),
            onGreenSurface: true,
            showHeading: false,
          ),
        ),
        if (!membershipAvailable)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Membership is currently unavailable.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 13, color: colors.textLight),
                ),
                if (billing != null)
                  TextButton(
                    onPressed: billing.snapshot.busy ? null : billing.refresh,
                    child: Text(
                      'Try again',
                      style: PixelText.body(size: 13, color: colors.textLight),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  ExtraSpinAdController _newAdController() =>
      widget.adControllerBuilder?.call() ??
      AdService(adUnitId: AdService.powerupUnlockAdUnitId);

  RewardedAdContext? _shopContextFor(
    Map<String, dynamic> item,
    RewardedAdPlacement placement,
  ) {
    final userId = widget.authService.userId;
    final sku = item['sku'];
    if (userId == null || userId.isEmpty || sku is! String || sku.isEmpty) {
      return null;
    }
    return placement == RewardedAdPlacement.powerupUnlock
        ? RewardedAdContext.powerupUnlock(
            userId: userId,
            sku: sku,
            localDate: _localDate(),
          )
        : RewardedAdContext.cosmeticUnlock(
            userId: userId,
            sku: sku,
            localDate: _localDate(),
          );
  }

  void _warmShopAd(RewardedAdContext? context) {
    if (!_hasValidServerAdUnlock || context == null) {
      _disposeShopAdTarget();
      return;
    }
    final previous = _shopAdContext;
    if (previous != null && previous != context) _disposeShopAdTarget();
    final controller = _shopAdController ??= _newAdController();
    if (!controller.isSupported) {
      _disposeShopAdTarget();
      return;
    }
    _shopAdContext = context;
    unawaited(controller.warm(context));
  }

  void _disposeShopAdTarget() {
    _shopAdController?.dispose();
    _shopAdController = null;
    _shopAdContext = null;
    _shopActionContext = null;
  }

  void _disposeActiveShopController(ExtraSpinAdController controller) {
    if (_activeShopAdControllers.remove(controller)) controller.dispose();
  }

  Future<bool> _watchShopUnlockAds(
    RewardedAdContext context,
    int adsNeeded,
    int generation,
    String token,
  ) async {
    final matching = _shopAdContext == context ? _shopAdController : null;
    ExtraSpinAdController current = matching ?? _newAdController();
    _activeShopAdControllers.add(current);
    _shopAdController = null;
    _shopAdContext = null;
    _shopActionContext = null;
    if (!current.isSupported) {
      current.dispose();
      if (mounted) {
        _showError(this.context, 'Ads aren’t available on this device.');
      }
      return false;
    }

    try {
      for (var index = 1; index <= adsNeeded; index++) {
        if (!_shopFlowCurrent(generation, token, context)) return false;
        if (!mounted) return false;
        showInfoToast(this.context, 'Ad $index of $adsNeeded…');
        if (!current.isReadyFor(context)) {
          await current.warm(context);
          if (!_shopFlowCurrent(generation, token, context)) return false;
        }
        if (!current.isReadyFor(context)) {
          if (mounted) {
            _showError(this.context, 'Ad didn’t load. No coins spent.');
          }
          return false;
        }

        final showFuture = current.showAndAwaitRewardFor(context);
        ExtraSpinAdController? next;
        Future<void>? nextWarm;
        if (index < adsNeeded) {
          next = _newAdController();
          _activeShopAdControllers.add(next);
          if (next.isSupported) {
            nextWarm = next.warm(context);
          }
        }
        final earned = await showFuture;
        if (!_shopFlowCurrent(generation, token, context)) {
          if (next != null) _disposeActiveShopController(next);
          return false;
        }
        if (!earned) {
          if (next != null) _disposeActiveShopController(next);
          if (mounted) {
            _showError(this.context, 'Ad not finished. No coins spent.');
          }
          return false;
        }
        if (next != null) {
          await nextWarm;
          if (!_shopFlowCurrent(generation, token, context)) return false;
          _disposeActiveShopController(current);
          current = next;
        }
      }
      return true;
    } finally {
      _disposeActiveShopController(current);
    }
  }

  bool _shopFlowCurrent(
    int generation,
    String token,
    RewardedAdContext context,
  ) =>
      mounted &&
      generation == _shopActionGeneration &&
      widget.authService.authToken == token &&
      widget.authService.userId == context.userId;

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

    final adContext = _shopContextFor(item, RewardedAdPlacement.powerupUnlock);
    if (adContext == null) return;
    final actionGeneration = _shopActionGeneration;
    final sessionGeneration = _shopSessionGeneration;
    final userId = widget.authService.userId;
    final startedEpoch = _shopStateEpoch;
    final name = item['name'] as String? ?? 'Powerup';

    setState(() => _saving = true);
    try {
      if (!await _watchShopUnlockAds(
        adContext,
        adsNeeded,
        actionGeneration,
        token,
      )) {
        return;
      }
      if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;

      _showPurchaseOverlay(item);
      final result = await _backendApiService.unlockPowerupWithAds(
        identityToken: token,
        sku: sku,
        idempotencyKey:
            '${adContext.userId}-pwunlock-${DateTime.now().microsecondsSinceEpoch}',
        localDate: adContext.localDate,
      );
      if (!_shopFlowCurrent(actionGeneration, token, adContext) ||
          !_sessionIsCurrent(
            generation: sessionGeneration,
            userId: userId,
            token: token,
            epoch: startedEpoch,
          )) {
        return;
      }
      final acceptedEpoch = ++_shopStateEpoch;
      final rawCoins = result['coins'];
      final coins = rawCoins is num ? rawCoins.toInt() : null;
      if (_isIdempotent(result) || !_patchPowerupMutation(result, item)) {
        await _loadPowerups(
          token,
          generation: sessionGeneration,
          userId: userId,
          epoch: acceptedEpoch,
        );
        if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;
      } else if (coins != null) {
        if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;
        await widget.authService.updateCoins(coins);
      }
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
        epoch: acceptedEpoch,
      )) {
        _clearPurchaseOverlay();
        _showInfo(context, '$name unlocked!');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(context, error.message);
      }
    } catch (_) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(context, 'Couldn’t unlock this powerup. Please try again.');
      }
    } finally {
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        setState(() => _saving = false);
        _maybeScheduleTutorial();
      }
    }
  }

  /// The device's local calendar day, so the server's once-per-day ad-unlock
  /// cap uses the user's midnight rather than UTC's (contract §4.1/§4.2).
  String _localDate() {
    final now = widget.now?.call() ?? DateTime.now();
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

    final adContext = _shopContextFor(item, RewardedAdPlacement.cosmeticUnlock);
    if (adContext == null) return;
    final actionGeneration = _shopActionGeneration;
    final sessionGeneration = _shopSessionGeneration;
    final userId = widget.authService.userId;
    final startedEpoch = _shopStateEpoch;
    final name = item['name'] as String? ?? 'Item';

    setState(() => _saving = true);
    try {
      if (!await _watchShopUnlockAds(
        adContext,
        adsNeeded,
        actionGeneration,
        token,
      )) {
        return;
      }
      if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;

      _showPurchaseOverlay(item);
      final result = await _backendApiService.unlockShopItemWithAds(
        identityToken: token,
        sku: sku,
        idempotencyKey:
            '${adContext.userId}-shopunlock-${DateTime.now().microsecondsSinceEpoch}',
        localDate: adContext.localDate,
      );
      if (!_shopFlowCurrent(actionGeneration, token, adContext) ||
          !_sessionIsCurrent(
            generation: sessionGeneration,
            userId: userId,
            token: token,
            epoch: startedEpoch,
          )) {
        return;
      }
      final acceptedEpoch = ++_shopStateEpoch;
      final rawCoins = result['coins'];
      final coins = rawCoins is num ? rawCoins.toInt() : null;
      if (_isIdempotent(result) || !_patchCosmeticPurchase(result)) {
        await _refreshCosmetics(
          token,
          generation: sessionGeneration,
          userId: userId,
          epoch: acceptedEpoch,
          clearSelection: true,
        );
        if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;
      } else if (coins != null) {
        if (!_shopFlowCurrent(actionGeneration, token, adContext)) return;
        await widget.authService.updateCoins(coins);
      }
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
        epoch: acceptedEpoch,
      )) {
        if (!mounted) return;
        _clearPurchaseOverlay();
        _showInfo(context, '$name unlocked!');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (!_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        return;
      }
      // A 404 means this backend has no cosmetic ad-unlock at all. Say so once
      // and send the user down the coin route rather than looping on ads.
      if (error.statusCode == 404) {
        _clearPurchaseOverlay();
        _openGetCoins();
        return;
      }
      _clearPurchaseOverlay();
      _showError(context, error.message);
    } catch (_) {
      if (!mounted) return;
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        _showError(context, 'Couldn’t unlock this item. Please try again.');
      }
    } finally {
      if (_sessionIsCurrent(
        generation: sessionGeneration,
        userId: userId,
        token: token,
      )) {
        _clearPurchaseOverlay();
        setState(() => _saving = false);
        _maybeScheduleTutorial();
      }
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
    final adContext = canAdUnlock
        ? _shopContextFor(item, RewardedAdPlacement.powerupUnlock)
        : null;

    void openSheet() {
      _warmShopAd(adContext);
      unawaited(
        _showItemSheet(
          art: _powerupArt(type, fallbackSize: 64),
          name: name,
          badge: owned > 0 ? 'OWNED x$owned' : null,
          description: [
            item['description'] is String ? item['description'] as String : '',
            ?_memberPriceCopy(item),
          ].where((part) => part.isNotEmpty).join('\n\n'),
          actions: [
            ?_adUnlockCapNotice(price),
            _powerupSheetAction(
              item,
              price,
              affordable,
              canAdUnlock,
              adsNeeded,
              adContext,
            ),
          ],
        ).whenComplete(() {
          if (_shopActionContext != adContext) _disposeShopAdTarget();
        }),
      );
    }

    return _ShopTile(
      art: _powerupArt(type),
      name: name,
      badge: owned > 0 ? 'x$owned' : null,
      // Item 23 — the strip is the PRICE, always. See _storeCosmeticTile.
      stripLabel: _memberPriceCopy(item) != null ? '$price · PLUS' : '$price',
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
    RewardedAdContext? adContext,
  ) {
    if (affordable) {
      return PillButton(
        label: 'BUY · $price',
        leading: const CoinGlyph(size: 16),
        variant: PillButtonVariant.primary,
        fontSize: 14,
        fullWidth: true,
        onPressed: _saving
            ? null
            : () {
                _shopActionContext = adContext;
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
        variant: PillButtonVariant.rewardedAd,
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

  List<Widget> _buildStore(
    List<Map<String, dynamic>> items,
  ) => _buildCategoryBody(
    [for (final item in _visiblePowerupStoreItems()) _storePowerupTile(item)],
    emptyIcon: Icons.bolt_rounded,
    emptyMessage: !_powerupsAvailable && _powerupsAvailabilityResolved
        ? 'Powerups are currently unavailable. Pull down to try again.'
        : _powerupFilter == _PowerupFilter.all
        ? 'No powerups for sale right now.'
        : 'No ${_powerupFilter.label.toLowerCase()} powerups right now.',
  );

  List<Widget> _buildInventory(List<Map<String, dynamic>> items) =>
      _buildCategoryBody(
        [
          for (final entry
              in _powerupInventory.entries
                  .where((entry) => entry.value > 0)
                  .toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            _ownedPowerupTile(entry.key, entry.value),
        ],
        emptyIcon: Icons.bolt_rounded,
        emptyMessage: 'No powerups yet. Tap Buy to find your first one.',
      );

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

class _ShopLoadingSkeleton extends StatelessWidget {
  const _ShopLoadingSkeleton({required this.cosmetic});

  final bool cosmetic;

  Widget _tile(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1,
        ),
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
              height: 32,
              alignment: Alignment.center,
              child: const SkeletonLine(width: 52, height: 10),
            ),
            // Price strip
            Container(
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.of(context).parchmentDark,
                border: Border(
                  top: BorderSide(
                    color: AppColors.of(context).parchmentBorder,
                    width: 1,
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

  Widget _section(BuildContext context, int tileCount) => ShopProductGrid(
    compact: true,
    spaciousPowerups: !cosmetic,
    gridKey: const Key('shop-loading-grid'),
    children: [for (var i = 0; i < tileCount; i++) _tile(context)],
  );

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

/// Art-led merchandise card with the name and one quiet footer action. Tapping
/// the card opens the detail sheet with the full description.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.art,
    required this.name,
    required this.stripLabel,
    required this.stripEnabled,
    required this.onStrip,
    required this.onTap,
    this.stripIcon,
    this.stripLeading,
    this.badge,
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

  Widget _badgeChip(BuildContext context) => Container(
    key: const Key('shop-tile-badge'),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.of(context).roofMid,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.of(context).roofDark),
    ),
    child: Text(
      badge!,
      // `textLight`, NOT `parchment` (spec §6). `parchment` is a SURFACE
      // token — cream by day, near-black navy at night — so using it as a
      // text color painted near-black on the dark-green `roofMid` pill.
      // `textLight` is cream in both palettes, which is what the day design
      // intended. The `highlighted` branch is already correct.
      style: PixelText.title(size: 10, color: AppColors.of(context).textLight),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        key: const Key('shop-product-card'),
        decoration: BoxDecoration(
          color: AppColors.of(context).parchment,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.of(context).parchmentBorder,
            width: 1,
          ),
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
                          // Keep the scaled artwork from crowding the frame;
                          // the extra vertical breathing room is especially
                          // important for tall powerup art.
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Center(
                            // The taller three-column art window supplies the
                            // extra size. Keep the full image contained inside
                            // its padding so thumbs and effects cannot clip.
                            child: Transform.scale(
                              key: const Key('shop-tile-art-scale'),
                              scale: 1,
                              child: art,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (badge != null)
                      Positioned(top: 4, right: 4, child: _badgeChip(context)),
                  ],
                ),
              ),
              // Name. The box height tracks the type size (spec §8): two lines
              // of 13pt pixel type need ~38dp, and under-sizing the box is what
              // clips the second line.
              //
              // The responsive grid gives product names enough width to read
              // as merchandise instead of inventory abbreviations.
              Container(
                height: 32,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _FittedTileName(
                  name: name,
                  color: AppColors.of(context).textDark,
                ),
              ),
              // Action strip
              KeyedSubtree(
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: onStrip == null
                        ? AppColors.of(context).parchmentDark
                        : AppColors.of(context).pillGold.withValues(
                            alpha: stripEnabled ? 0.22 : 0.10,
                          ),
                    border: Border(
                      top: BorderSide(
                        color: onStrip == null
                            ? AppColors.of(context).parchmentBorder
                            : AppColors.of(context).pillGoldDark,
                        width: 1,
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
                                : AppColors.of(context).textDark,
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
/// The responsive redesign supports a larger nominal name size while this
/// still picks the biggest size from [_sizes] whose
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
