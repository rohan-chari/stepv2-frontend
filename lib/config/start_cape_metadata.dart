import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The start screen's cape capybara must render exactly what the Accessory
/// Tuner tuned, but it draws before sign-in — no catalog fetch is possible.
/// So the catalog funnel ([_applyShopCatalog] in main_shell) saves the cape's
/// live `renderMetadata` here whenever the catalog carries it, and the start
/// screen reads the cached copy on later launches. The compiled fallback below
/// is a snapshot of the prod tuner values at build time; it only shows on a
/// fresh install's first launch, or on prod-channel builds where the cape is
/// still testOnly-filtered out of the catalog.
class StartCapeMetadata {
  static const String prefsKey = 'start_cape_item';

  /// Prod `shop_items` cape row (bobble + render_metadata), snapshotted
  /// 2026-07-22. `bobble` lives OUTSIDE renderMetadata in the catalog — the
  /// cache must carry both or tuner static/bounce changes silently no-op here.
  static const Map<String, dynamic> fallback = <String, dynamic>{
    'bobble': true,
    'renderMetadata': <String, dynamic>{
      'offsetX': -0.1,
      'offsetY': -0.0042372881,
      'rotation': 0.2491525424,
      'scale': 2.15,
      'animationFrames': 6,
      'renderLayer': 'front',
    },
  };

  static Future<void> save({
    required bool bobble,
    required Map<String, dynamic> renderMetadata,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode({'bobble': bobble, 'renderMetadata': renderMetadata}),
    );
  }

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['renderMetadata'] is Map<String, dynamic> &&
          (decoded['renderMetadata'] as Map<String, dynamic>).isNotEmpty) {
        return decoded;
      }
    } catch (_) {
      // Corrupt cache — fall through to the compiled snapshot.
    }
    return fallback;
  }
}
