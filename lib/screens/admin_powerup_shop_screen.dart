import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/powerup_shop_admin_item.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/pixel_switch.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/trail_sign.dart';

/// Admin powerup-shop catalog editor (spec §5.1).
///
/// This is the surface that makes "the DB is the authority" true for shop
/// prices. Without it, changing Leech from 150 to 300 means hand-written SQL —
/// which is how the drift in audit §2.1 happened, and how it stayed invisible.
///
/// Two deliberate omissions:
/// * **No copy fields.** `name` / `description` belong to `PowerupCopy`; there
///   is no editor for them here and no setter for them in the API method.
/// * **No "save all".** Each row PATCHes itself with only the keys that
///   actually changed, so one bad field can't rewrite a neighbouring item.
class AdminPowerupShopScreen extends StatefulWidget {
  const AdminPowerupShopScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
  }) : _api = backendApiService;

  final AuthService authService;
  final BackendApiService? _api;

  @override
  State<AdminPowerupShopScreen> createState() => _AdminPowerupShopScreenState();
}

enum _LoadState { loading, ready, unsupported, error }

class _AdminPowerupShopScreenState extends State<AdminPowerupShopScreen> {
  late final BackendApiService _api = widget._api ?? BackendApiService();

  _LoadState _state = _LoadState.loading;
  String? _loadError;
  List<PowerupShopAdminItem> _items = const [];

