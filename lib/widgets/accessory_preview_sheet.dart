import 'package:flutter/material.dart';
import '../models/accessory_preview.dart';
import '../config/animals.dart';
import '../services/remote_asset_cache.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import 'home_course_track.dart';
import 'home_hero_scene.dart';
import 'pill_button.dart';

/// Read-only preview: all character and outfit choices come from the server.
class AccessoryPreviewSheet extends StatefulWidget {
  const AccessoryPreviewSheet({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.api,
    required this.auth,
  });
  final String itemId, itemName;
  final BackendApiService api;
  final AuthService auth;
  @override
  State<AccessoryPreviewSheet> createState() => _AccessoryPreviewSheetState();
}

class _AccessoryPreviewSheetState extends State<AccessoryPreviewSheet> {
  AccessoryPreview? _preview;
  bool _loading = true, _retry = false, _expired = false;
  int _request = 0;
  late final String? _user = widget.auth.userId, _token = widget.auth.authToken;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_authChanged);
    _load();
  }

  bool get _current =>
      !_expired &&
      widget.auth.userId == _user &&
      widget.auth.authToken == _token;
  void _authChanged() {
    if (_current || !mounted) return;
    _request++;
    setState(() {
      _expired = true;
      _preview = null;
      _loading = false;
      _retry = false;
    });
  }

  Future<void> _load() async {
    final token = _token;
    if (!_current || token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _preview = null;
      _retry = false;
    });
    AccessoryPreview? preview;
    var retry = false;
    try {
      final json = await widget.api.fetchShopItemPreview(
        identityToken: token,
        itemId: widget.itemId,
      );
      preview = AccessoryPreview.parse(json, widget.itemId);
      if (preview != null && !await _bodyReady(preview)) {
        preview = null;
        retry = true;
      }
    } on ApiException catch (error) {
      retry = error.statusCode != 404 && error.statusCode != 401;
    } catch (_) {
      retry = true;
    }
    if (!mounted || !_current || request != _request) return;
    setState(() {
      _preview = preview;
      _loading = false;
      _retry = retry;
    });
  }

  Future<bool> _bodyReady(AccessoryPreview preview) async {
    final animal = preview.animal;
    if (animal == null || kAnimalSprites.containsKey(animal)) return true;
    final cache = RemoteAssetCache.instance;
    if (cache.entry(RemoteAssetKind.characters, animal) == null) {
      await cache.refreshManifest(
        releaseChannel: await widget.api.getReleaseChannel(),
      );
    }
    await cache.fetch(RemoteAssetKind.characters, animal);
    // Unknown bodies must never silently resolve to the bundled capybara.
    return remoteAnimalSprite(animal) != null;
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context), preview = _preview;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('accessory-preview-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.itemName,
                    style: PixelText.title(size: 22, color: colors.textDark),
                  ),
                ),
                IconButton(
                  key: const Key('accessory-preview-close'),
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: colors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                key: Key('accessory-preview-loading'),
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (preview != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 240,
                  child: HomeHeroScene(
                    groundHeight: 54,
                    groundScrollSpeed: 26,
                    excludeBackgroundSemantics: true,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 54 - 4 - 150 * .22,
                          child: Center(
                            child: AnimatedCapybaraWithAccessories(
                              size: 150,
                              stepDuration: const Duration(milliseconds: 720),
                              animate: !MediaQuery.disableAnimationsOf(context),
                              animal: preview.animal,
                              accessories: preview.accessories,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Previewing on ${preview.characterName}',
                style: PixelText.title(size: 16, color: colors.textDark),
              ),
              if (preview.usedFallbackCharacter) ...[
                const SizedBox(height: 8),
                Text(
                  'Your equipped character stays unchanged.',
                  style: PixelText.body(size: 13, color: colors.textMid),
                ),
              ],
            ] else ...[
              Text(
                _retry
                    ? 'Couldn’t load preview. Please try again.'
                    : 'Preview is currently unavailable.',
                style: PixelText.body(size: 15, color: colors.textMid),
              ),
              if (_retry) ...[
                const SizedBox(height: 16),
                PillButton(
                  label: 'TRY AGAIN',
                  variant: PillButtonVariant.secondary,
                  onPressed: _load,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
