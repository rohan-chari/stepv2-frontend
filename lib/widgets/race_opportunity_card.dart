import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../styles.dart';
import 'app_avatar.dart';
import 'home_chrome.dart';
import 'pill_button.dart';

const _inviteShareMessage =
    "Race me on Bara — daily step challenges with friends. https://apps.apple.com/us/app/bara-step-challenges/id6760504694";

enum RaceCardState {
  pendingInvite,
  activeRace,
  friendRacing,
  friendFinished,
  publicRace,
  empty,
}

class RaceCardUser {
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final List<Map<String, dynamic>> accessories;

  const RaceCardUser({
    required this.userId,
    required this.displayName,
    this.profilePhotoUrl,
    this.accessories = const [],
  });

  static RaceCardUser? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final accessories = (json['accessories'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    return RaceCardUser(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Anonymous',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      accessories: accessories,
    );
  }
}

class RaceCardData {
  final RaceCardState state;
  final int pendingInviteCount;
  final Map<String, dynamic> data;

  const RaceCardData({
    required this.state,
    this.pendingInviteCount = 0,
    this.data = const {},
  });

  static RaceCardData fromJson(Map<String, dynamic> json) {
    final stateStr = (json['state'] as String? ?? 'EMPTY').toUpperCase();
    return RaceCardData(
      state: _stateFromString(stateStr),
      pendingInviteCount: (json['pendingInviteCount'] as int?) ?? 0,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  static RaceCardState _stateFromString(String s) {
    switch (s) {
      case 'PENDING_INVITE':
        return RaceCardState.pendingInvite;
      case 'ACTIVE_RACE':
        return RaceCardState.activeRace;
      case 'FRIEND_RACING':
        return RaceCardState.friendRacing;
      case 'FRIEND_FINISHED':
        return RaceCardState.friendFinished;
      case 'PUBLIC_RACE':
        return RaceCardState.publicRace;
      default:
        return RaceCardState.empty;
    }
  }
}

class RaceOpportunityCard extends StatelessWidget {
  final RaceCardData data;
  final void Function(String raceId)? onAccept;
  final void Function(String raceId)? onDecline;
  final void Function(String raceId)? onOpenRace;
  final void Function(String raceId)? onJoinRace;
  final void Function(String userId)? onChallengeBack;

  const RaceOpportunityCard({
    super.key,
    required this.data,
    this.onAccept,
    this.onDecline,
    this.onOpenRace,
    this.onJoinRace,
    this.onChallengeBack,
  });

  @override
  Widget build(BuildContext context) {
    switch (data.state) {
      case RaceCardState.pendingInvite:
        return _PendingInviteCard(
          data: data.data,
          extraInviteCount: (data.pendingInviteCount - 1).clamp(0, 99),
          onAccept: onAccept,
          onDecline: onDecline,
        );
      case RaceCardState.activeRace:
        return _ActiveRaceCard(data: data.data, onOpenRace: onOpenRace);
      case RaceCardState.friendRacing:
        return _FriendRacingCard(data: data.data, onJoinRace: onJoinRace);
      case RaceCardState.friendFinished:
        return _FriendFinishedCard(
          data: data.data,
          onChallengeBack: onChallengeBack,
        );
      case RaceCardState.publicRace:
        return _PublicRaceCard(data: data.data, onJoinRace: onJoinRace);
      case RaceCardState.empty:
        return const _InviteFriendsCard();
    }
  }
}

// ---------------------------------------------------------------------------
// State 1: Pending invite
// ---------------------------------------------------------------------------

class _PendingInviteCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final int extraInviteCount;
  final void Function(String raceId)? onAccept;
  final void Function(String raceId)? onDecline;

  const _PendingInviteCard({
    required this.data,
    required this.extraInviteCount,
    this.onAccept,
    this.onDecline,
  });

  @override
  State<_PendingInviteCard> createState() => _PendingInviteCardState();
}

class _PendingInviteCardState extends State<_PendingInviteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inviter = RaceCardUser.fromJson(
      widget.data['inviter'] as Map<String, dynamic>?,
    );
    final raceId = widget.data['raceId'] as String? ?? '';
    final durationHours = (widget.data['durationHours'] as num?)?.toInt() ?? 0;
    final participantCount =
        (widget.data['participantCount'] as num?)?.toInt() ?? 0;
    final expiresAt = DateTime.tryParse(
      widget.data['expiresAt'] as String? ?? '',
    );
    final expiresText = _formatTimeLeft(expiresAt);

