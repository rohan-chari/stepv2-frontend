import 'package:flutter/foundation.dart';
import '../models/character_wardrobe.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';

enum WardrobeLoadState {
  initial,
  loading,
  loaded,
  paging,
  stale,
  empty,
  unsupported,
  sessionExpired,
}

/// One shop session, isolated from replaced auth identities and stale reads.
class CharacterWardrobeController extends ChangeNotifier {
  CharacterWardrobeController({
    required this.api,
    required this.auth,
    this.onAppearanceChanged,
  }) {
    _identity = '${auth.userId}:${auth.authToken}';
    auth.addListener(_authChanged);
  }
  final BackendApiService api;
  final AuthService auth;
  final ValueChanged<Map<String, dynamic>>? onAppearanceChanged;
  final Map<String, ShopCharacter> characters = {};
  WardrobeLoadState state = WardrobeLoadState.initial;
  String? error, nextCursor;
  int? appearanceRevision;
  int? _publishedAppearanceRevision;
  int _generation = 0, _request = 0;
  bool _disposed = false;
  late String _identity;
  String? get token => auth.authToken;
  String get localDate => DateTime.now().toIso8601String().substring(0, 10);
  void _authChanged() {
    final identity = '${auth.userId}:${auth.authToken}';
    if (identity == _identity) return;
    _identity = identity;
    _generation++;
    _request++;
    characters.clear();
    appearanceRevision = null;
    _publishedAppearanceRevision = null;
    nextCursor = null;
    state = token == null
        ? WardrobeLoadState.sessionExpired
        : WardrobeLoadState.initial;
    error = null;
    notifyListeners();
  }

