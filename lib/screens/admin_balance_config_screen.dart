import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/balance_config.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

/// Admin balance editor (spec §6.3.A).
///
/// The database is the authority for every balance value, so this screen is
/// what makes that authority usable. Three properties matter more than looks:
///
/// * **Nothing is edited blind.** A structured, typed form — never a raw JSON
///   blob — with a changed-paths-only diff and an explicit confirm before any
///   write (D12).
/// * **Nothing is silently overwritten.** A stale save gets a 409 and a
///   re-diff against the config the server returned. There is deliberately no
///   auto-merge path anywhere in this file (D10).
/// * **Nothing this editor doesn't understand is destroyed.** The PUT body is
///   the FETCHED config with only edited paths overwritten, so config keys a
///   newer backend added — and that this build has no field for — round-trip
///   verbatim instead of being dropped on the next admin save.
class AdminBalanceConfigScreen extends StatefulWidget {
  const AdminBalanceConfigScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
  }) : _api = backendApiService;

  final AuthService authService;
  final BackendApiService? _api;

  @override
  State<AdminBalanceConfigScreen> createState() =>
      _AdminBalanceConfigScreenState();
}

enum _LoadState { loading, ready, unsupported, error }

class _AdminBalanceConfigScreenState extends State<AdminBalanceConfigScreen> {
  late final BackendApiService _api = widget._api ?? BackendApiService();

  _LoadState _state = _LoadState.loading;
  String? _loadError;

  /// The config as the server last told us it is — the diff baseline and the
  /// round-trip source. Replaced wholesale on a 409, never merged.
  Map<String, dynamic> _baseline = const {};
  int _version = 0;
  Map<String, List<double>> _bounds = const {};
  List<BalanceConfigVersion> _versions = const [];

  /// Edited scalar values keyed by canonical path. Only paths the admin
  /// actually touched appear here.
  final Map<String, Object> _edits = {};
  final Map<String, TextEditingController> _controllers = {};
  final _noteController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _noteController.dispose();
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
      final config = await _api.fetchAdminBalanceConfig(identityToken: token);
      if (!mounted) return;
      if (config == null) {
        // Old backend: an empty form here would let an admin PUT a config the
        // server has no route for — show the truth instead (spec §7).
        setState(() => _state = _LoadState.unsupported);
        return;
      }
      final versions = await _api.fetchAdminBalanceConfigVersions(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _adoptServerConfig(config.config, config.version);
        _bounds = config.bounds;
        _versions = versions;
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

  /// Adopts a server config as the new baseline, discarding nothing the admin
  /// typed — edits are kept so a 409 re-diff shows their intent against the
  /// newer server state.
  void _adoptServerConfig(Map<String, dynamic> config, int version) {
    _baseline = config;
    _version = version;
    for (final field in _fields()) {
      final controller = _controllers[field.path];
      if (controller == null) continue;
      if (!_edits.containsKey(field.path)) {
        controller.text = field.formatted(_baselineValue(field.path));
      }
    }
  }

  // ---------------------------------------------------------------- paths

  /// Reads a dotted path out of a config map. Numeric segments index lists.
  static Object? _readPath(Map<String, dynamic> config, String path) {
    Object? node = config;
    for (final segment in path.split('.')) {
      if (node is Map) {
        node = node[segment];
      } else if (node is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= node.length) return null;
        node = node[index];
      } else {
        return null;
      }
    }
    return node;
  }

