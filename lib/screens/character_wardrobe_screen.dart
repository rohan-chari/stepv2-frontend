import '../widgets/app_refresh_indicator.dart';
import '../tutorial/spotlight_overlay.dart';
import '../widgets/game_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/character_wardrobe.dart';
import '../services/backend_api_service.dart';
import '../services/character_wardrobe_controller.dart';
import '../styles.dart';
import '../widgets/accessory_thumbnail.dart';
import '../widgets/info_toast.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/race_ui.dart';
import '../widgets/shop_category_bar.dart';
import '../widgets/shop_product_grid.dart';

class CharacterWardrobeScreen extends StatefulWidget {
  const CharacterWardrobeScreen({
    super.key,
    required this.character,
    required this.controller,
    required this.onBuy,
    this.tutorial = false,
  });
  final ShopCharacter character;
  final CharacterWardrobeController controller;
  final Future<ShopCategory?> Function(Map<String, dynamic>) onBuy;
  final bool tutorial;
  @override
  State<CharacterWardrobeScreen> createState() =>
      _CharacterWardrobeScreenState();
}

class _CharacterWardrobeScreenState extends State<CharacterWardrobeScreen> {
  final _headerKey = GlobalKey();
  final _controlsKey = GlobalKey();
  final _previewKey = GlobalKey();
  final _choicesKey = GlobalKey();
  final _spaceKey = GlobalKey();
  int _tutorialIndex = 0;
  Rect? _tutorialRect;
  double _toastTop = 100;
  final List<VoidCallback> _toasts = [];
  void _info(String message) =>
      _toasts.add(showInfoToast(_headerKey.currentContext ?? context, message));
  void _errorToast(String message) => _toasts.add(
    showErrorToast(_headerKey.currentContext ?? context, message),
  );
  CharacterWardrobe? _wardrobe;
  CharacterOutfit? _saved;
  Map<String, String?> _draft = {};
  final Map<String, WardrobeAccessory> _accessories = {};
  final Map<String, Map<String, dynamic>> _draftItems = {};
  String? _nextCursor, _error;
  int _readEpoch = 0;
  bool _loading = true, _busy = false, _paging = false, _leaving = false;
  String? _selected;
  late final String _identity;
  final ScrollController _scroll = ScrollController();
  bool get _dirty => _saved != null && !mapEquals(_draft, _saved?.slots);
  bool get _readOnly =>
      _saved?.editable != true || _wardrobe?.appearanceRevision == null;
  bool get _hasUnowned => _draft.values.whereType<String>().any(
    (id) =>
        _accessories[id]?.owned != true &&
        !(_saved?.items.any((item) => item['id'] == id) ?? false),
  );
  bool get _current =>
      mounted &&
      _identity ==
          '${widget.controller.auth.userId}:${widget.controller.auth.authToken}';
  @override
  void initState() {
    super.initState();
    _identity =
        '${widget.controller.auth.userId}:${widget.controller.auth.authToken}';
    widget.controller.auth.addListener(_identityChanged);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 260 &&
          _nextCursor != null &&
          !_paging) {
        _load(more: true);
      }
    });
    _load();
  }

  void _identityChanged() {
    if (!_current && mounted) {
      setState(() {
        for (final dismiss in _toasts) {
          dismiss();
        }
        _toasts.clear();
        _busy = false;
        _paging = false;
        _leaving = false;
        _readEpoch++;
        _saved = null;
        _draft = {};
        _draftItems.clear();
        _accessories.clear();
        _error = 'Please reopen the shop for this account.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final dismiss in _toasts) {
      dismiss();
    }
    widget.controller.auth.removeListener(_identityChanged);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false, bool discard = false}) async {
    final request = ++_readEpoch;
    bool currentRead() => _current && request == _readEpoch;
    setState(() => _paging = more);
    try {
      final wardrobe = await widget.controller.wardrobe(
        widget.character.key,
        cursor: more ? _nextCursor : null,
      );
      if (!currentRead()) return;
      if (more &&
          (_wardrobe?.appearanceRevision != wardrobe.appearanceRevision ||
              _wardrobe?.outfit.revision != wardrobe.outfit.revision)) {
        _paging = false;
        await _load();
        return;
      }
      setState(() {
        if (!more) {
          _wardrobe = wardrobe;
          if (!_dirty || discard) {
            _saved = wardrobe.outfit;
            _draft = {...wardrobe.outfit.slots};
          }
          _accessories.clear();
        }
        for (final item in wardrobe.accessories) {
          _accessories[item.id] = item;
        }
        _nextCursor = wardrobe.nextCursor;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (currentRead()) {
        setState(() {
          if (widget.tutorial) {
            _wardrobe = CharacterWardrobe.fromJson({
              'characterKey': 'default',
              'name': 'Capybara',
              'appearanceRevision': 0,
              'outfit': {
                'revision': 0,
                'editable': true,
                'hasHiddenItems': false,
                'slots': {for (final slot in wardrobeSlots) slot: null},
                'items': [],
                'unavailableItemIds': [],
              },
              'accessories': [],
            });
            _saved = _wardrobe?.outfit;
            _draft = {...?_saved?.slots};
          } else {
            _error = error is ApiException
                ? error.message
                : 'Wardrobe is currently unavailable. Please try again.';
          }
          _loading = false;
        });
      }
    } finally {
      if (currentRead() && more) setState(() => _paging = false);
      if (widget.tutorial && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measureTutorial());
      }
    }
  }

  Future<void> _measureTutorial() async {
    if (!mounted || !widget.tutorial) return;
    final keys = [_controlsKey, _previewKey, _choicesKey, _headerKey];
    final target = keys[_tutorialIndex].currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(target, alignment: .3);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !target.mounted) return;
    final box = target.findRenderObject();
    final space = _spaceKey.currentContext?.findRenderObject();
    if (box is RenderBox &&
        space is RenderBox &&
        box.hasSize &&
        space.hasSize) {
      setState(
        () => _tutorialRect =
            space.globalToLocal(box.localToGlobal(Offset.zero)) & box.size,
      );
    }
  }

  void _tutorialNext() {
    if (_tutorialIndex == 3) {
      _leave();
      return;
    }
    setState(() {
      _tutorialIndex++;
      _tutorialRect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTutorial());
  }

  Future<bool> _allowLeave() async {
    if (_busy) return false;
    if (!_dirty || widget.tutorial) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.of(context).parchment,
            title: const Text('Discard outfit changes?'),
            content: const Text(
              'Your purchased items stay yours. This outfit has not been saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _leave([ShopCategory? category]) async {
    if (!await _allowLeave() || !mounted) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, category);
  }

  void _select(WardrobeAccessory accessory) {
    if (_busy || !_current) return;
    setState(() {
      _selected = accessory.id;
      _draftItems[accessory.id] = accessory.item;
      if (_readOnly ||
          (!accessory.canPreview && _draft[accessory.slot] != accessory.id)) {
        return;
      }
      _draft[accessory.slot] = _draft[accessory.slot] == accessory.id
          ? null
          : accessory.id;
    });
  }

  Future<void> _save() async {
    final revision = _saved?.revision;
    if (!_current ||
        _busy ||
        !_dirty ||
        _hasUnowned ||
        _readOnly ||
        revision == null ||
        widget.tutorial) {
      return;
    }
    final submitted = {..._draft};
    _readEpoch++;
    setState(() {
      _busy = true;
      _paging = false;
    });
    try {
      final outfit = await widget.controller.save(
        widget.character.key,
        revision,
        submitted,
      );
      if (!mounted || !_current) return;
      setState(() {
        _saved = outfit;
        _draft = {...outfit.slots};
      });
      await _load(discard: true);
      if (mounted && _current) _info('Outfit saved.');
    } on ApiException catch (error) {
      if (!mounted || !_current) return;
      if (error.code == 'OUTFIT_CHANGED' ||
          error.code == 'APPEARANCE_CHANGED') {
        await _reviewConflict();
      } else if (error.statusCode == null || (error.statusCode ?? 0) >= 500) {
        await _reconcileSave(submitted);
      } else {
        _errorToast(error.message);
      }
    } catch (_) {
      if (!mounted || !_current) return;
      await _reconcileSave(submitted);
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _reconcileSave(Map<String, String?> submitted) async {
    try {
      final fresh = await widget.controller.wardrobe(widget.character.key);
      if (!mounted || !_current) return;
      if (fresh.outfit.editable && mapEquals(fresh.outfit.slots, submitted)) {
        setState(() {
          _wardrobe = fresh;
          _saved = fresh.outfit;
          _draft = {...fresh.outfit.slots};
        });
        await widget.controller.load();
        if (mounted && _current) _info('Outfit is saved.');
      } else {
        await _reviewConflict();
      }
    } catch (_) {
      if (mounted && _current) {
        _errorToast('Could not verify the save. Your draft is kept.');
      }
    }
  }

  Future<void> _reviewConflict() async {
    CharacterWardrobe? fresh;
    try {
      fresh = await widget.controller.wardrobe(widget.character.key);
    } catch (_) {}
    if (!mounted || !_current) return;
    final reload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.of(context).parchment,
        title: const Text('Review changed outfit'),
        content: const Text(
          'Your saved outfit changed. Reload it to discard this draft, or keep editing and review before saving again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: fresh == null
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Reload saved'),
          ),
        ],
      ),
    );
    if (!_current || fresh == null) return;
    if (reload == true) {
      setState(() {
        _wardrobe = fresh;
        _saved = fresh!.outfit;
        _draft = {...fresh.outfit.slots};
      });
    }
    // Keeping the draft does not advance its revision or silently rebase it.
  }

  Future<void> _buy(WardrobeAccessory item) async {
    if (!_current || _busy || !item.canPurchase || widget.tutorial) return;
    _readEpoch++;
    setState(() {
      _busy = true;
      _paging = false;
    });
    ShopCategory? destination;
    try {
      destination = await widget.onBuy(item.item);
      if (_current) await _load();
    } finally {
      if (_current) setState(() => _busy = false);
    }
    if (destination != null && _current) await _leave(destination);
  }

  Text _text(String value, {double size = 14}) => Text(
    value,
    style: PixelText.body(size: size, color: AppColors.of(context).textDark),
  );
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = _accessories[_selected];
    final itemRecords = <String, Map<String, dynamic>>{
      ..._draftItems,
      for (final item in _saved?.items ?? <Map<String, dynamic>>[])
        ?wardrobeString(item['id']): item,
      for (final item in _accessories.values) item.id: item.item,
    };
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
      child: Stack(
        key: _spaceKey,
        children: [
          PopScope(
            canPop: _leaving || (!_dirty && !_busy),
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _leave();
            },
            child: Scaffold(
              backgroundColor: colors.roofLight,
              bottomNavigationBar: _saved == null
                  ? null
                  : SafeArea(
                      top: false,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.roofMid,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.parchmentBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .2),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IntrinsicHeight(child: _buildControls()),
                      ),
                    ),
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      key: _headerKey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextButton.icon(
                              onPressed: _busy ? null : () => _leave(),
                              icon: Icon(
                                Icons.arrow_back,
                                color: colors.textLight,
                              ),
                              label: Text(
                                'Back to Characters',
                                style: PixelText.body(
                                  size: 13,
                                  color: colors.textLight,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              widget.character.name,
                              textAlign: TextAlign.right,
                              style: PixelText.title(
                                size: 17,
                                color: colors.textLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : AppRefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                                children: [
                                  if (_error != null) ...[
                                    _text(_error!),
                                    TextButton(
                                      onPressed: _load,
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                  if (_saved != null) ...[
                                    KeyedSubtree(
                                      key: _previewKey,
                                      child: Container(
                                        key: const Key('wardrobe-preview'),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        constraints: const BoxConstraints(
                                          minHeight: 210,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: colors.parchment,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: colors.parchmentBorder,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width:
                                                  MediaQuery.sizeOf(
                                                        context,
                                                      ).width <
                                                      360
                                                  ? 120
                                                  : 140,
                                              height: 160,
                                              child: RacerAvatar(
                                                rank: 1,
                                                size: 132,
                                                showMedalRing: false,
                                                animal: widget.character.animal,
                                                accessories: [
                                                  for (final id
                                                      in _draft.values
                                                          .whereType<String>())
                                                    ?itemRecords[id],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _text(
                                                    _dirty
                                                        ? 'Trying on'
                                                        : 'Saved outfit',
                                                    size: 16,
                                                  ),
                                                  if (selected != null) ...[
                                                    const SizedBox(height: 8),
                                                    _text(
                                                      wardrobeString(
                                                            selected
                                                                .item['name'],
                                                          ) ??
                                                          'Accessory',
                                                    ),
                                                  ],
                                                  if (_hasUnowned) ...[
                                                    const SizedBox(height: 8),
                                                    _text(
                                                      'Buy the previewed items before saving.',
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (selected?.canPurchase == true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: PillButton(
                                          label:
                                              'Buy · ${selected?.item['priceCoins'] ?? 0}',
                                          onPressed: _busy
                                              ? null
                                              : () => _buy(selected!),
                                        ),
                                      ),
                                    if (_readOnly)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: _text(
                                          'Outfit editing is currently unavailable. Refresh to check again.',
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    KeyedSubtree(
                                      key: _choicesKey,
                                      child: Column(
                                        children: [
                                          if (!_accessories.values.any(
                                            (item) =>
                                                item.fit != 'preservation-only',
                                          ))
                                            _text(
                                              'No accessories for this character yet.',
                                            ),
                                          _accessorySection(
                                            'Owned',
                                            'owned',
                                            owned: true,
                                          ),
                                          _accessorySection(
                                            'Unowned',
                                            'unowned',
                                            owned: false,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_paging)
                                      const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    if (_nextCursor != null && !_paging)
                                      TextButton(
                                        onPressed: () => _load(more: true),
                                        child: const Text('Load more'),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.tutorial && !_loading)
            Positioned.fill(
              child: SpotlightOverlay(
                targetRect: _tutorialRect,
                title: const [
                  'SAVE OR RESET',
                  'TRY IT ON',
                  'FIND YOUR FIT',
                  'BACK TO THE SHOP',
                ][_tutorialIndex],
                body: const [
                  'Outfits save independently for each character. Reset returns to its saved look.',
                  'Preview accessories here before buying or saving. Editing does not switch your active character.',
                  'Only accessories made for this character can be selected. Items you already own remain yours.',
                  'Back returns to Characters. Scroll through the shop sections to browse more.',
                ][_tutorialIndex],
                stepIndex: _tutorialIndex + 2,
                stepCount: 6,
                onNext: _tutorialNext,
                onBack: _tutorialIndex == 0
                    ? null
                    : () {
                        setState(() => _tutorialIndex--);
                        _measureTutorial();
                      },
                onSkip: () => _leave(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final colors = AppColors.of(context);
    return KeyedSubtree(
      key: _controlsKey,
      child: Row(
        key: const Key('wardrobe-controls'),
        children: [
          Expanded(
            child: PillButton(
              fullWidth: true,
              scaleDownContent: false,
              labelMaxLines: 2,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              label: _busy ? 'Saving…' : 'Save outfit',
              onPressed:
                  _dirty &&
                      !_hasUnowned &&
                      !_readOnly &&
                      !_busy &&
                      !widget.tutorial
                  ? _save
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colors.textLight,
              disabledForegroundColor: colors.textLight.withValues(alpha: .45),
              minimumSize: const Size(64, 48),
            ),
            onPressed: _dirty && !_busy
                ? () => setState(() {
                    _saved = _wardrobe?.outfit ?? _saved;
                    _draft = {...?_saved?.slots};
                    _selected = null;
                  })
                : null,
            child: Text(
              'Reset',
              style: PixelText.body(
                size: 14,
                color: _dirty && !_busy
                    ? colors.textLight
                    : colors.textLight.withValues(alpha: .45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessorySection(String title, String id, {required bool owned}) {
    final colors = AppColors.of(context);
    final items = _accessories.values
        .where((item) => item.fit != 'preservation-only' && item.owned == owned)
        .toList();
    return Column(
      key: Key('wardrobe-section-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 23,
                  decoration: BoxDecoration(
                    color: colors.pillGold,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.pillGoldDark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: PixelText.title(size: 24, color: colors.textLight),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (items.isNotEmpty)
          _grid(items)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              owned
                  ? 'Your accessories will appear here.'
                  : 'No unowned accessories for this character.',
              style: PixelText.body(size: 14, color: colors.textLight),
            ),
          ),
      ],
    );
  }

  Widget _grid(List<WardrobeAccessory> items) => ShopProductGrid(
    gridKey: const Key('wardrobe-accessory-grid'),
    compact: true,
    children: [
      for (final item in items)
        GestureDetector(
          key: Key('wardrobe-item-${item.id}'),
          onTap: () => _select(item),
          child: Semantics(
            selected: _draft[item.slot] == item.id,
            button: true,
            label:
                '${item.item['name'] ?? 'Accessory'}, ${item.owned ? 'Owned' : '${item.item['priceCoins'] ?? 0} coins'}',
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.of(context).parchment,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  width: _draft[item.slot] == item.id ? 2 : 1,
                  color: _draft[item.slot] == item.id
                      ? AppColors.of(context).pillGoldDark
                      : AppColors.of(context).parchmentBorder,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: AccessoryThumbnail(
                      assetKey: wardrobeString(item.item['assetKey']) ?? '',
                      animationFrames: AccessoryThumbnail.framesOf(item.item),
                      errorBuilder: (_, error, stack) =>
                          const Icon(Icons.checkroom),
                    ),
                  ),
                  Text(
                    wardrobeString(item.item['name']) ?? 'Accessory',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 11,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  if (item.canPurchase)
                    _text('${item.item['priceCoins'] ?? 0} coins', size: 10)
                  else
                    _text(
                      item.canSelect
                          ? (_draft[item.slot] == item.id
                                ? 'Selected'
                                : 'Owned')
                          : 'Unavailable',
                      size: 10,
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
