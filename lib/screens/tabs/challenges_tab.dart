import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/game_container.dart';
import '../../widgets/info_board_card.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/pill_button.dart';
import '../challenge_detail_screen.dart';
import '../friend_picker_screen.dart';
import '../stake_picker_screen.dart';

class ChallengesTab extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic>? currentChallenge;
  final List<Map<String, dynamic>> friendsSteps;
  final VoidCallback onChallengeChanged;
  final VoidCallback? onOpenFriendsTab;
  final Future<void> Function()? onRefresh;
  final DateTime Function()? now;
  final StepData? stepData;
  final int? stepGoal;
  final String? displayName;
  final VoidCallback? onOpenProfile;

  const ChallengesTab({
    super.key,
    required this.authService,
    required this.currentChallenge,
    required this.friendsSteps,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onRefresh,
    this.now,
    this.stepData,
    this.stepGoal,
    this.displayName,
    this.onOpenProfile,
  });

  @override
  State<ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<ChallengesTab> {
  final BackendApiService _api = BackendApiService();
  bool _isInitiating = false;
  Timer? _countdownTimer;
  late DateTime _countdownNow;
  int _wins = 0;
  int _losses = 0;

  bool get _hasActiveChallenge =>
      widget.currentChallenge != null &&
      widget.currentChallenge!['challenge'] != null;

  DateTime get _now => (widget.now ?? DateTime.now).call();

  DateTime? get _challengeEndsAt {
    final rawValue = widget.currentChallenge?['endsAt'] as String?;
    if (rawValue == null || rawValue.isEmpty) return null;
    return DateTime.tryParse(rawValue)?.toLocal();
  }

  String get _myUserId => widget.authService.userId ?? '';

  List<Map<String, dynamic>> _getAvailableFriends() {
    final instances = widget.currentChallenge?['instances'] as List? ?? [];
    final challengedIds = <String>{};
    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final aId =
          inst['userAId'] as String? ??
          (inst['userA'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      final bId =
          inst['userBId'] as String? ??
          (inst['userB'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      challengedIds.add(aId);
      challengedIds.add(bId);
    }

    return widget.friendsSteps.where((f) {
      final id = f['id'] as String? ?? '';
      return !challengedIds.contains(id);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _countdownNow = _now;
    _syncCountdownTimer();
    _loadRecord();
  }

  @override
  void didUpdateWidget(covariant ChallengesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _countdownNow = _now;
    _syncCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Map<String, List<Map<String, dynamic>>> _categorizeInstances() {
    final instances = widget.currentChallenge?['instances'] as List? ?? [];
    final incoming = <Map<String, dynamic>>[];
    final outgoing = <Map<String, dynamic>>[];
    final active = <Map<String, dynamic>>[];

    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final status = inst['status'] as String? ?? '';
      final stakeStatus = inst['stakeStatus'] as String? ?? '';

      if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
        active.add(inst);
      } else {
        final proposedById = inst['proposedById'] as String? ?? '';
        if (proposedById.isNotEmpty && proposedById != _myUserId) {
          incoming.add(inst);
        } else {
          outgoing.add(inst);
        }
      }
    }

    return {'incoming': incoming, 'outgoing': outgoing, 'active': active};
  }

  Future<void> _startChallenge(String friendId, String friendName) async {
    final stakeId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          friendName: friendName,
        ),
      ),
    );

    if (stakeId == null || !mounted) return;

    setState(() => _isInitiating = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.initiateChallenge(
        identityToken: token,
        friendUserId: friendId,
        stakeId: stakeId,
      );

      if (mounted) {
        setState(() => _isInitiating = false);
        widget.onChallengeChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitiating = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  void _syncCountdownTimer() {
    _countdownTimer?.cancel();

    if (!_hasActiveChallenge || _challengeEndsAt == null) {
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdownNow = _now;
      });
    });
  }

  Future<void> _loadRecord() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    try {
      final stats = await _api.fetchStats(identityToken: token);
      if (mounted) {
        setState(() {
          _wins = stats['wins'] as int? ?? 0;
          _losses = stats['losses'] as int? ?? 0;
        });
      }
    } catch (_) {}
  }

  void _navigateToFriendPicker() {
    if (widget.friendsSteps.isEmpty) {
      widget.onOpenFriendsTab?.call();
      showInfoToast(context, 'Add some friends first on the Friends tab.');
      return;
    }

    final availableFriends = _getAvailableFriends();
    if (availableFriends.isEmpty) {
      showInfoToast(context, 'All friends already challenged this week!');
      return;
    }

    Navigator.of(context)
        .push<(String, String)>(
          MaterialPageRoute(
            builder: (context) => FriendPickerScreen(friends: availableFriends),
          ),
        )
        .then((result) {
          if (result != null && mounted) {
            _startChallenge(result.$1, result.$2);
          }
        });
  }

  void _showChallengeMenu(String instanceId, String friendName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'vs $friendName',
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'CANCEL CHALLENGE',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await _cancelChallenge(instanceId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelChallenge(String instanceId) async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await BackendApiService().cancelChallenge(
        identityToken: token,
        instanceId: instanceId,
      );

      if (!mounted) return;
      widget.onChallengeChanged();
    } catch (e) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn\u2019t cancel challenge. Please try again.',
      );
    }
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    final bottomPadding = tabBarHeight;

    return Padding(
      padding: EdgeInsets.only(top: topInset + 12, bottom: bottomPadding),
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            widget.onRefresh?.call() ?? Future.value(),
            _loadRecord(),
          ]);
        },
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _hasActiveChallenge
                    ? _buildActiveContent()
                    : _buildEmptyContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveContent() {
    final challenge =
        widget.currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final categories = _categorizeInstances();
    final allInstances = [
      ...categories['incoming']!,
      ...categories['active']!,
      ...categories['outgoing']!,
    ];

    return Column(
      children: [
        _buildTopStatusBar(),
        const SizedBox(height: 16),
        _buildChallengeBoard(challenge, hasActive: true),
        if (allInstances.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildChallengeTiles(allInstances, challenge),
        ],
      ],
    );
  }

  Widget _buildEmptyContent() {
    return Column(
      children: [
        _buildTopStatusBar(),
        const SizedBox(height: 16),
        _buildChallengeBoard(const {}, hasActive: false),
      ],
    );
  }

  // -- Top status bar (same as HomeTab) --

  Widget _buildTopStatusBar() {
    final steps = widget.stepData?.steps ?? 0;
    final goal = widget.stepGoal ?? 0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.displayName != null)
                    Flexible(
                      child: Text(
                        widget.displayName!,
                        style: PixelText.title(
                          size: 26,
                          color: AppColors.textDark,
                        ).copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  CoinBalanceBadge(
                    coins: widget.authService.coins,
                    heldCoins: widget.authService.heldCoins,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (goalStr != null)
                Text(
                  '$stepsStr / $goalStr',
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                )
              else
                Text(
                  stepsStr,
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                ),
            ],
          ),
        ),
        ProfileAvatarButton(
          name: widget.displayName ?? 'You',
          imageUrl: widget.authService.profilePhotoUrl,
          onPressed: widget.onOpenProfile,
        ),
      ],
    );
  }

  // -- Weekly challenge green board --

  Widget _buildChallengeBoard(
    Map<String, dynamic> challenge, {
    required bool hasActive,
  }) {
    final challengeEndsAt = _challengeEndsAt;
    final remaining = challengeEndsAt != null
        ? challengeEndsAt.difference(_countdownNow)
        : Duration.zero;
    final safeDuration = remaining.isNegative ? Duration.zero : remaining;

    final days = safeDuration.inDays;
    final hours = safeDuration.inHours.remainder(24);
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);

    final title = hasActive
        ? (challenge['title'] as String? ?? '')
        : 'No active challenges';
    final description = hasActive
        ? (challenge['description'] as String?)
        : 'Challenge a friend to a weekly step battle!';

    return InfoBoardCard(
      badgeLabel: 'THIS WEEK\u2019S CHALLENGE',
      title: title,
      subtitle: (description?.isNotEmpty ?? false) ? description : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (hasActive && challengeEndsAt != null) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CountdownUnit(value: days, label: 'DAYS'),
              const SizedBox(width: 8),
              _CountdownUnit(value: hours, label: 'HRS'),
              const SizedBox(width: 8),
              _CountdownUnit(value: minutes, label: 'MIN'),
              const SizedBox(width: 8),
              _CountdownUnit(value: seconds, label: 'SEC'),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _buildRecordRow(),
        if (widget.authService.displayName != null) ...[
          const SizedBox(height: 14),
          PillButton(
            label: _isInitiating ? 'STARTING...' : 'NEW CHALLENGE',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isInitiating ? null : _navigateToFriendPicker,
          ),
        ],
      ],
    );
  }

  Widget _buildRecordRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RecordStat(value: _wins, label: 'WINS'),
        Container(
          width: 1,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          color: AppColors.parchment.withValues(alpha: 0.4),
        ),
        _RecordStat(value: _losses, label: 'LOSSES'),
      ],
    );
  }

  // -- Challenge list (single consolidated card) --

  Widget _buildChallengeTiles(
    List<Map<String, dynamic>> instances,
    Map<String, dynamic> challenge,
  ) {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Column(
        children: [
          for (int i = 0; i < instances.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.parchmentBorder.withValues(alpha: 0.45),
              ),
            _buildChallengeRow(instances[i], challenge, i),
          ],
        ],
      ),
    );
  }

  Widget _buildChallengeRow(
    Map<String, dynamic> instance,
    Map<String, dynamic> challenge,
    int index,
  ) {
    final instanceId = instance['id'] as String? ?? '';
    final userA = instance['userA'] as Map<String, dynamic>?;
    final userB = instance['userB'] as Map<String, dynamic>?;

    Map<String, dynamic>? opponent;
    if (userA != null && userA['id'] != _myUserId) {
      opponent = userA;
    } else if (userB != null && userB['id'] != _myUserId) {
      opponent = userB;
    }

    final friendName = opponent?['displayName'] as String? ?? '???';
    final friendPhotoUrl = opponent?['profilePhotoUrl'] as String?;

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';
    final proposedById = instance['proposedById'] as String? ?? '';
    final isIncoming = proposedById.isNotEmpty && proposedById != _myUserId;

    final proposedStake = instance['proposedStake'] as Map<String, dynamic>?;
    final agreedStake = instance['stake'] as Map<String, dynamic>?;
    final stakeName =
        agreedStake?['name'] as String? ??
        proposedStake?['name'] as String? ??
        '';

    final ranking = instance['ranking'] as Map<String, dynamic>?;
    final isActive = status == 'ACTIVE' || stakeStatus == 'AGREED';

    String statusLabel;
    Color badgeColor;
    if (isActive && ranking != null) {
      final rank = ranking['rank'] as int? ?? 1;
      if (rank <= 1) {
        statusLabel = 'WINNING';
        badgeColor = AppColors.pillGreenDark;
      } else {
        statusLabel = 'LOSING';
        badgeColor = AppColors.error;
      }
    } else if (isActive) {
      statusLabel = 'ACTIVE';
      badgeColor = AppColors.pillGreenDark;
    } else if (isIncoming) {
      statusLabel = 'ACCEPT';
      badgeColor = AppColors.pillGoldDark;
    } else {
      statusLabel = 'WAITING';
      badgeColor = AppColors.textMid;
    }

    return Material(
      color: index.isOdd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context)
              .push<bool>(
                MaterialPageRoute(
                  builder: (context) => ChallengeDetailScreen(
                    authService: widget.authService,
                    instance: instance,
                    challenge: challenge,
                  ),
                ),
              )
              .then((_) => widget.onChallengeChanged());
        },
        onLongPress: () => _showChallengeMenu(instanceId, friendName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              AppAvatar(name: friendName, imageUrl: friendPhotoUrl, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vs $friendName',
                      style: PixelText.title(
                        size: 16,
                        color: AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (stakeName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        stakeName,
                        style: PixelText.body(
                          size: 12,
                          color: AppColors.textMid,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: PixelText.title(size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Helpers --

  static String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatCompact(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
  }

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
}

// -- Countdown unit widget --

class _CountdownUnit extends StatelessWidget {
  final int value;
  final String label;

  const _CountdownUnit({required this.value, required this.label});

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.pillGreenShadow.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.parchment.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: PixelText.number(size: 28, color: AppColors.parchmentLight),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: PixelText.title(
            size: 9,
            color: AppColors.parchment,
          ).copyWith(shadows: _textShadows),
        ),
      ],
    );
  }
}

// -- Record stat widget (wins / losses inside the green board) --

class _RecordStat extends StatelessWidget {
  final int value;
  final String label;

  const _RecordStat({required this.value, required this.label});

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: PixelText.number(
            size: 26,
            color: AppColors.parchmentLight,
          ).copyWith(shadows: _textShadows),
        ),
        Text(
          label,
          style: PixelText.title(
            size: 10,
            color: AppColors.parchment,
          ).copyWith(shadows: _textShadows),
        ),
      ],
    );
  }
}
