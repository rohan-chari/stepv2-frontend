import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/game_container.dart';
import '../../widgets/info_board_card.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/tab_layout.dart';

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
    return TabLayout(
      title: 'SHOP',
      onRefresh: _loadCatalog,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final state = _catalogState;
    if (state.shouldShowInitialLoading || (_loading && _catalog == null)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: ListSkeleton(itemCount: 3),
      );
    }

    if (state.isError && !state.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'ACCESSORIES',
              style: PixelText.title(size: 16, color: AppColors.textMid),
            ),
            const Spacer(),
            CoinBalanceBadge(
              coins: widget.authService.coins,
              heldCoins: widget.authService.heldCoins,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.isRefreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (items.isEmpty)
          const InfoBoardCard(
            title: 'No accessories yet',
            subtitle: 'New capybara gear will show up here soon.',
          )
        else
          for (final item in items) ...[
            _ShopItemCard(
              item: item,
              saving: _saving,
              onBuy: () => _purchase(item),
              onEquip: () =>
                  _equip(item['slot'] as String? ?? '', item['id'] as String?),
              onClear: () => _equip(item['slot'] as String? ?? '', null),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.item,
    required this.saving,
    required this.onBuy,
    required this.onEquip,
    required this.onClear,
  });

  final Map<String, dynamic> item;
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

    return GameContainer(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.parchmentBorder),
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
                Text(
                  name,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
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
              label: 'Clear',
              icon: Icons.close_rounded,
              onPressed: saving ? null : onClear,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            )
          else
            PillButton(
              label: 'Equip',
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
