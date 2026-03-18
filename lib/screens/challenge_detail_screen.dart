import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';
import 'stake_picker_screen.dart';

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

  String get _myUserId =>
      widget.authService.userId ?? '';

  @override
  void initState() {
    super.initState();
    _instance = Map<String, dynamic>.from(widget.instance);
    if (_instance['status'] == 'ACTIVE') {
      _fetchProgress();
    }
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
    final proposedStake = _instance['proposedStake'] as Map<String, dynamic>?;
    return proposedStake?['name'] as String?;
  }

  String? _agreedStakeName() {
    final stake = _instance['stake'] as Map<String, dynamic>?;
    return stake?['name'] as String?;
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

  Future<void> _openEditStake() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          instanceId: _instance['id'] as String,
          friendName: _friendName(),
        ),
      ),
    );

    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openCounterPicker() async {
    final proposed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          instanceId: _instance['id'] as String,
          friendName: _friendName(),
          currentProposalId: _instance['proposedStakeId'] as String?,
        ),
      ),
    );

    if (proposed == true && mounted) {
      // Refresh instance data
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildNegotiationView() {
    final stakeName = _proposedStakeName();
    final isMyProposal = _isMyProposal();
    final proposedStakeId = _instance['proposedStakeId'] as String?;

    // No proposal yet — this user should propose
    if (proposedStakeId == null) {
      return Column(
        children: [
          TrailSign(
            width: double.infinity,
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          PillButton(
            label: 'PICK A STAKE',
            variant: PillButtonVariant.primary,
            fontSize: 16,
            fullWidth: true,
            padding:
                const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            onPressed: () async {
              final proposed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => StakePickerScreen(
                    authService: widget.authService,
                    instanceId: _instance['id'] as String,
                    friendName: _friendName(),
                  ),
                ),
              );
              if (proposed == true && mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      );
    }

    // There's a proposal on the table
    return Column(
      children: [
        ContentBoard(
          width: double.infinity,
          child: Column(
            children: [
              Text(
                isMyProposal ? 'YOU PROPOSED' : 'THEIR PROPOSAL',
                style: PixelText.title(size: 14, color: AppColors.accent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                stakeName ?? 'Unknown stake',
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (isMyProposal) ...[
                Text(
                  'Waiting for ${_friendName()} to respond...',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        if (isMyProposal) ...[
          const SizedBox(height: 16),
          PillButton(
            label: 'EDIT STAKE',
            variant: PillButtonVariant.secondary,
            fontSize: 16,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(
                horizontal: 48, vertical: 16),
            onPressed: _openEditStake,
          ),
        ],
        if (!isMyProposal) ...[
          const SizedBox(height: 16),
          if (_isAccepting)
            const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
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
              onPressed: _openCounterPicker,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildActiveView() {
    final stakeName = _agreedStakeName() ?? 'Unknown';

    int mySteps = 0;
    int theirSteps = 0;
    if (_progress != null) {
      final userA = _progress!['userA'] as Map<String, dynamic>?;
      final userB = _progress!['userB'] as Map<String, dynamic>?;
      if (userA != null && userB != null) {
        final aId = userA['userId'] as String? ?? '';
        if (aId == _myUserId) {
          mySteps = userA['totalSteps'] as int? ?? 0;
          theirSteps = userB['totalSteps'] as int? ?? 0;
        } else {
          mySteps = userB['totalSteps'] as int? ?? 0;
          theirSteps = userA['totalSteps'] as int? ?? 0;
        }
      }
    }

    final winning = mySteps >= theirSteps;

    return Column(
      children: [
        ContentBoard(
          width: double.infinity,
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
        ),
        const SizedBox(height: 16),
        ContentBoard(
          width: double.infinity,
          child: _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child:
                        CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              : Column(
                  children: [
                    Text(
                      'HEAD TO HEAD',
                      style:
                          PixelText.title(size: 14, color: AppColors.textMid),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'YOU',
                                style: PixelText.title(
                                    size: 12, color: AppColors.textMid),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$mySteps',
                                style: PixelText.number(
                                  size: 28,
                                  color: winning
                                      ? AppColors.pillGreen
                                      : AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'vs',
                          style: PixelText.body(
                              size: 16, color: AppColors.textMid),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _friendName().toUpperCase(),
                                style: PixelText.title(
                                    size: 12, color: AppColors.textMid),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$theirSteps',
                                style: PixelText.number(
                                  size: 28,
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
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _instance['status'] as String? ?? '';
    final isActive = status == 'ACTIVE';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        title: Text(
          'vs ${_friendName()}',
          style: PixelText.body(size: 14, color: AppColors.textDark),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                // Challenge info
                TrailSign(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        widget.challenge['title'] as String? ?? '',
                        style: PixelText.title(
                            size: 18, color: AppColors.textDark),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.challenge['description'] as String? ?? '',
                        style: PixelText.body(
                            size: 13, color: AppColors.textMid),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isActive) _buildActiveView() else _buildNegotiationView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