  /// Per-item pending edits, keyed by item id. An item absent from this map is
  /// clean; the save button reads directly off it, so "dirty" and "what gets
  /// PATCHed" can never disagree.
  final Map<String, _ItemDraft> _drafts = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  String? get _token {
    final token = widget.authService.authToken;
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _state = _LoadState.error;
        _loadError = 'Not signed in.';
      });
      return;
    }
    setState(() => _state = _LoadState.loading);
    try {
      final items = await _api.fetchAdminPowerupShopItems(
        identityToken: token,
      );
      if (!mounted) return;
      if (items == null) {
        setState(() => _state = _LoadState.unsupported);
        return;
      }
      setState(() {
        _items = items;
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _loadError = e.toString();
      });
    }
  }

  _ItemDraft _draftFor(PowerupShopAdminItem item) {
    return _drafts.putIfAbsent(item.id, () => _ItemDraft(item));
  }

  /// Replaces an item with the server's echo and clears its draft — the row
  /// shows what the backend actually stored, not what was typed at it.
  void _adoptServerItem(PowerupShopAdminItem updated) {
    final index = _items.indexWhere((i) => i.id == updated.id);
    if (index < 0) return;
    setState(() {
      _items = List.of(_items)..[index] = updated;
      _drafts.remove(updated.id)?.dispose();
    });
  }

  Future<void> _save(PowerupShopAdminItem item) async {
    final token = _token;
    final draft = _drafts[item.id];
    if (token == null || draft == null || _saving.contains(item.id)) return;
    final changes = draft.changesAgainst(item);
    if (changes.isEmpty) return;

    setState(() => _saving.add(item.id));
    try {
      final updated = await _api.updateAdminPowerupShopItem(
        identityToken: token,
        itemId: item.id,
        priceCoins: changes.priceCoins,
        active: changes.active,
        testOnly: changes.testOnly,
        sortOrder: changes.sortOrder,
      );
      if (!mounted) return;
      if (updated != null) {
        _adoptServerItem(updated);
      } else {
        // 2xx with a body this build couldn't read: reload rather than trust
        // the local draft, so the row can't drift from the DB.
        await _load();
      }
      if (mounted) showInfoToast(context, 'Saved ${item.name}.');
    } catch (e) {
      // The draft is deliberately KEPT: a rejected save must not silently
      // discard what the admin typed.
      if (mounted) showErrorToast(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: GameBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
              child: Column(
                children: [
                  TrailSign(
                    width: boardWidth,
                    child: Text(
                      'POWERUP SHOP',
                      style: PixelText.title(
                        size: 18,
                        color: AppColors.textDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._buildBody(boardWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(double boardWidth) {
    switch (_state) {
      case _LoadState.loading:
        return const [
          SizedBox(height: 40),
          Center(child: CircularProgressIndicator(color: AppColors.accent)),
        ];

      case _LoadState.unsupported:
        return [
          _notice(
            boardWidth,
            'UNAVAILABLE',
            'The powerup shop admin API is not supported by this backend. '
                'Deploy the backend that serves /admin/powerup-shop/items, '
                'then reopen this screen.',
          ),
        ];

      case _LoadState.error:
        return [
          _notice(
            boardWidth,
            'COULD NOT LOAD',
            _loadError ?? 'Unknown error.',
            onRetry: _load,
          ),
        ];

      case _LoadState.ready:
        if (_items.isEmpty) {
          return [
            _notice(
              boardWidth,
              'EMPTY CATALOG',
              'The backend returned no powerup shop items.',
              onRetry: _load,
            ),
          ];
        }
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Prices and flags are live. Names come from PowerupCopy and are '
              'not editable here.',
              style: PixelText.body(size: 10, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ),
          for (final item in _items) _itemCard(boardWidth, item),
        ];
    }
  }

  Widget _notice(
    double width,
    String title,
    String body, {
    VoidCallback? onRetry,
  }) {
    return ContentBoard(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PixelText.title(size: 14, color: AppColors.error)),
          const SizedBox(height: 8),
          Text(body, style: PixelText.body(size: 12, color: AppColors.textMid)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            PillButton(
              label: 'RETRY',
              fullWidth: true,
              fontSize: 12,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(double width, PowerupShopAdminItem item) {
    final draft = _draftFor(item);
    final changes = draft.changesAgainst(item);
    final saving = _saving.contains(item.id);
    final priceError = draft.priceError;
    final sortError = draft.sortError;
    final canSave = !saving && changes.isNotEmpty && !draft.hasError;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ContentBoard(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PowerupIcon(type: item.powerupType, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: PixelText.title(
                          size: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        item.sku,
                        style: PixelText.body(
                          size: 10,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                if (changes.isNotEmpty)
                  Text(
                    'UNSAVED',
                    style: PixelText.pill(size: 9, color: AppColors.error),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _numberField(
                    key: Key('ps-price-${item.id}'),
                    controller: draft.priceController,
                    label: 'PRICE (COINS)',
                    error: priceError,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    key: Key('ps-sort-${item.id}'),
                    controller: draft.sortController,
                    label: 'SORT ORDER',
                    error: sortError,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _toggleRow(
              key: Key('ps-active-${item.id}'),
              label: 'ACTIVE',
              hint: 'Sells in the store',
              value: draft.active ?? item.active,
              onChanged: (v) => setState(() => draft.active = v),
            ),
            const SizedBox(height: 8),
            _toggleRow(
              key: Key('ps-testonly-${item.id}'),
              label: 'TEST ONLY',
              hint: 'Hidden from real users until the app build ships',
              value: draft.testOnly ?? item.testOnly,
              onChanged: (v) => setState(() => draft.testOnly = v),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('ps-save-${item.id}'),
                onPressed: canSave ? () => _save(item) : null,
                child: Text(
                  saving ? 'SAVING...' : 'SAVE',
                  style: PixelText.pill(
                    size: 11,
                    color: canSave ? AppColors.roofMid : AppColors.textMid,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String? error,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: key,
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
          onChanged: onChanged,
          style: PixelText.number(size: 14, color: AppColors.textDark),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: PixelText.body(size: 10, color: AppColors.textMid),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: error != null
                    ? AppColors.error
                    : AppColors.parchmentBorder,
                width: 2,
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              error,
              style: PixelText.body(size: 9, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _toggleRow({
    required Key key,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: PixelText.title(size: 11, color: AppColors.textDark),
              ),
              Text(
                hint,
                style: PixelText.body(size: 9, color: AppColors.textMid),
              ),
            ],
          ),
        ),
        PixelSwitch(key: key, value: value, onChanged: onChanged),
      ],
    );
  }
}

/// The pending edit for one row. Holds the controllers so a rebuild doesn't
/// reset a half-typed value, and owns the client-side validation that keeps
/// the app from sending a body §5.1 defines as a 400.
class _ItemDraft {
  _ItemDraft(PowerupShopAdminItem item)
    : priceController = TextEditingController(text: item.priceCoins.toString()),
      sortController = TextEditingController(text: item.sortOrder.toString());

  final TextEditingController priceController;
  final TextEditingController sortController;
  bool? active;
  bool? testOnly;

  void dispose() {
    priceController.dispose();
    sortController.dispose();
  }

  int? get _price => int.tryParse(priceController.text.trim());
  int? get _sort => int.tryParse(sortController.text.trim());

  /// §5.1 rejects a non-integer or negative `priceCoins` with a 400. Catching
  /// it here keeps the failure next to the field instead of in a toast.
  String? get priceError {
    final text = priceController.text.trim();
    if (text.isEmpty) return 'Required';
    final value = _price;
    if (value == null) return 'Must be a whole number';
    if (value < 0) return 'Must be non-negative';
    return null;
  }

  String? get sortError {
    final text = sortController.text.trim();
    if (text.isEmpty) return 'Required';
    return _sort == null ? 'Must be a whole number' : null;
  }

  bool get hasError => priceError != null || sortError != null;

  /// Only the keys that actually differ from the server's item — the PATCH
  /// body is the diff, never the whole row.
  _ItemChanges changesAgainst(PowerupShopAdminItem item) {
    final price = _price;
    final sort = _sort;
    return _ItemChanges(
      priceCoins: price != null && price != item.priceCoins ? price : null,
      sortOrder: sort != null && sort != item.sortOrder ? sort : null,
      active: active != null && active != item.active ? active : null,
      testOnly: testOnly != null && testOnly != item.testOnly ? testOnly : null,
    );
  }
}

class _ItemChanges {
  const _ItemChanges({
    this.priceCoins,
    this.active,
    this.testOnly,
    this.sortOrder,
  });

  final int? priceCoins;
  final bool? active;
  final bool? testOnly;
  final int? sortOrder;

  bool get isEmpty =>
      priceCoins == null &&
      active == null &&
      testOnly == null &&
      sortOrder == null;
  bool get isNotEmpty => !isEmpty;
}
