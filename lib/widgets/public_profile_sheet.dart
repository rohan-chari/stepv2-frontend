import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import 'app_avatar.dart';
import 'error_toast.dart';
import 'home_course_track.dart' show CapybaraCustomizationPreview;
import 'pill_button.dart';

enum PublicProfileRelationship {
  unknown,
  self,
  none,
  outgoing,
  incoming,
  friends,
}

@immutable
class PublicProfileRelationshipSnapshot {
  const PublicProfileRelationshipSnapshot(
    this.relationship, {
    this.friendshipId,
  });

  final PublicProfileRelationship relationship;
  final String? friendshipId;
}

Future<void> showPublicProfileSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
  required String userId,
  required String fallbackName,
  String? fallbackPhotoUrl,
  String? fallbackRealName,
  PublicProfileRelationship initialRelationship =
      PublicProfileRelationship.unknown,
  String? friendshipId,
  VoidCallback? onChanged,
}) {
  final targetId = userId.trim();
  if (targetId.isEmpty || !context.mounted) return Future<void>.value();
  // Resolve palette while the launching context is active. The sheet route
  // can outlive its caller during a tab transition.
  final palette = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    builder: (sheetContext) => Container(
      key: const ValueKey('public-profile-sheet'),
      decoration: BoxDecoration(
        color: palette.parchment,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .55,
        maxChildSize: .94,
        builder: (context, controller) => PublicProfilePanel(
          authService: authService,
          backendApiService: backendApiService,
          userId: targetId,
          fallbackName: fallbackName,
          fallbackPhotoUrl: fallbackPhotoUrl,
          fallbackRealName: fallbackRealName,
          initialRelationship: initialRelationship,
          friendshipId: friendshipId,
          onChanged: onChanged,
          scrollController: controller,
        ),
      ),
    ),
  );
}

