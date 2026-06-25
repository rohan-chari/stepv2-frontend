import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/home_course_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

class AdminAccessoryTunerScreen extends StatefulWidget {
  final AuthService authService;

  const AdminAccessoryTunerScreen({super.key, required this.authService});

  @override
  State<AdminAccessoryTunerScreen> createState() =>
      _AdminAccessoryTunerScreenState();
}

class _AdminAccessoryTunerScreenState extends State<AdminAccessoryTunerScreen> {
  final _api = BackendApiService();

  List<Map<String, dynamic>> _items = const [];
  Loadable<List<Map<String, dynamic>>> _itemsState = const Loadable.initial();
  String? _selectedItemId;
  bool _isLoading = true;
  bool _isSaving = false;

  double _offsetX = 0;
  double _offsetY = 0;
  double _rotation = 0;
  double _scale = 1.0;
  bool _active = true;
  bool _testOnly = false;
  bool _bobble = false;
  final _priceController = TextEditingController(text: '0');

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final previous = _items;
    setState(() {
      _isLoading = true;
      _itemsState = previous.isEmpty
          ? const Loadable.loading()
          : Loadable.refreshing(previous);
    });
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _itemsState = Loadable.error(
          'Not signed in.',
          data: previous.isEmpty ? null : previous,
        );
      });
      return;
    }
    try {
      final res = await _api.fetchAdminShopItems(identityToken: token);
      final items = (res['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _items = items;
        if (items.isNotEmpty) {
          _selectItem(items.first['id'] as String);
        } else {
          _selectedItemId = null;
        }
        _itemsState = Loadable.success(items);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _itemsState = Loadable.error(
          e.toString(),
          data: previous.isEmpty ? null : previous,
        );
      });
      if (mounted) {
        showErrorToast(context, 'Failed to load shop items: $e');
      }
    }
  }

  void _selectItem(String id) {
    final item = _items.firstWhere(
      (m) => m['id'] == id,
      orElse: () => const <String, dynamic>{},
    );
    final meta = item['renderMetadata'];
    final map = meta is Map ? Map<String, dynamic>.from(meta) : const {};
    setState(() {
      _selectedItemId = id;
      _offsetX = _toDouble(map['offsetX']) ?? 0;
      _offsetY = _toDouble(map['offsetY']) ?? 0;
      _rotation = _toDouble(map['rotation']) ?? 0;
      _scale = _toDouble(map['scale']) ?? 1.0;
      _active = item['active'] is bool ? item['active'] as bool : true;
      _testOnly = item['testOnly'] is bool ? item['testOnly'] as bool : false;
      // Fall back to the historical slot rule when the backend hasn't sent a
      // bobble flag yet (HEAD/FACE/NECK bobbed) so the toggle shows real state.
      final slot = item['slot'] as String?;
      _bobble = item['bobble'] is bool
          ? item['bobble'] as bool
          : (slot == 'HEAD' || slot == 'FACE' || slot == 'NECK');
      final price = item['priceCoins'];
      _priceController.text = price is num ? price.toInt().toString() : '0';
    });
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Map<String, dynamic>? get _selectedItem {
    if (_selectedItemId == null) return null;
    return _items.firstWhere(
      (m) => m['id'] == _selectedItemId,
      orElse: () => const <String, dynamic>{},
    );
  }

  Map<String, dynamic> _previewAccessory() {
    final item = _selectedItem;
    if (item == null) return const {};
    return {
      'slot': item['slot'],
      'assetKey': item['assetKey'],
      'bobble': _bobble,
      'renderMetadata': {
        'offsetX': _offsetX,
        'offsetY': _offsetY,
        'rotation': _rotation,
        'scale': _scale,
      },
    };
  }

  Future<void> _save() async {
    final id = _selectedItemId;
    final token = widget.authService.authToken;
    if (id == null || token == null || token.isEmpty) return;
    final price = int.tryParse(_priceController.text.trim());
    if (price == null || price < 0) {
      showErrorToast(context, 'Price must be a non-negative integer.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final res = await _api.updateAdminShopItem(
        identityToken: token,
        itemId: id,
        renderMetadata: {
          'offsetX': _offsetX,
          'offsetY': _offsetY,
          'rotation': _rotation,
          'scale': _scale,
        },
        active: _active,
        priceCoins: price,
        testOnly: _testOnly,
        bobble: _bobble,
      );
      final updated = res['item'] is Map
          ? Map<String, dynamic>.from(res['item'] as Map)
          : null;
      if (updated != null) {
        final idx = _items.indexWhere((m) => m['id'] == id);
        if (idx >= 0) {
          setState(() => _items[idx] = updated);
        }
      }
      if (mounted) {
        showInfoToast(context, 'Saved.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;
    final item = _selectedItem;

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
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
              child: Column(
                children: [
                  TrailSign(
                    width: boardWidth,
                    child: Text(
                      'ACCESSORY RENDER TUNER',
                      style: PixelText.title(
                        size: 18,
                        color: AppColors.textDark,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ContentBoard(
                    width: boardWidth,
                    child: _itemsState.isError && !_itemsState.hasData
                        ? LoadErrorPanel(
                            title: 'Couldn’t load shop items',
                            message: 'Check your connection and try again.',
                            onRetry: _load,
                          )
                        : _isLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                              ),
                            ),
                          )
                        : _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No shop items found.',
                              style: PixelText.body(
                                size: 14,
                                color: AppColors.textMid,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildPicker(),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  _active ? 'Enabled' : 'Disabled',
                                  style: PixelText.body(
                                    size: 14,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                subtitle: Text(
                                  _active
                                      ? 'Visible in the shop'
                                      : 'Hidden from the shop',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                value: _active,
                                activeThumbColor: AppColors.accent,
                                onChanged: (v) => setState(() => _active = v),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  _testOnly ? 'TestFlight only' : 'Live in prod',
                                  style: PixelText.body(
                                    size: 14,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                subtitle: Text(
                                  _testOnly
                                      ? 'Only visible in TestFlight builds'
                                      : 'Visible to everyone on the App Store',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                value: _testOnly,
                                activeThumbColor: AppColors.accent,
                                onChanged: (v) => setState(() => _testOnly = v),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  _bobble ? 'Bobbles' : 'Static',
                                  style: PixelText.body(
                                    size: 14,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                subtitle: Text(
                                  _bobble
                                      ? 'Rides the capybara head-bob'
                                      : 'Stays still as the capybara moves',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                value: _bobble,
                                activeThumbColor: AppColors.accent,
                                onChanged: (v) => setState(() => _bobble = v),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Price (coins)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Container(
                                  width: 200,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: AppColors.parchmentDark.withValues(
                                      alpha: 0.25,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.bottomCenter,
                                  child: CapybaraCustomizationPreview(
                                    accessories: [_previewAccessory()],
                                    size: 140,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _slider(
                                'offsetX',
                                _offsetX,
                                -0.5,
                                0.5,
                                0.005,
                                (v) => setState(() => _offsetX = v),
                              ),
                              _slider(
                                'offsetY',
                                _offsetY,
                                -0.5,
                                0.5,
                                0.005,
                                (v) => setState(() => _offsetY = v),
                              ),
                              _slider(
                                'rotation (rad)',
                                _rotation,
                                -3.15,
                                3.15,
                                0.02,
                                (v) => setState(() => _rotation = v),
                              ),
                              _slider(
                                'scale',
                                _scale,
                                0.4,
                                2.5,
                                0.05,
                                (v) => setState(() => _scale = v),
                              ),
                              const SizedBox(height: 16),
                              PillButton(
                                label: _isSaving
                                    ? 'SAVING...'
                                    : 'SAVE TO ALL USERS',
                                variant: PillButtonVariant.accent,
                                fontSize: 13,
                                fullWidth: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                onPressed: (_isSaving || item == null)
                                    ? null
                                    : _save,
                              ),
                              const SizedBox(height: 8),
                              PillButton(
                                label: 'RESET TO SAVED',
                                variant: PillButtonVariant.secondary,
                                fontSize: 12,
                                fullWidth: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 10,
                                ),
                                onPressed: _selectedItemId == null
                                    ? null
                                    : () => _selectItem(_selectedItemId!),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedItemId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Accessory',
        border: OutlineInputBorder(),
      ),
      items: _items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item['id'] as String,
              child: Text(
                '${item['name'] ?? item['sku']} (${item['slot']})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) _selectItem(id);
      },
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChanged,
  ) {
    void nudge(double delta) {
      final next = (value + delta).clamp(min, max).toDouble();
      onChanged(next);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: PixelText.body(size: 13, color: AppColors.textDark),
                ),
              ),
              Text(
                value.toStringAsFixed(3),
                style: PixelText.number(size: 13, color: AppColors.textMid),
              ),
            ],
          ),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                onPressed: value <= min ? null : () => nudge(-step),
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                  activeColor: AppColors.accent,
                ),
              ),
              _StepButton(
                icon: Icons.add,
                onPressed: value >= max ? null : () => nudge(step),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: onPressed == null
            ? AppColors.parchmentDark.withValues(alpha: 0.2)
            : AppColors.parchmentDark.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Icon(
            icon,
            size: 18,
            color: onPressed == null ? AppColors.textMid : AppColors.textDark,
          ),
        ),
      ),
    );
  }
}
