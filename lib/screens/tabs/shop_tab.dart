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
  bool _loading = true;
  bool _saving = false;

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
                  CoinBalanceBadge(coins: widget.authService.coins),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Spend coins on capybara gear. Earn more by walking and racing.',
                style: PixelText.body(
                  size: 15,
                  color: AppColors.parchment.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
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
            _buildSectionHeader('ACCESSORIES'),
            if (items.isEmpty)
              _buildEmptyState()
            else
              for (int i = 0; i < items.length; i++)
                _ShopItemRow(
                  item: items[i],
                  index: i,
                  saving: _saving,
                  onBuy: () => _purchase(items[i]),
                  onEquip: () => _equip(
                    items[i]['slot'] as String? ?? '',
                    items[i]['id'] as String?,
                  ),
                  onClear: () =>
                      _equip(items[i]['slot'] as String? ?? '', null),
                ),
          ],
        ),
      ),
    );
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

  Widget _buildEmptyState() {
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
            Icons.checkroom_rounded,
            size: 32,
            color: AppColors.textMid.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            'No accessories yet — new capybara gear coming soon.',
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