    final detailLine =
        "${_formatDuration(durationHours)} · $participantCount racers";

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.25 + (_pulse.value * 0.35);
        return _CardShell(
          borderColor: HomeColors.clay.withValues(alpha: glow),
          child: child!,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(
                name: inviter?.displayName ?? '?',
                imageUrl: inviter?.profilePhotoUrl,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${inviter?.displayName ?? 'Someone'} invited you to race",
                      style: HomeText.title(size: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detailLine,
                      style: HomeText.body(size: 12, color: HomeColors.lineSoft),
                    ),
                  ],
                ),
              ),
              if (widget.extraInviteCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: HomeColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: HomeColors.lineSoft, width: 1),
                  ),
                  child: Text(
                    "+${widget.extraInviteCount} more",
                    style: HomeText.body(
                      size: 11,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: PillButton(
                  label: 'ACCEPT',
                  variant: PillButtonVariant.primary,
                  fontSize: 13,
                  fullWidth: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  onPressed: widget.onAccept == null || raceId.isEmpty
                      ? null
                      : () => widget.onAccept!(raceId),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PillButton(
                  label: 'DECLINE',
                  variant: PillButtonVariant.secondary,
                  fontSize: 13,
                  fullWidth: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  onPressed: widget.onDecline == null || raceId.isEmpty
                      ? null
                      : () => widget.onDecline!(raceId),
                ),
              ),
            ],
          ),
          if (expiresText != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                expiresText,
                style: HomeText.body(
                  size: 11,
                  color: HomeColors.lineSoft,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State 2: Active race
// ---------------------------------------------------------------------------

class _ActiveRaceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String raceId)? onOpenRace;

  const _ActiveRaceCard({required this.data, this.onOpenRace});

  @override
  Widget build(BuildContext context) {
    final raceId = data['raceId'] as String? ?? '';
    final name = data['name'] as String? ?? 'Race';
    final endsAt = DateTime.tryParse(data['endsAt'] as String? ?? '');
    final me = data['me'] as Map<String, dynamic>?;
    final leader = data['leader'] as Map<String, dynamic>?;
    final myUserId = me?['userId'] as String?;
    final leaderUserId = leader?['userId'] as String?;
    final isLeading = myUserId != null && myUserId == leaderUserId;
    final myTotal = (me?['totalSteps'] as num?)?.toInt() ?? 0;
    final leaderTotal = (leader?['totalSteps'] as num?)?.toInt() ?? 0;
    final gap = isLeading ? 0 : (leaderTotal - myTotal);
    final gapText = isLeading
        ? 'Leading the race — keep going'
        : '${_formatSteps(gap)} steps behind ${leader?['displayName'] ?? 'the leader'}';

    return GestureDetector(
      onTap: onOpenRace == null || raceId.isEmpty
          ? null
          : () => onOpenRace!(raceId),
      child: _CardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: HomeText.title(size: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (endsAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'ends ${_formatRelative(endsAt)}',
                    style: HomeText.body(
                      size: 12,
                      color: HomeColors.lineSoft,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _MiniTrack(
              entries: [
                if (leader != null) _trackEntry(leader),
                if (me != null && myUserId != leaderUserId) _trackEntry(me),
                ...((data['others'] as List?) ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(_trackEntry),
              ],
              highlightUserId: myUserId,
            ),
            const SizedBox(height: 12),
            Text(
              gapText,
              style: HomeText.body(size: 13, weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'VIEW RACE',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onPressed: onOpenRace == null || raceId.isEmpty
                  ? null
                  : () => onOpenRace!(raceId),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State 3: Friend currently racing
// ---------------------------------------------------------------------------

class _FriendRacingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String raceId)? onJoinRace;

  const _FriendRacingCard({required this.data, this.onJoinRace});

  @override
  Widget build(BuildContext context) {
    final raceId = data['raceId'] as String? ?? '';
    final friend = RaceCardUser.fromJson(
      data['friend'] as Map<String, dynamic>?,
    );
    final participants = ((data['participants'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final isPublicJoinable = data['isPublicJoinable'] as bool? ?? false;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "${friend?.displayName ?? 'A friend'} is racing right now",
            style: HomeText.title(size: 16),
          ),
          const SizedBox(height: 12),
          _MiniTrack(
            entries: participants.map(_trackEntry).toList(),
            highlightUserId: friend?.userId,
          ),
          const SizedBox(height: 12),
          if (isPublicJoinable && raceId.isNotEmpty)
            PillButton(
              label: 'JOIN THIS RACE',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onPressed: onJoinRace == null
                  ? null
                  : () => onJoinRace!(raceId),
            )
          else
            Text(
              'This is a private race — root them on.',
              style: HomeText.body(size: 12, color: HomeColors.lineSoft),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State 4: Friend just finished
// ---------------------------------------------------------------------------

class _FriendFinishedCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String userId)? onChallengeBack;

  const _FriendFinishedCard({required this.data, this.onChallengeBack});

  @override
  Widget build(BuildContext context) {
    final friend = RaceCardUser.fromJson(
      data['friend'] as Map<String, dynamic>?,
    );
    final placement = (data['placement'] as num?)?.toInt() ?? 1;
    final raceName = data['raceName'] as String? ?? 'a race';
    final medal = switch (placement) {
      1 => '🏆',
      2 => '🥈',
      3 => '🥉',
      _ => '🎉',
    };
    final placementText = switch (placement) {
      1 => 'just won',
      2 => 'just finished 2nd in',
      3 => 'just finished 3rd in',
      _ => 'just finished',
    };

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(
                name: friend?.displayName ?? '?',
                imageUrl: friend?.profilePhotoUrl,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "${friend?.displayName ?? 'A friend'} $placementText $raceName $medal",
                  style: HomeText.title(size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'CHALLENGE ${friend?.displayName.toUpperCase() ?? ''}'
                .trim(),
            variant: PillButtonVariant.primary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            onPressed: onChallengeBack == null || friend == null
                ? null
                : () => onChallengeBack!(friend.userId),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State 5: Public race available
// ---------------------------------------------------------------------------

class _PublicRaceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String raceId)? onJoinRace;

  const _PublicRaceCard({required this.data, this.onJoinRace});

  @override
  Widget build(BuildContext context) {
    final raceId = data['raceId'] as String? ?? '';
    final name = data['name'] as String? ?? 'Public Race';
    final participantCount =
        (data['participantCount'] as num?)?.toInt() ?? 0;
    final endsAt = DateTime.tryParse(data['endsAt'] as String? ?? '');

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: HomeText.title(size: 16)),
          const SizedBox(height: 4),
          Text(
            "$participantCount racing"
            "${endsAt != null ? ' · ends ${_formatRelative(endsAt)}' : ''}",
            style: HomeText.body(size: 12, color: HomeColors.lineSoft),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'JOIN RACE',
            variant: PillButtonVariant.primary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            onPressed: onJoinRace == null || raceId.isEmpty
                ? null
                : () => onJoinRace!(raceId),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State 6 (EMPTY): Invite friends fallback
// ---------------------------------------------------------------------------

class _InviteFriendsCard extends StatelessWidget {
  const _InviteFriendsCard();

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Race your friends',
            style: HomeText.title(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Invite people you walk with — races are better head-to-head.',
            style: HomeText.body(size: 12, color: HomeColors.lineSoft),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'INVITE FRIENDS',
            variant: PillButtonVariant.primary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            onPressed: () {
              Share.share(_inviteShareMessage);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

class _CardShell extends StatelessWidget {
  final Widget child;
  final Color? borderColor;

  const _CardShell({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HomeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? HomeColors.lineSoft,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

class _MiniTrack extends StatelessWidget {
  final List<_TrackEntry> entries;
  final String? highlightUserId;

  const _MiniTrack({required this.entries, this.highlightUserId});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: HomeColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final entry in entries.take(4))
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${entry.rank}',
                    style: HomeText.title(
                      size: 11,
                      color: HomeColors.sageDeep,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppAvatar(
                    name: entry.displayName,
                    imageUrl: entry.profilePhotoUrl,
                    size: 36,
                    borderColor: entry.userId == highlightUserId
                        ? HomeColors.clay
                        : AppColors.parchment,
                    borderWidth: entry.userId == highlightUserId ? 2.5 : 1.5,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatSteps(entry.totalSteps),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeText.body(size: 11, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackEntry {
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final int rank;
  final int totalSteps;

  const _TrackEntry({
    required this.userId,
    required this.displayName,
    required this.rank,
    required this.totalSteps,
    this.profilePhotoUrl,
  });
}

_TrackEntry _trackEntry(Map<String, dynamic> json) {
  return _TrackEntry(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Anonymous',
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    totalSteps: (json['totalSteps'] as num?)?.toInt() ?? 0,
  );
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _formatSteps(int steps) {
  if (steps >= 10000) {
    return '${(steps / 1000).toStringAsFixed(1)}k';
  }
  return steps.toString();
}

String _formatDuration(int hours) {
  if (hours <= 0) return 'Race';
  if (hours % 24 == 0) {
    final days = hours ~/ 24;
    return '$days-day race';
  }
  return '${hours}h race';
}

String _formatRelative(DateTime when) {
  final diff = when.difference(DateTime.now());
  if (diff.isNegative) return 'soon';
  final hours = diff.inHours;
  if (hours < 1) return 'in ${diff.inMinutes}m';
  if (hours < 24) return 'in ${hours}h';
  return 'in ${diff.inDays}d';
}

String? _formatTimeLeft(DateTime? expiresAt) {
  if (expiresAt == null) return null;
  final diff = expiresAt.difference(DateTime.now());
  if (diff.isNegative || diff.inSeconds == 0) {
    return 'Invite expired';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m left to respond';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h left to respond';
  }
  return '${diff.inDays}d left to respond';
}
