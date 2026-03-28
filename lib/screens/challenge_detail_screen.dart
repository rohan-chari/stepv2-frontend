import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/pill_icon_button.dart';
import '../widgets/race_track.dart';
import 'stake_picker_screen.dart';
import '../widgets/wooden_tab_bar.dart';

class ChallengeDetailScreen extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic> instance;
  final Map<String, dynamic> challenge;

  const ChallengeDetailScreen({
    super.key,
    required this.authService,
    required this.instance,
    required this.challenge,
  });

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  final BackendApiService _api = BackendApiService();
  late Map<String, dynamic> _instance;
  Map<String, dynamic>? _progress;
  bool _isLoading = false;
  bool _isAccepting = false;


  String get _myUserId => widget.authService.userId ?? '';

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];


  @override
  void initState() {
    super.initState();
    _instance = Map<String, dynamic>.from(widget.instance);
    _fetchProgress();
  }

  String _friendName() {
    final userA = _instance['userA'] as Map<String, dynamic>?;
    final userB = _instance['userB'] as Map<String, dynamic>?;
    if (userA != null && userA['id'] != _myUserId) {
      return userA['displayName'] as String? ?? '???';
    }
    return userB?['displayName'] as String? ?? '???';
  }

  bool _isMyProposal() {
    final proposedById = _instance['proposedById'] as String?;
    return proposedById == _myUserId;
  }

  String? _proposedStakeName() {
    final proposedStake =
        _instance['proposedStake'] as Map<String, dynamic>?;
    return proposedStake?['name'] as String?;
  }

  String? _agreedStakeName() {
    final stake = _instance['stake'] as Map<String, dynamic>?;
    return stake?['name'] as String?;
  }

  // -- API methods --

  void _openSettings() {
    final status = _instance['status'] as String? ?? '';
    final isActive = status == 'ACTIVE';
    final isMyProposal = _isMyProposal();
    final hasProposal = _instance['proposedStakeId'] != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SETTINGS',
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
            const SizedBox(height: 16),
            if (!isActive && hasProposal && isMyProposal) ...[
              PillButton(
                label: 'EDIT STAKE',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _navigateToStakePicker('edit');
                },
              ),
              const SizedBox(height: 10),
            ],
            PillButton(
              label: 'CANCEL CHALLENGE',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () {
                Navigator.of(ctx).pop();
                _cancelChallenge();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelChallenge() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.cancelChallenge(
        identityToken: token,
        instanceId: _instance['id'] as String,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Couldn\u2019t cancel challenge. Please try again.');
      }
    }
  }

  Future<void> _fetchProgress() async {
    setState(() => _isLoading = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final instanceId = _instance['id'] as String;
      final progress = await _api.fetchChallengeProgress(
        identityToken: token,
        instanceId: instanceId,
      );

      if (mounted) {
        setState(() {
          _progress = progress;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptStake() async {
    setState(() => _isAccepting = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final result = await _api.respondToStake(
        identityToken: token,
        instanceId: _instance['id'] as String,
        accept: true,
      );

      if (mounted) {
        setState(() {
          _instance = result['instance'] as Map<String, dynamic>;
          _isAccepting = false;
        });
        _fetchProgress();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAccepting = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  void _navigateToStakePicker(String mode) {
    final currentProposalId = mode == 'counter'
        ? _instance['proposedStakeId'] as String?
        : null;

    Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          instanceId: _instance['id'] as String,
          friendName: _friendName(),
          currentProposalId: currentProposalId,
        ),
      ),
    ).then((result) {
      if (result == true && mounted) {
        _refreshInstance();
      }
    });
  }

  Future<void> _refreshInstance() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final data = await _api.fetchCurrentChallenge(identityToken: token);
      final instances = data['instances'] as List? ?? [];
      final instanceId = _instance['id'] as String;

      for (final i in instances) {
        final inst = i as Map<String, dynamic>;
        if (inst['id'] == instanceId) {
          if (mounted) {
            setState(() => _instance = inst);
          }
          break;
        }
      }
    } catch (_) {}

    _fetchProgress();
  }

  String _formatSteps(int steps) {
    if (steps >= 10000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final status = _instance['status'] as String? ?? '';
    final isActive = status == 'ACTIVE';

    return Scaffold(
      body: Stack(
        children: [
          Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF87CEEB),
                    Color(0xFFB0E0F0),
                    Color(0xFFD4F1F9),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.arrow_back,
                            color: AppColors.textDark,
                            size: 24,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'You vs. ${_friendName()}',
                              style: PixelText.title(size: 22, color: AppColors.textDark)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.challenge['title'] as String? ?? '',
                              style: PixelText.title(size: 14, color: AppColors.textMid)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                            if ((widget.challenge['description'] as String?)?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.challenge['description'] as String,
                                style: PixelText.body(size: 12, color: AppColors.textMid)
                                    .copyWith(shadows: _textShadows),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      PillIconButton(
                        icon: Icons.settings_rounded,
                        size: 36,
                        variant: PillButtonVariant.secondary,
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: 77.5 + MediaQuery.of(context).padding.bottom + 16,
                    ),
                    child: Column(
                      children: [
                        // Stake section (top)
                        if (isActive)
                          _buildActiveStakeInfo()
                        else
                          _buildNegotiationView(),
                        const SizedBox(height: 16),

                        // Race track
                        if (_progress != null) ...[
                          _buildRaceTrack(),
                          const SizedBox(height: 16),
                        ],

                        // Progress
                        _buildProgressSection(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

            // Tab bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: WoodenTabBar(
                currentIndex: 1,
                onTap: (index) {
                  Navigator.of(context).pop(true);
                },
                items: const [
                  WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                  WoodenTabItem(
                    icon: Icons.emoji_events_rounded,
                    label: 'Challenges',
                  ),
                  WoodenTabItem(
                    icon: Icons.people_rounded,
                    label: 'Friends',
                  ),
                  WoodenTabItem(
                    icon: Icons.leaderboard_rounded,
                    label: 'Leaderboard',
                  ),
                  WoodenTabItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // -- Race track --

  Widget _buildRaceTrack() {
    final userA = _progress!['userA'] as Map<String, dynamic>? ?? {};
    final userB = _progress!['userB'] as Map<String, dynamic>? ?? {};
    final aId = userA['userId'] as String? ?? '';
    final bool iAmA = aId == _myUserId;

    final myData = iAmA ? userA : userB;
    final theirData = iAmA ? userB : userA;

    return RetroCard(
      padding: const EdgeInsets.all(6),
      child: RaceTrack(
        mySteps: myData['totalSteps'] as int? ?? 0,
        theirSteps: theirData['totalSteps'] as int? ?? 0,
        myName: widget.authService.displayName ?? 'You',
        theirName: _friendName(),
      ),
    );
  }

  // -- Progress section --

  Widget _buildProgressSection() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_progress == null) return const SizedBox.shrink();

    return _buildHigherTotalProgress();
  }

  Widget _buildHigherTotalProgress() {
    final userA = _progress!['userA'] as Map<String, dynamic>? ?? {};
    final userB = _progress!['userB'] as Map<String, dynamic>? ?? {};

    final aId = userA['userId'] as String? ?? '';
    final bool iAmA = aId == _myUserId;

    final myData = iAmA ? userA : userB;
    final theirData = iAmA ? userB : userA;

    final myTotal = myData['totalSteps'] as int? ?? 0;
    final theirTotal = theirData['totalSteps'] as int? ?? 0;
    final myDaily = (myData['dailySteps'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final theirDaily = (theirData['dailySteps'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final winning = myTotal >= theirTotal;
    final diff = (myTotal - theirTotal).abs();

    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'WEEKLY STEPS',
            style: PixelText.title(size: 18, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('YOU',
                        style: PixelText.title(
                            size: 14, color: AppColors.textMid)),
                    const SizedBox(height: 4),
                    Text(
                      _formatSteps(myTotal),
                      style: PixelText.number(
                        size: 34,
                        color: winning
                            ? AppColors.pillGreen
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              Text('vs',
                  style:
                      PixelText.body(size: 16, color: AppColors.textMid)),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _friendName().toUpperCase(),
                      style: PixelText.title(
                          size: 14, color: AppColors.textMid),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSteps(theirTotal),
                      style: PixelText.number(
                        size: 34,
                        color: !winning
                            ? AppColors.pillGreen
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            winning
                ? (diff > 0
                    ? 'You\u2019re ahead by ${_formatSteps(diff)}'
                    : 'You\u2019re tied!')
                : '${_friendName()} leads by ${_formatSteps(diff)}',
            style: PixelText.body(size: 12, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
          if (myDaily.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDailyBreakdown(myDaily, theirDaily),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyBreakdown(
    List<Map<String, dynamic>> myDaily,
    List<Map<String, dynamic>> theirDaily,
  ) {
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text('DAY',
                  style: PixelText.title(size: 13, color: AppColors.textMid)),
            ),
            Expanded(
              child: Text('YOU',
                  style: PixelText.title(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.right),
            ),
            Expanded(
              child: Text(_friendName().toUpperCase(),
                  style: PixelText.title(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            height: 1,
            color: AppColors.parchmentBorder.withValues(alpha: 0.5),
          ),
        ),
        for (int i = 0; i < 7 && i < myDaily.length; i++)
          _buildDayRow(
            dayLabels[i],
            myDaily[i]['steps'] as int? ?? 0,
            i < theirDaily.length
                ? theirDaily[i]['steps'] as int? ?? 0
                : 0,
          ),
      ],
    );
  }

  Widget _buildDayRow(String label, int mySteps, int theirSteps) {
    final iWon = mySteps > theirSteps;
    final theyWon = theirSteps > mySteps;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: PixelText.body(size: 15, color: AppColors.textMid)),
          ),
          Expanded(
            child: Text(
              mySteps > 0 ? _formatSteps(mySteps) : '-',
              style: PixelText.body(
                size: 16,
                color: iWon ? AppColors.pillGreen : AppColors.textDark,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            child: Text(
              theirSteps > 0 ? _formatSteps(theirSteps) : '-',
              style: PixelText.body(
                size: 16,
                color: theyWon ? AppColors.pillGreen : AppColors.textDark,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // -- Stake negotiation --

  Widget _buildNegotiationView() {
    final stakeName = _proposedStakeName();
    final isMyProposal = _isMyProposal();
    final proposedStakeId = _instance['proposedStakeId'] as String?;

    if (proposedStakeId == null) {
      return RetroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'SET THE STAKES',
              style: PixelText.title(size: 16, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pick what the loser owes the winner.',
              style: PixelText.body(size: 13, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'PICK A STAKE',
              variant: PillButtonVariant.primary,
              fontSize: 16,
              fullWidth: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              onPressed: () => _navigateToStakePicker('propose'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.parchmentBorder, width: 2),
          ),
          child: Column(
            children: [
              Text(
                isMyProposal ? 'YOU PROPOSED' : 'THEIR PROPOSAL',
                style:
                    PixelText.title(size: 14, color: AppColors.accent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                stakeName ?? 'Unknown stake',
                style: PixelText.title(
                    size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (isMyProposal)
                Text(
                  'Waiting for ${_friendName()} to respond...',
                  style:
                      PixelText.body(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
        if (isMyProposal) ...[
          const SizedBox(height: 0),
        ],
        if (!isMyProposal) ...[
          const SizedBox(height: 16),
          if (_isAccepting)
            const Center(
                child:
                    CircularProgressIndicator(color: AppColors.accent))
          else ...[
            PillButton(
              label: 'ACCEPT STAKE',
              variant: PillButtonVariant.primary,
              fontSize: 16,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 48, vertical: 16),
              onPressed: _acceptStake,
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'COUNTER',
              variant: PillButtonVariant.secondary,
              fontSize: 16,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 48, vertical: 16),
              onPressed: () => _navigateToStakePicker('counter'),
            ),
          ],
        ],
      ],
    );
  }

  // -- Active stake info --

  Widget _buildActiveStakeInfo() {
    final stakeName = _agreedStakeName() ?? 'Unknown';
    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'STAKE',
            style: PixelText.title(size: 14, color: AppColors.accent),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            stakeName,
            style: PixelText.title(size: 16, color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

}
