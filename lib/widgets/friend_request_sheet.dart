import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import 'app_avatar.dart';
import 'error_toast.dart';
import 'info_toast.dart';
import 'pill_button.dart';

enum _FriendStatus { loading, self, friends, outgoing, incoming, none, error }

Future<void> showFriendRequestSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
  required String userId,
  required String displayName,
  String? profilePhotoUrl,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.of(context).parchment,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _FriendRequestSheet(
      authService: authService,
      backendApiService: backendApiService,
      userId: userId,
      displayName: displayName,
      profilePhotoUrl: profilePhotoUrl,
      onChanged: onChanged,
    ),
  );
}

class _FriendRequestSheet extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final VoidCallback? onChanged;

  const _FriendRequestSheet({
    required this.authService,
    required this.backendApiService,
    required this.userId,
    required this.displayName,
    this.profilePhotoUrl,
    this.onChanged,
  });

  @override
  State<_FriendRequestSheet> createState() => _FriendRequestSheetState();
}

class _FriendRequestSheetState extends State<_FriendRequestSheet> {
  _FriendStatus _status = _FriendStatus.loading;
  String? _incomingFriendshipId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final myId = widget.authService.userId;
    if (myId != null && myId == widget.userId) {
      setState(() => _status = _FriendStatus.self);
      return;
    }

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() => _status = _FriendStatus.error);
      return;
    }

    try {
      final data = await widget.backendApiService.fetchFriends(
        identityToken: token,
      );
      if (!mounted) return;

      final friends =
          (data['friends'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (friends.any((f) => _matchesUser(f, widget.userId))) {
        setState(() => _status = _FriendStatus.friends);
        return;
      }

      final pending = data['pending'] as Map<String, dynamic>? ?? {};
      final outgoing =
          (pending['outgoing'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (outgoing.any((r) => _matchesUser(r, widget.userId))) {
        setState(() => _status = _FriendStatus.outgoing);
        return;
      }

      final incoming =
          (pending['incoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final incomingMatch = incoming.firstWhere(
        (r) => _matchesUser(r, widget.userId),
        orElse: () => const {},
      );
      if (incomingMatch.isNotEmpty) {
        setState(() {
          _incomingFriendshipId = incomingMatch['friendshipId'] as String?;
          _status = _FriendStatus.incoming;
        });
        return;
      }

      setState(() => _status = _FriendStatus.none);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _FriendStatus.error);
    }
  }

  /// Whether [entry] (a friend or pending-request object from `/friends`)
  /// refers to [userId]. The backend uses different shapes across collections:
  /// friends carry a top-level `id`, while pending requests nest the other
  /// person under `user: { id, ... }`. Match defensively across both so older
  /// or newer backend payloads still resolve correctly.
  static bool _matchesUser(Map<String, dynamic> entry, String userId) {
    return _extractUserId(entry) == userId;
  }

  static String? _extractUserId(Map<String, dynamic> data) {
    for (final key in const ['id', 'userId', 'friendId', 'addresseeId']) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }
    for (final key in const ['user', 'friend', 'addressee', 'requester']) {
      final value = data[key];
      if (value is Map<String, dynamic>) {
        final nested = _extractUserId(value);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<void> _send() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.backendApiService.sendFriendRequest(
        identityToken: token,
        addresseeId: widget.userId,
      );
      if (!mounted) return;
      showInfoToast(context, 'Friend request sent');
      widget.onChanged?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final raw = e.toString();
      if (raw.contains('already') || raw.contains('existing')) {
        showErrorToast(context, 'You already have a request with this user.');
      } else {
        showErrorToast(
          context,
          'Couldn’t send friend request. Please try again.',
        );
      }
    }
  }

  Future<void> _accept() async {
    final token = widget.authService.authToken;
    final friendshipId = _incomingFriendshipId;
    if (token == null || token.isEmpty || friendshipId == null) return;
    setState(() => _busy = true);
    try {
      await widget.backendApiService.respondToFriendRequest(
        identityToken: token,
        friendshipId: friendshipId,
        accept: true,
      );
      if (!mounted) return;
      showInfoToast(context, 'Friend request accepted');
      widget.onChanged?.call();
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorToast(context, 'Couldn’t accept request. Please try again.');
    }
  }

  Widget _buildActionRow() {
    switch (_status) {
      case _FriendStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _FriendStatus.self:
        return Text(
          "That's you!",
          style: PixelText.body(size: 13, color: AppColors.of(context).textMid),
        );
      case _FriendStatus.friends:
        return const PillButton(
          label: 'FRIENDS',
          icon: Icons.check,
          variant: PillButtonVariant.primary,
          fontSize: 13,
          fullWidth: true,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: null,
        );
      case _FriendStatus.outgoing:
        return const PillButton(
          label: 'REQUESTED',
          variant: PillButtonVariant.secondary,
          fontSize: 13,
          fullWidth: true,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: null,
        );
      case _FriendStatus.incoming:
        return PillButton(
          label: _busy ? 'ACCEPTING…' : 'ACCEPT REQUEST',
          variant: PillButtonVariant.primary,
          fontSize: 13,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: _busy ? null : _accept,
        );
      case _FriendStatus.none:
        return PillButton(
          label: _busy ? 'SENDING…' : 'ADD FRIEND',
          variant: PillButtonVariant.primary,
          fontSize: 13,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: _busy ? null : _send,
        );
      case _FriendStatus.error:
        return Text(
          'Couldn’t load friendship status.',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
          textAlign: TextAlign.center,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              name: widget.displayName,
              imageUrl: widget.profilePhotoUrl,
              size: 64,
              fontSize: 22,
            ),
            const SizedBox(height: 12),
            Text(
              atName(widget.displayName),
              style: PixelText.title(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildActionRow(),
          ],
        ),
      ),
    );
  }
}