  /// Writes a dotted path into a DEEP COPY of [config], leaving every other
  /// key — including ones this build has no field for — untouched.
  static Map<String, dynamic> _writePath(
    Map<String, dynamic> config,
    String path,
    Object value,
  ) {
    final segments = path.split('.');
    final root = _deepCopy(config) as Map<String, dynamic>;
    Object? node = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      if (node is Map) {
        node = node[segment];
      } else if (node is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= node.length) return root;
        node = node[index];
      } else {
        return root;
      }
    }
    final last = segments.last;
    if (node is Map) {
      node[last] = value;
    } else if (node is List) {
      final index = int.tryParse(last);
      if (index != null && index >= 0 && index < node.length) {
        node[index] = value;
      }
    }
    return root;
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries) e.key.toString(): _deepCopy(e.value),
      };
    }
    if (value is List) return value.map(_deepCopy).toList();
    return value;
  }

  Object? _baselineValue(String path) => _readPath(_baseline, path);

  /// The config to submit: the fetched baseline with edited paths applied.
  Map<String, dynamic> _composedConfig() {
    var out = _baseline;
    for (final entry in _edits.entries) {
      out = _writePath(out, entry.key, entry.value);
    }
    return Map<String, dynamic>.from(out);
  }

  // ---------------------------------------------------------------- fields

  /// Every editable scalar, in render order. Paths are canonical dotted paths
  /// into the config JSON, which is what makes the diff, the bound matcher and
  /// the write path share one vocabulary.
  List<_Field> _fields() {
    final fields = <_Field>[];

    void num3(String base) {
      for (var i = 0; i < 3; i++) {
        fields.add(_Field.decimal('$base.$i'));
      }
    }

    for (final row in const ['first', 'last']) {
      num3('positionOdds.$row');
    }
    for (final rarity in _rarityKeys) {
      for (var tier = 0; tier < 4; tier++) {
        fields.add(_Field.integer('upgradeCosts.byRarity.$rarity.$tier'));
      }
    }
    for (var level = 0; level < 4; level++) {
      fields.add(_Field.decimal('luckyHorseshoe.rareChanceByLevel.$level'));
    }
    fields.add(_Field.integer('dailyBox.streakCap'));
    for (final row in const ['first', 'last']) {
      num3('dailyBox.odds.$row');
    }
    for (final tier in _coinRangeKeys) {
      fields.add(_Field.integer('dailyBox.coinRanges.$tier.0'));
      fields.add(_Field.integer('dailyBox.coinRanges.$tier.1'));
    }
    fields.add(_Field.decimal('dailyBox.rareCoinsShare'));
    return fields;
  }

  static const _rarityKeys = ['COMMON', 'UNCOMMON', 'RARE'];
  static const _coinRangeKeys = ['COMMON', 'UNCOMMON', 'RARE_FALLBACK'];
  static const _weightModes = ['inverse', 'uniform', 'legacy'];

  TextEditingController _controllerFor(_Field field) {
    return _controllers.putIfAbsent(field.path, () {
      final edited = _edits[field.path];
      return TextEditingController(
        text: field.formatted(edited ?? _baselineValue(field.path)),
      );
    });
  }

  void _onFieldChanged(_Field field, String raw) {
    setState(() {
      final parsed = field.parse(raw);
      if (parsed == null) {
        // Unparseable input is neither an edit nor a revert: leave the last
        // good value in place so a half-typed "0." can't submit garbage.
        _edits.remove(field.path);
        return;
      }
      if (_sameValue(parsed, _baselineValue(field.path))) {
        _edits.remove(field.path);
      } else {
        _edits[field.path] = parsed;
      }
    });
  }

  static bool _sameValue(Object? a, Object? b) {
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }

  // ------------------------------------------------------------ soft bounds

  /// Matches a canonical field path against a served bound key, which may use
  /// `*` wildcards and either dotted or bracketed index notation
  /// (`upgradeCosts.byRarity.*[3]`). Both sides are normalised so the UI warns
  /// regardless of which notation the backend chose.
  static bool _boundMatches(String boundKey, String path) {
    final key = _normalisePath(boundKey);
    final target = _normalisePath(path);
    final keyParts = key.split('.');
    final targetParts = target.split('.');
    if (keyParts.length != targetParts.length) return false;
    for (var i = 0; i < keyParts.length; i++) {
      if (keyParts[i] == '*') continue;
      if (keyParts[i] != targetParts[i]) return false;
    }
    return true;
  }

  static String _normalisePath(String path) =>
      path.replaceAll('[', '.').replaceAll(']', '');

  /// The bound governing a field, if any. A bound on a coin-range PAIR
  /// (`dailyBox.coinRanges.COMMON`) also governs its two endpoints, which is
  /// how §5.2's `dailyBox.coinRanges.*` reaches the `.0` / `.1` inputs.
  List<double>? _boundFor(String path) {
    for (final candidate in _boundCandidates(path)) {
      for (final entry in _bounds.entries) {
        if (_boundMatches(entry.key, candidate)) return entry.value;
      }
    }
    return null;
  }

  /// The paths a bound key may plausibly be written against, most specific
  /// first. §5.2 names the third slot of an odds triplet by its RARITY
  /// (`positionOdds.*[RARE]`) while the config addresses it by INDEX, and it
  /// bounds a coin range as a PAIR while the form edits its endpoints — so a
  /// literal path match alone would silently never warn.
  static List<String> _boundCandidates(String path) {
    final candidates = <String>[path];
    final lastDot = path.lastIndexOf('.');
    if (lastDot <= 0) return candidates;
    final index = int.tryParse(path.substring(lastDot + 1));
    if (index == null) return candidates;
    final parent = path.substring(0, lastDot);
    final isOddsTriplet =
        parent.startsWith('positionOdds.') ||
        parent.startsWith('dailyBox.odds.');
    if (isOddsTriplet && index >= 0 && index < _rarityKeys.length) {
      candidates.add('$parent.${_rarityKeys[index]}');
    }
    candidates.add(parent);
    return candidates;
  }

  /// Inline warning for the CURRENT value of a field, shown as the admin types
  /// — before submit, per D11/D12.
  String? _warningFor(_Field field) {
    final bound = _boundFor(field.path);
    if (bound == null) return null;
    final value = _edits[field.path] ?? _baselineValue(field.path);
    if (value is! num || !value.isFinite) return null;
    if (value >= bound[0] && value <= bound[1]) return null;
    return 'Outside sane range ${_trim(bound[0])}–${_trim(bound[1])}';
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ------------------------------------------------------------------ diff

  /// Changed paths only, against the CURRENT baseline. Recomputed after a 409
  /// so the admin sees their intent against the newer server state.
  List<_DiffRow> _diff() {
    final rows = <_DiffRow>[];
    for (final field in _fields()) {
      final edited = _edits[field.path];
      if (edited == null) continue;
      final before = _baselineValue(field.path);
      if (_sameValue(edited, before)) continue;
      rows.add(
        _DiffRow(
          field.displayPath,
          field.formatted(before),
          field.formatted(edited),
        ),
      );
    }
    for (final entry in _edits.entries) {
      if (entry.value is! String) continue;
      final before = _baselineValue(entry.key);
      if (_sameValue(entry.value, before)) continue;
      rows.add(
        _DiffRow(entry.key, before?.toString() ?? '—', entry.value.toString()),
      );
    }
    rows.sort((a, b) => a.path.compareTo(b.path));
    return rows;
  }

  // ------------------------------------------------------------------ save

  Future<void> _reviewChanges() async {
    final rows = _diff();
    if (rows.isEmpty) {
      showInfoToast(context, 'Nothing changed.');
      return;
    }
    final confirmed = await _showDiffDialog(rows);
    if (confirmed != true || !mounted) return;
    await _submit(acknowledge: false);
  }

  Future<bool?> _showDiffDialog(List<_DiffRow> rows) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => _BalanceDialog(
        title: 'CONFIRM CHANGES',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saving as version ${_version + 1}. Only these paths change:',
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
            const SizedBox(height: 10),
            for (final row in rows) _DiffTile(row: row),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'CANCEL',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'SAVE',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).roofMid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit({required bool acknowledge}) async {
    final token = _token;
    if (token == null || _saving) return;
    setState(() => _saving = true);
    BalanceConfigSaveResult result;
    try {
      result = await _api.saveAdminBalanceConfig(
        identityToken: token,
        expectedVersion: _version,
        config: _composedConfig(),
        note: _noteController.text.trim(),
        acknowledgeBoundWarnings: acknowledge,
      );
    } catch (e) {
      result = BalanceConfigSaveResult.failed(e.toString());
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await _handleSaveResult(result);
  }

  Future<void> _handleSaveResult(BalanceConfigSaveResult result) async {
    switch (result.status) {
      case BalanceConfigSaveStatus.saved:
        _edits.clear();
        _noteController.clear();
        showInfoToast(context, 'Saved as version ${result.version}.');
        await _load();

      case BalanceConfigSaveStatus.conflict:
        await _handleConflict(result);

      case BalanceConfigSaveStatus.boundWarnings:
        await _handleBoundWarnings(result.warnings);

      case BalanceConfigSaveStatus.error:
        showErrorToast(context, result.message ?? 'Save failed.');
    }
  }

  /// 409: adopt the server's config as the new baseline, re-diff the admin's
  /// unchanged intent against it, and require a fresh confirm. Never merged,
  /// never auto-retried.
  Future<void> _handleConflict(BalanceConfigSaveResult result) async {
    setState(() {
      if (result.config != null && result.currentVersion != null) {
        _adoptServerConfig(result.config!, result.currentVersion!);
      }
      // Edits that now match the newer server value are no longer changes.
      _edits.removeWhere(
        (path, value) => _sameValue(value, _baselineValue(path)),
      );
    });

    final review = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _BalanceDialog(
        title: 'VERSION CONFLICT',
        body: Text(
          'Someone else changed this while you were editing. The server is now '
          'on version ${result.currentVersion ?? '?'}. Your edits were NOT '
          'applied — review them against the new config before saving.',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'DISCARD',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'REVIEW AGAIN',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).roofMid,
              ),
            ),
          ),
        ],
      ),
    );
    if (review != true || !mounted) return;
    await _reviewChanges();
  }

  /// 422: render the server's warnings and block the save behind an explicit
  /// acknowledgement (D11). The toggle is the only path to `true`.
  Future<void> _handleBoundWarnings(List<BalanceBoundWarning> warnings) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var acknowledged = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => _BalanceDialog(
            title: 'BOUND WARNINGS',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'These values are outside their sane ranges. The save is '
                  'allowed, but it will be recorded as an override.',
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(height: 10),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).parchmentDark,
                        border: Border.all(
                          color: AppColors.of(context).error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            warning.path,
                            style: PixelText.title(
                              size: 11,
                              color: AppColors.of(context).error,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            warning.message,
                            style: PixelText.body(
                              size: 11,
                              color: AppColors.of(context).textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                CheckboxListTile(
                  key: const Key('bc-ack-toggle'),
                  value: acknowledged,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) =>
                      setDialogState(() => acknowledged = v ?? false),
                  title: Text(
                    'I understand',
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  'CANCEL',
                  style: PixelText.pill(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ),
              TextButton(
                onPressed: acknowledged
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(
                  'SAVE ANYWAY',
                  style: PixelText.pill(
                    size: 12,
                    color: acknowledged
                        ? AppColors.of(context).error
                        : AppColors.of(context).textMid,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (proceed != true || !mounted) return;
    await _submit(acknowledge: true);
  }

  // -------------------------------------------------------------- rollback

  Future<void> _rollback(BalanceConfigVersion version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _BalanceDialog(
        title: 'ROLL BACK TO V${version.version}',
        body: Text(
          'This copies version ${version.version} forward into a NEW version '
          '${_version + 1} and activates it. History is never rewritten. '
          'Unsaved edits in the form are discarded.',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'CANCEL',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'ROLL BACK',
              style: PixelText.pill(
                size: 12,
                color: AppColors.of(context).error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = _token;
    if (token == null) return;

    setState(() => _saving = true);
    BalanceConfigSaveResult result;
    try {
      result = await _api.rollbackAdminBalanceConfig(
        identityToken: token,
        version: version.version,
        expectedVersion: _version,
      );
    } catch (e) {
      result = BalanceConfigSaveResult.failed(e.toString());
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.status == BalanceConfigSaveStatus.conflict) {
      // Same no-auto-merge rule as a PUT: adopt, tell the admin, stop.
      await _handleConflict(result);
      return;
    }
    if (result.status == BalanceConfigSaveStatus.saved) {
      _edits.clear();
      showInfoToast(context, 'Rolled back as version ${result.version}.');
      await _load();
      return;
    }
    showErrorToast(context, result.message ?? 'Rollback failed.');
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.of(context).textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
            child: Column(
              children: [
                TrailSign(
                  width: boardWidth,
                  child: Text(
                    'BALANCE CONFIG',
                    style: PixelText.title(
                      size: 20,
                      color: AppColors.of(context).textDark,
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
    );
  }

  List<Widget> _buildBody(double boardWidth) {
    switch (_state) {
      case _LoadState.loading:
        return [
          SizedBox(height: 40),
          Center(
            child: CircularProgressIndicator(
              color: AppColors.of(context).accent,
            ),
          ),
        ];

      case _LoadState.unsupported:
        return [
          ContentBoard(
            width: boardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UNAVAILABLE',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Balance config is not supported by this backend. Deploy the '
                  'backend that serves /admin/balance-config, then reopen this '
                  'screen.',
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
            ),
          ),
        ];

      case _LoadState.error:
        return [
          ContentBoard(
            width: boardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COULD NOT LOAD',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError ?? 'Unknown error.',
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(height: 12),
                PillButton(
                  label: 'RETRY',
                  fullWidth: true,
                  fontSize: 12,
                  onPressed: _load,
                ),
              ],
            ),
          ),
        ];

      case _LoadState.ready:
        return _buildForm(boardWidth);
    }
  }

  List<Widget> _buildForm(double boardWidth) {
    final changed = _diff().length;
    return [
      ContentBoard(
        width: boardWidth,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'VERSION $_version',
                style: PixelText.title(
                  size: 16,
                  color: AppColors.of(context).textDark,
                ),
              ),
            ),
            Text(
              changed == 0 ? 'no changes' : '$changed changed',
              style: PixelText.body(
                size: 11,
                color: changed == 0
                    ? AppColors.of(context).textMid
                    : AppColors.of(context).roofMid,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      _section(boardWidth, 'RARITY', [
        _hint(
          'Canonical rarity per powerup. Drives drops, upgrade price and '
          'the colour every client shows.',
        ),
        ..._rarityRows(),
      ]),

      _section(boardWidth, 'DROP POOL', [
        _hint(
          'Which types can drop in each tier. Store-only types are '
          'excluded server-side and are not editable here.',
        ),
        ..._dropPoolRows(),
      ]),

      _section(boardWidth, 'POSITION ODDS', [
        _hint(
          'COMMON / UNCOMMON / RARE for the leader (first) and the '
          'trailer (last). Each row must sum to 1.0.',
        ),
        for (final row in const ['first', 'last'])
          _tripletRow('positionOdds.$row', row.toUpperCase()),
      ]),

      _section(boardWidth, 'UPGRADE LADDERS', [
        _hint('Cost to reach each tier. Index 0 is always 0.'),
        for (final rarity in _rarityKeys)
          _ladderRow('upgradeCosts.byRarity.$rarity', rarity),
      ]),

      _section(boardWidth, 'LUCKY HORSESHOE', [
        _hint(
          'Chance of a RARE roll at each upgrade level. Level 3 should '
          'be 1.0.',
        ),
        _quadRow('luckyHorseshoe.rareChanceByLevel', 'RARE CHANCE'),
      ]),

      _section(boardWidth, 'DAILY BOX', [
        _numberField(_Field.integer('dailyBox.streakCap'), 'STREAK CAP'),
        const SizedBox(height: 10),
        for (final row in const ['first', 'last'])
          _tripletRow('dailyBox.odds.$row', 'ODDS ${row.toUpperCase()}'),
        for (final tier in _coinRangeKeys) _coinRangeRow(tier),
        _numberField(
          _Field.decimal('dailyBox.rareCoinsShare'),
          'RARE COINS SHARE',
        ),
        const SizedBox(height: 12),
        _weightModeRow(),
      ]),

      _section(boardWidth, 'PUBLISH', [
        TextField(
          controller: _noteController,
          style: PixelText.body(
            size: 12,
            color: AppColors.of(context).textDark,
          ),
          decoration: InputDecoration(
            labelText: 'Note (why this change)',
            labelStyle: PixelText.body(
              size: 11,
              color: AppColors.of(context).textMid,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        PillButton(
          label: _saving ? 'SAVING...' : 'REVIEW CHANGES',
          fullWidth: true,
          fontSize: 13,
          onPressed: _saving ? null : _reviewChanges,
        ),
      ]),

      _section(boardWidth, 'VERSION HISTORY', [
        if (_versions.isEmpty)
          Text(
            'No history returned by the backend.',
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          )
        else
          for (final version in _versions) _versionRow(version),
      ]),
    ];
  }

  Widget _section(double width, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ContentBoard(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: PixelText.title(
                size: 14,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: PixelText.body(size: 10, color: AppColors.of(context).textMid),
    ),
  );

  List<Widget> _rarityRows() {
    final raw = _baseline['rarityByType'];
    if (raw is! Map || raw.isEmpty) {
      return [
        Text(
          'This config carries no rarityByType block.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
      ];
    }
    final types = raw.keys.map((k) => k.toString()).toList()..sort();
    return [
      for (final type in types)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  type,
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              _RarityPicker(
                value:
                    (_edits['rarityByType.$type'] as String?) ??
                    raw[type]?.toString() ??
                    'COMMON',
                onChanged: (value) => setState(() {
                  if (value == raw[type]?.toString()) {
                    _edits.remove('rarityByType.$type');
                  } else {
                    _edits['rarityByType.$type'] = value;
                  }
                }),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _dropPoolRows() {
    final pool = _baseline['dropPool'];
    if (pool is! Map || pool.isEmpty) {
      return [
        Text(
          'This config carries no dropPool block.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
      ];
    }
    return [
      for (final tier in pool.keys.map((k) => k.toString()))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tier,
                style: PixelText.title(
                  size: 11,
                  color: AppColors.of(context).textDark,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry
                      in (pool[tier] is List ? (pool[tier] as List) : const []))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).parchmentDark,
                        border: Border.all(
                          color: AppColors.of(context).parchmentBorder,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.toString(),
                        style: PixelText.body(
                          size: 10,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  Widget _tripletRow(String base, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PixelText.title(
              size: 11,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: _numberField(
                    _Field.decimal('$base.$i'),
                    _rarityKeys[i],
                  ),
                ),
                if (i < 2) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _ladderRow(String base, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PixelText.title(
              size: 11,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Expanded(
                  child: _numberField(_Field.integer('$base.$i'), 'L$i'),
                ),
                if (i < 3) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _quadRow(String base, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PixelText.title(
              size: 11,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Expanded(
                  child: _numberField(_Field.decimal('$base.$i'), 'L$i'),
                ),
                if (i < 3) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _coinRangeRow(String tier) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COINS $tier',
            style: PixelText.title(
              size: 11,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  _Field.integer('dailyBox.coinRanges.$tier.0'),
                  'MIN',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  _Field.integer('dailyBox.coinRanges.$tier.1'),
                  'MAX',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weightModeRow() {
    const path = 'dailyBox.accessoryWeightMode';
    final current =
        (_edits[path] as String?) ??
        _baselineValue(path)?.toString() ??
        'inverse';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCESSORY WEIGHT MODE',
          style: PixelText.title(
            size: 11,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final mode in _weightModes)
              ChoiceChip(
                label: Text(
                  mode,
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                selected: current == mode,
                onSelected: (_) => setState(() {
                  if (mode == _baselineValue(path)?.toString()) {
                    _edits.remove(path);
                  } else {
                    _edits[path] = mode;
                  }
                }),
              ),
          ],
        ),
        if (current == 'legacy')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'legacy is the 36x prestige inversion — it makes 1500-coin '
              'accessories the most common daily-box drop. Retained only so a '
              'rollback can reproduce history.',
              style: PixelText.body(
                size: 10,
                color: AppColors.of(context).error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _numberField(_Field field, String label) {
    final controller = _controllerFor(field);
    final warning = _warningFor(field);
    final edited = _edits.containsKey(field.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: Key('bc-${field.path}'),
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(
            decimal: !field.isInteger,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              field.isInteger ? RegExp(r'[0-9-]') : RegExp(r'[0-9.\-]'),
            ),
          ],
          onChanged: (raw) => _onFieldChanged(field, raw),
          style: PixelText.number(
            size: 13,
            color: AppColors.of(context).textDark,
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: PixelText.body(
              size: 10,
              color: AppColors.of(context).textMid,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: warning != null
                    ? AppColors.of(context).error
                    : edited
                    ? AppColors.of(context).roofMid
                    : AppColors.of(context).parchmentBorder,
                width: 2,
              ),
            ),
          ),
        ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 4),
            child: Text(
              warning,
              style: PixelText.body(
                size: 9,
                color: AppColors.of(context).error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _versionRow(BalanceConfigVersion version) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.of(context).parchmentDark,
          border: Border.all(
            color: version.active
                ? AppColors.of(context).roofMid
                : AppColors.of(context).parchmentBorder,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'v${version.version}',
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      if (version.active) ...[
                        const SizedBox(width: 6),
                        Text(
                          'ACTIVE',
                          style: PixelText.pill(
                            size: 9,
                            color: AppColors.of(context).roofMid,
                          ),
                        ),
                      ],
                      if (version.boundOverride) ...[
                        const SizedBox(width: 6),
                        Text(
                          'OVERRIDE',
                          style: PixelText.pill(
                            size: 9,
                            color: AppColors.of(context).error,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (version.note != null && version.note!.isNotEmpty)
                    Text(
                      version.note!,
                      style: PixelText.body(
                        size: 10,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                ],
              ),
            ),
            if (!version.active)
              TextButton(
                onPressed: _saving ? null : () => _rollback(version),
                child: Text(
                  'ROLL BACK',
                  style: PixelText.pill(
                    size: 10,
                    color: AppColors.of(context).error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An editable scalar leaf of the config JSON.
class _Field {
  const _Field._(this.path, this.isInteger);

  const _Field.integer(String path) : this._(path, true);
  const _Field.decimal(String path) : this._(path, false);

  final String path;
  final bool isInteger;

  /// `positionOdds.first.0` reads better as `positionOdds.first[0]` in a diff.
  String get displayPath {
    final lastDot = path.lastIndexOf('.');
    if (lastDot <= 0) return path;
    final tail = path.substring(lastDot + 1);
    if (int.tryParse(tail) == null) return path;
    return '${path.substring(0, lastDot)}[$tail]';
  }

  Object? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (isInteger) return int.tryParse(text);
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  String formatted(Object? value) {
    if (value == null) return '';
    if (value is! num) return value.toString();
    if (isInteger) return value.toInt().toString();
    // A whole decimal renders as "1.0", never "1", so a JSON `1` and a typed
    // `1.0` read as the same value on both sides of a diff.
    if (value == value.roundToDouble() && value.abs() >= 1) {
      return value.toDouble().toStringAsFixed(1);
    }
    return value.toString();
  }
}

class _DiffRow {
  const _DiffRow(this.path, this.before, this.after);
  final String path;
  final String before;
  final String after;
}

class _DiffTile extends StatelessWidget {
  const _DiffTile({required this.row});
  final _DiffRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.of(context).parchmentDark,
          border: Border.all(color: AppColors.of(context).roofMid, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.path,
              style: PixelText.body(
                size: 11,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${row.before} → ${row.after}',
              style: PixelText.number(
                size: 13,
                color: AppColors.of(context).roofMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RarityPicker extends StatelessWidget {
  const _RarityPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: const ['COMMON', 'UNCOMMON', 'RARE'].contains(value)
          ? value
          : 'COMMON',
      underline: const SizedBox.shrink(),
      style: PixelText.body(size: 11, color: AppColors.of(context).textDark),
      items: const [
        DropdownMenuItem(value: 'COMMON', child: Text('COMMON')),
        DropdownMenuItem(value: 'UNCOMMON', child: Text('UNCOMMON')),
        DropdownMenuItem(value: 'RARE', child: Text('RARE')),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

/// The editor's one dialog shell, so a diff, a conflict and a bound warning
/// all read as the same object rather than three unrelated alerts.
class _BalanceDialog extends StatelessWidget {
  const _BalanceDialog({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.of(context).parchmentLight,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.of(context).roofDark, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: PixelText.title(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(child: SingleChildScrollView(child: body)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}