class PublicProfilePanel extends StatefulWidget {
  const PublicProfilePanel({
    super.key,
    required this.authService,
    required this.backendApiService,
    required this.userId,
    required this.fallbackName,
    this.fallbackPhotoUrl,
    this.fallbackRealName,
    this.initialRelationship = PublicProfileRelationship.unknown,
    this.friendshipId,
    this.onChanged,
    this.scrollController,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final String userId;
  final String fallbackName;
  final String? fallbackPhotoUrl;
  final String? fallbackRealName;
  final PublicProfileRelationship initialRelationship;
  final String? friendshipId;
  final VoidCallback? onChanged;
  final ScrollController? scrollController;

  @override
  State<PublicProfilePanel> createState() => _PublicProfilePanelState();
}

enum _LoadState { loading, refreshing, loaded, error }

class _PublicProfilePanelState extends State<PublicProfilePanel> {
  Map<String, dynamic>? _profile;
  _LoadState _profileState = _LoadState.loading;
  int? _profileErrorStatus;
  late PublicProfileRelationshipSnapshot _relationship;
  late _LoadState _relationshipState;
  bool _busy = false;
  int _profileGeneration = 0;
  int _relationshipGeneration = 0;
  int _mutationGeneration = 0;
  bool _authInvalidated = false;
  String? _authTokenAtStart;
  String? _authUserAtStart;

  @override
  void initState() {
    super.initState();
    final initialId = _nonEmpty(widget.friendshipId);
    _relationship = PublicProfileRelationshipSnapshot(
      widget.initialRelationship,
      friendshipId: initialId,
    );
    _relationshipState =
        widget.initialRelationship == PublicProfileRelationship.unknown
        ? _LoadState.loading
        : _LoadState.refreshing;
    widget.authService.addListener(_onAuthChanged);
    _authTokenAtStart = widget.authService.authToken;
    _authUserAtStart = widget.authService.userId;
    _loadProfile();
    if (widget.authService.userId == widget.userId) {
      _relationship = const PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.self,
      );
      _relationshipState = _LoadState.loaded;
    } else {
      _loadRelationship();
    }
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    _profileGeneration++;
    _relationshipGeneration++;
    _mutationGeneration++;
    super.dispose();
  }

  bool _current({int? profile, int? relationship, int? mutation}) {
    if (!mounted || _authInvalidated) return false;
    if (profile != null && profile != _profileGeneration) return false;
    if (relationship != null && relationship != _relationshipGeneration) {
      return false;
    }
    if (mutation != null && mutation != _mutationGeneration) return false;
    return widget.authService.authToken == _authTokenAtStart &&
        widget.authService.userId == _authUserAtStart &&
        widget.userId.trim().isNotEmpty;
  }

  void _onAuthChanged() {
    if (widget.authService.authToken == _authTokenAtStart &&
        widget.authService.userId == _authUserAtStart) {
      return;
    }
    _authInvalidated = true;
    _profileGeneration++;
    _relationshipGeneration++;
    _mutationGeneration++;
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _loadProfile() async {
    final token = widget.authService.authToken;
    final generation = ++_profileGeneration;
    if (token == null || token.isEmpty) {
      if (_current(profile: generation)) {
        setState(() => _profileState = _LoadState.error);
      }
      return;
    }
    try {
      final data = await widget.backendApiService.fetchPublicProfile(
        identityToken: token,
        userId: widget.userId,
      );
      if (!_current(profile: generation)) return;
      final projected = _projectMap(data);
      final rawUser = _map(projected['user']);
      final returnedId = _nonEmpty(rawUser['id']);
      if (returnedId != null && returnedId != widget.userId) {
        setState(() {
          _profileState = _LoadState.error;
          _profileErrorStatus = 404;
        });
        return;
      }
      setState(() {
        _profile = projected;
        _profileState = _LoadState.loaded;
        _profileErrorStatus = null;
      });
    } catch (error) {
      if (!_current(profile: generation)) return;
      setState(() {
        _profileState = _LoadState.error;
        _profileErrorStatus = error is ApiException ? error.statusCode : null;
      });
    }
  }

  Future<void> _loadRelationship({bool retry = false}) async {
    final token = widget.authService.authToken;
    final generation = ++_relationshipGeneration;
    final mutationAtStart = _mutationGeneration;
    if (token == null || token.isEmpty) {
      if (_current(relationship: generation)) {
        setState(() => _relationshipState = _LoadState.error);
      }
      return;
    }
    if (retry && _relationshipState != _LoadState.loading && mounted) {
      setState(() => _relationshipState = _LoadState.refreshing);
    }
    try {
      final data = await widget.backendApiService.fetchFriends(
        identityToken: token,
      );
      if (!_current(relationship: generation) ||
          mutationAtStart != _mutationGeneration) {
        return;
      }
      final resolved = _relationshipFromPayload(data);
      setState(() {
        _relationship = resolved;
        _relationshipState = _LoadState.loaded;
      });
    } catch (_) {
      if (!_current(relationship: generation)) return;
      setState(() => _relationshipState = _LoadState.error);
    }
  }

  Future<void> _mutate(_Mutation action) async {
    if (_busy || !_canMutate(action)) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final before = _relationship;
    final mutation = ++_mutationGeneration;
    ++_relationshipGeneration;
    setState(() => _busy = true);
    try {
      Map<String, dynamic>? response;
      if (action == _Mutation.add) {
        response = await widget.backendApiService.sendFriendRequest(
          identityToken: token,
          addresseeId: widget.userId,
        );
      } else if (action == _Mutation.accept || action == _Mutation.decline) {
        final id = before.friendshipId;
        if (id == null) return;
        response = await widget.backendApiService.respondToFriendRequest(
          identityToken: token,
          friendshipId: id,
          accept: action == _Mutation.accept,
        );
      } else {
        final id = before.friendshipId;
        if (id == null) return;
        await widget.backendApiService.removeFriend(
          identityToken: token,
          friendshipId: id,
        );
      }
      if (!_current(mutation: mutation)) return;
      final next = _nextRelationship(action, response);
      setState(() {
        _relationship = next;
        _relationshipState = _LoadState.loaded;
        _busy = false;
      });
      widget.onChanged?.call();
      _reconcileAfterMutation(mutation, next);
    } catch (error) {
      if (!_current(mutation: mutation)) return;
      setState(() => _busy = false);
      if (mounted) {
        showErrorToast(
          context,
          'Couldn’t update friendship. Please try again.',
        );
      }
      _reconcileAfterFailure(mutation, before);
    }
  }

  Future<void> _reconcileAfterMutation(
    int mutation,
    PublicProfileRelationshipSnapshot local,
  ) async {
    if (!_current(mutation: mutation)) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final generation = ++_relationshipGeneration;
    try {
      final data = await widget.backendApiService.fetchFriends(
        identityToken: token,
      );
      if (!_current(relationship: generation, mutation: mutation)) return;
      final resolved = _relationshipFromPayload(data);
      if (!_sameRelationship(local, resolved)) {
        setState(() => _relationship = resolved);
        widget.onChanged?.call();
      }
    } catch (_) {
      // The successful local transition remains usable if reconciliation is
      // temporarily unavailable.
    }
  }

  Future<void> _reconcileAfterFailure(
    int mutation,
    PublicProfileRelationshipSnapshot before,
  ) async {
    if (!_current(mutation: mutation)) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final generation = ++_relationshipGeneration;
    try {
      final data = await widget.backendApiService.fetchFriends(
        identityToken: token,
      );
      if (!_current(relationship: generation, mutation: mutation)) return;
      final resolved = _relationshipFromPayload(data);
      if (!_sameRelationship(before, resolved)) {
        setState(() => _relationship = resolved);
        widget.onChanged?.call();
      }
    } catch (_) {
      if (_current(mutation: mutation)) setState(() => _relationship = before);
    }
  }

  bool _canMutate(_Mutation action) {
    final relation = _relationship.relationship;
    if (action == _Mutation.add) {
      return relation == PublicProfileRelationship.none;
    }
    if (action == _Mutation.accept || action == _Mutation.decline) {
      return relation == PublicProfileRelationship.incoming &&
          _relationship.friendshipId != null;
    }
    return (relation == PublicProfileRelationship.outgoing ||
            relation == PublicProfileRelationship.friends) &&
        _relationship.friendshipId != null;
  }

  PublicProfileRelationshipSnapshot _nextRelationship(
    _Mutation action,
    Map<String, dynamic>? response,
  ) {
    if (action == _Mutation.add) {
      final friendship = _map(response?['friendship']);
      final id = _nonEmpty(friendship['id']);
      final status = _nonEmpty(friendship['status'])?.toUpperCase();
      return PublicProfileRelationshipSnapshot(
        status == 'ACCEPTED'
            ? PublicProfileRelationship.friends
            : PublicProfileRelationship.outgoing,
        friendshipId: id,
      );
    }
    if (action == _Mutation.accept) {
      return PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.friends,
        friendshipId: _relationship.friendshipId,
      );
    }
    return const PublicProfileRelationshipSnapshot(
      PublicProfileRelationship.none,
    );
  }

  Future<void> _confirm(_Mutation action) async {
    final name = _displayName;
    final remove = action == _Mutation.remove;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.of(dialogContext).parchment,
        title: Text(
          remove ? 'REMOVE FRIEND?' : 'CANCEL FRIEND REQUEST?',
          style: PixelText.title(
            size: 16,
            color: AppColors.of(dialogContext).textDark,
          ),
        ),
        content: Text(
          remove
              ? 'Remove $name from your friends?'
              : 'Cancel your request to $name?',
          style: PixelText.body(
            size: 13,
            color: AppColors.of(dialogContext).textMid,
          ),
        ),
        actions: [
          PillButton(
            label: 'KEEP',
            variant: PillButtonVariant.secondary,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          PillButton(
            label: remove ? 'REMOVE FRIEND' : 'CANCEL REQUEST',
            variant: PillButtonVariant.destructive,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _mutate(action);
  }

  String get _displayName {
    final user = _map(_profile?['user']);
    return _nonEmpty(user['displayName']) ??
        _nonEmpty(widget.fallbackName) ??
        'Runner';
  }

  String? get _photo =>
      _nonEmpty(_map(_profile?['user'])['profilePhotoUrl']) ??
      _nonEmpty(widget.fallbackPhotoUrl);

  String? get _requestRealName => _nonEmpty(widget.fallbackRealName);

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final controller = widget.scrollController;
    final content = ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: palette.parchmentBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        CustomPaint(
          painter: const ArcadeCheckerPainter(drawBottomStripe: false),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                AppAvatar(name: _displayName, imageUrl: _photo, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_requestRealName != null) ...[
                        Text(
                          _requestRealName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.title(
                            size: 16,
                            color: palette.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        atName(_displayName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _requestRealName == null
                            ? PixelText.title(size: 18, color: palette.textDark)
                            : PixelText.body(size: 13, color: palette.textMid),
                      ),
                      const SizedBox(height: 4),
                      _relationshipStatus(),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('public-profile-close'),
                  tooltip: 'Close profile',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.close, color: palette.textMid),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_profileState == _LoadState.loading) _loading() else _profileBody(),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey(
              '${_relationship.relationship.name}-${_busy ? 'busy' : 'ready'}',
            ),
            child: _relationshipActions(),
          ),
        ),
      ],
    );
    return Material(
      color: palette.parchment,
      child: SafeArea(child: content),
    );
  }

  Widget _loading() => Container(
    key: const ValueKey('public-profile-loading'),
    padding: const EdgeInsets.all(24),
    child: const Center(child: CircularProgressIndicator()),
  );

  Widget _profileBody() {
    final palette = AppColors.of(context);
    final user = _map(_profile?['user']);
    final stats = _map(_profile?['stats']);
    final podium = _map(stats['racePodiums']);
    final average = _finiteNonNegative(stats['avgStepsPerDay']);
    final error = _profileState == _LoadState.error;
    return Column(
      children: [
        if (error)
          Container(
            key: const ValueKey('public-profile-retry'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.parchmentLight,
              border: Border.all(color: palette.parchmentBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _profileErrorStatus == 404
                        ? 'PROFILE UNAVAILABLE'
                        : 'COULDN’T LOAD STATS',
                    style: PixelText.body(size: 12, color: palette.textMid),
                  ),
                ),
                TextButton(onPressed: _loadProfile, child: const Text('RETRY')),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Profile character',
          child: Container(
            key: const ValueKey('public-profile-character'),
            height: 148,
            alignment: Alignment.center,
            child: CapybaraCustomizationPreview(
              accessories: _accessories(user['equippedAccessories']),
              animal: _nonEmpty(user['equippedAnimal']),
              size: 140,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _statPlate(podium, average),
      ],
    );
  }

  Widget _statPlate(Map<String, dynamic> podium, num? average) {
    final palette = AppColors.of(context);
    Widget medal(String key, String label, Color color, String valueKey) {
      final value = _finiteNonNegative(podium[key]);
      return Expanded(
        child: Container(
          key: ValueKey('public-profile-podium-$valueKey'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(label, style: PixelText.title(size: 15, color: color)),
              const SizedBox(height: 3),
              Text(
                value == null ? '—' : '${value.round()}',
                style: PixelText.body(size: 14, color: palette.textDark),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.parchmentLight,
        border: Border.all(color: palette.parchmentBorder),
        boxShadow: [
          BoxShadow(color: palette.woodShadow, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              medal('first', '1ST', palette.medalGold, 'first'),
              medal('second', '2ND', palette.medalSilver, 'second'),
              medal('third', '3RD', palette.medalBronze, 'third'),
            ],
          ),
          Divider(height: 1, color: palette.parchmentBorder),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              key: const ValueKey('public-profile-average-steps'),
              children: [
                Text(
                  'AVG STEPS / DAY',
                  style: PixelText.title(size: 12, color: palette.textMid),
                ),
                const SizedBox(height: 3),
                Text(
                  average == null ? '—' : '${average.round()}',
                  style: PixelText.body(size: 16, color: palette.textDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relationshipStatus() {
    final palette = AppColors.of(context);
    final relation = _relationship.relationship;
    final text = switch (relation) {
      PublicProfileRelationship.self => "THAT'S YOU",
      PublicProfileRelationship.outgoing => 'REQUESTED',
      PublicProfileRelationship.incoming => 'WANTS TO BE FRIENDS',
      PublicProfileRelationship.friends => 'FRIENDS',
      PublicProfileRelationship.unknown =>
        _relationshipState == _LoadState.error
            ? 'FRIENDSHIP STATUS UNAVAILABLE'
            : 'CHECKING FRIENDSHIP…',
      PublicProfileRelationship.none => '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Relationship status $text',
      child: Text(
        key: const ValueKey('public-profile-relationship-status'),
        text,
        style: PixelText.body(size: 11, color: palette.textMid),
      ),
    );
  }

  Widget _relationshipActions() {
    final relation = _relationship.relationship;
    if (relation == PublicProfileRelationship.self) {
      return const SizedBox.shrink();
    }
    if (relation == PublicProfileRelationship.unknown &&
        _relationshipState == _LoadState.error) {
      return TextButton(
        onPressed: _loadRelationship,
        child: const Text('TRY AGAIN'),
      );
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    switch (relation) {
      case PublicProfileRelationship.none:
        return _actionButton(
          'ADD FRIEND',
          'public-profile-action-add',
          () => _mutate(_Mutation.add),
        );
      case PublicProfileRelationship.outgoing:
        return _relationship.friendshipId == null
            ? const SizedBox.shrink()
            : _actionButton(
                'CANCEL REQUEST',
                'public-profile-action-cancel',
                () => _confirm(_Mutation.cancel),
              );
      case PublicProfileRelationship.incoming:
        return Row(
          children: [
            Expanded(
              child: _actionButton(
                'ACCEPT',
                'public-profile-action-accept',
                () => _mutate(_Mutation.accept),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                'DECLINE',
                'public-profile-action-decline',
                () => _mutate(_Mutation.decline),
                destructive: true,
              ),
            ),
          ],
        );
      case PublicProfileRelationship.friends:
        return _relationship.friendshipId == null
            ? const SizedBox.shrink()
            : _actionButton(
                'REMOVE FRIEND',
                'public-profile-action-remove',
                () => _confirm(_Mutation.remove),
                destructive: true,
              );
      case PublicProfileRelationship.self:
      case PublicProfileRelationship.unknown:
        return const SizedBox.shrink();
    }
  }

  Widget _actionButton(
    String label,
    String key,
    VoidCallback action, {
    bool destructive = false,
  }) => Semantics(
    button: true,
    label: label,
    child: PillButton(
      key: ValueKey(key),
      label: label,
      fullWidth: true,
      variant: destructive
          ? PillButtonVariant.destructive
          : PillButtonVariant.primary,
      onPressed: action,
    ),
  );

  static Map<String, dynamic> _projectMap(Object? value) => _map(value);

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? <String, dynamic>{
          for (final entry in value.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : <String, dynamic>{};

  static List<Map<String, dynamic>> _accessories(Object? value) => value is List
      ? <Map<String, dynamic>>[
          for (final item in value)
            if (item is Map) _map(item),
        ]
      : const <Map<String, dynamic>>[];

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final result = value.trim();
    return result.isEmpty ? null : result;
  }

  static num? _finiteNonNegative(Object? value) {
    if (value is num && value.isFinite && value >= 0) return value;
    return null;
  }

  PublicProfileRelationshipSnapshot _relationshipFromPayload(
    Map<String, dynamic> data,
  ) {
    final userId = widget.userId;
    if (widget.authService.userId == userId) {
      return const PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.self,
      );
    }
    final friends = _maps(data['friends']);
    final friend = friends
        .where((entry) => _extractId(entry) == userId)
        .firstOrNull;
    if (friend != null) {
      return PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.friends,
        friendshipId: _extractFriendshipId(friend),
      );
    }
    final pending = _map(data['pending']);
    final outgoing = _maps(pending['outgoing']);
    final outgoingMatch = outgoing
        .where((entry) => _extractId(entry) == userId)
        .firstOrNull;
    if (outgoingMatch != null) {
      return PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.outgoing,
        friendshipId: _extractFriendshipId(outgoingMatch),
      );
    }
    final incoming = _maps(pending['incoming']);
    final incomingMatch = incoming
        .where((entry) => _extractId(entry) == userId)
        .firstOrNull;
    if (incomingMatch != null) {
      return PublicProfileRelationshipSnapshot(
        PublicProfileRelationship.incoming,
        friendshipId: _extractFriendshipId(incomingMatch),
      );
    }
    return const PublicProfileRelationshipSnapshot(
      PublicProfileRelationship.none,
    );
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? <Map<String, dynamic>>[
          for (final item in value)
            if (item is Map) _map(item),
        ]
      : const <Map<String, dynamic>>[];

  static String? _extractId(Map<String, dynamic> value) {
    for (final key in const [
      'id',
      'userId',
      'friendId',
      'requesterId',
      'addresseeId',
    ]) {
      final id = _nonEmpty(value[key]);
      if (id != null) return id;
    }
    for (final key in const ['user', 'friend', 'requester', 'addressee']) {
      final nested = value[key];
      if (nested is Map) {
        final id = _extractId(_map(nested));
        if (id != null) return id;
      }
    }
    return null;
  }

  static String? _extractFriendshipId(Map<String, dynamic> value) {
    for (final key in const ['friendshipId', 'id']) {
      final id = _nonEmpty(value[key]);
      if (id != null && (key == 'friendshipId' || value['status'] != null)) {
        return id;
      }
    }
    return null;
  }

  static bool _sameRelationship(
    PublicProfileRelationshipSnapshot a,
    PublicProfileRelationshipSnapshot b,
  ) => a.relationship == b.relationship && a.friendshipId == b.friendshipId;
}

enum _Mutation { add, accept, decline, cancel, remove }

// Kept for older callers that imported the old file's private status by way
// of widget expectations; no second profile state owner exists.
extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