  bool current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (more && (nextCursor == null || state == WardrobeLoadState.paging)) {
      return;
    }
    final authToken = token;
    if (authToken == null) {
      state = WardrobeLoadState.sessionExpired;
      _notify();
      return;
    }
    final generation = _generation, request = ++_request;
    final cursor = more ? nextCursor : null;
    state = more ? WardrobeLoadState.paging : WardrobeLoadState.loading;
    _notify();
    try {
      final json = await api.fetchShopCharacters(
        identityToken: authToken,
        cursor: cursor,
        localDate: localDate,
      );
      if (!current(generation) || request != _request) return;
      if (json['contract'] != wardrobeContract) {
        state = WardrobeLoadState.unsupported;
        _notify();
        return;
      }
      final revision = wardrobeRevision(json['appearanceRevision']);
      if (more && appearanceRevision != revision) {
        await load();
        return;
      }
      final rows = wardrobeMaps(
        json['characters'],
      ).map(ShopCharacter.fromJson).where((row) => row.valid);
      if (!more) characters.clear();
      for (final row in rows) {
        characters[row.key] = row;
      }
      appearanceRevision = revision;
      final active = characters.values
          .where((row) => row.active && row.outfit?.editable == true)
          .firstOrNull;
      if (active != null &&
          revision != null &&
          revision != _publishedAppearanceRevision) {
        _publishedAppearanceRevision = revision;
        onAppearanceChanged?.call({
          'equipped': {
            if (active.key != 'default') 'CHARACTER': active.item,
            for (final item in active.outfit?.items ?? <Map<String, dynamic>>[])
              if (item['slot'] is String) item['slot'] as String: item,
          },
        });
      }
      nextCursor = wardrobeString(json['nextCursor']);
      error = characters.isEmpty
          ? 'Characters could not be read. Please try again.'
          : null;
      state = characters.isEmpty
          ? WardrobeLoadState.empty
          : WardrobeLoadState.loaded;
    } on ApiException catch (failure) {
      if (!current(generation) || request != _request) return;
      state = failure.statusCode == 401
          ? WardrobeLoadState.sessionExpired
          : (failure.statusCode == 404 || failure.statusCode == 405) &&
                failure.code == null
          ? WardrobeLoadState.unsupported
          : characters.isEmpty
          ? WardrobeLoadState.empty
          : WardrobeLoadState.stale;
      error = failure.message;
    } catch (_) {
      if (!current(generation) || request != _request) return;
      state = characters.isEmpty
          ? WardrobeLoadState.empty
          : WardrobeLoadState.stale;
      error = 'Could not load characters. Please try again.';
    }
    _notify();
  }

  Future<CharacterWardrobe> wardrobe(String key, {String? cursor}) async {
    final generation = _generation, authToken = token;
    if (authToken == null) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    final json = await api.fetchCharacterWardrobe(
      identityToken: authToken,
      characterKey: key,
      cursor: cursor,
      localDate: localDate,
    );
    if (!current(generation)) {
      throw const ApiException('Account changed.', statusCode: 401);
    }
    if (json['contract'] != wardrobeContract || json['characterKey'] != key) {
      throw const ApiException('Wardrobe is currently unavailable.');
    }
    return CharacterWardrobe.fromJson(json);
  }

  Future<CharacterOutfit> save(
    String key,
    int revision,
    Map<String, String?> slots,
  ) async {
    final generation = _generation, authToken = token;
    if (authToken == null) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    _request++;
    final json = await api.saveCharacterOutfit(
      identityToken: authToken,
      characterKey: key,
      expectedOutfitRevision: revision,
      slots: slots,
    );
    if (!current(generation)) {
      throw const ApiException('Account changed.', statusCode: 401);
    }
    final outfit = _acceptMutation(json, key);
    await load();
    return outfit;
  }

  Future<void> activate(ShopCharacter character) async {
    final revision = appearanceRevision,
        outfitRevision = character.outfit?.revision;
    final generation = _generation, authToken = token;
    if (revision == null || outfitRevision == null || authToken == null) {
      throw const ApiException(
        'Saved outfit is currently unavailable. Please refresh.',
      );
    }
    _request++;
    try {
      final json = await api.activateShopCharacter(
        identityToken: authToken,
        characterKey: character.key,
        expectedAppearanceRevision: revision,
        expectedOutfitRevision: outfitRevision,
      );
      if (!current(generation)) {
        throw const ApiException('Account changed.', statusCode: 401);
      }
      _acceptMutation(json, character.key);
      await load();
    } catch (failure) {
      if (!current(generation)) rethrow;
      if (failure is ApiException &&
          failure.statusCode != null &&
          failure.statusCode! < 500) {
        rethrow;
      }
      await load();
      if (!current(generation)) rethrow;
      final verified = characters[character.key];
      if (state == WardrobeLoadState.loaded &&
          verified?.active == true &&
          verified?.outfit?.editable == true &&
          verified?.outfit?.revision == outfitRevision &&
          (appearanceRevision ?? -1) > revision &&
          mapEquals(verified?.outfit?.slots, character.outfit?.slots)) {
        return;
      }
      rethrow;
    }
  }

  CharacterOutfit _acceptMutation(Map<String, dynamic> json, String key) {
    final outfit = CharacterOutfit.fromJson(json['outfit']);
    if (json['contract'] != wardrobeContract ||
        json['characterKey'] != key ||
        !outfit.editable ||
        wardrobeRevision(json['appearanceRevision']) == null) {
      throw const ApiException(
        'Could not verify the saved outfit. Please refresh.',
      );
    }
    appearanceRevision = wardrobeRevision(json['appearanceRevision']);
    final equipped = wardrobeMap(json['equipped']);
    if (json['equipped'] is! Map ||
        equipped.entries.any(
          (entry) =>
              ![...wardrobeSlots, 'CHARACTER'].contains(entry.key) ||
              entry.value is! Map ||
              wardrobeMap(entry.value)['slot'] != entry.key ||
              wardrobeString(wardrobeMap(entry.value)['id']) == null,
        )) {
      throw const ApiException(
        'Could not verify the current appearance. Please refresh.',
      );
    }
    if (json['appearanceChanged'] == true) {
      _publishedAppearanceRevision = appearanceRevision;
      onAppearanceChanged?.call({'equipped': equipped});
    }
    return outfit;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
