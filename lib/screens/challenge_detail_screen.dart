import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

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

  // Inline stake picker state
  bool _showingStakePicker = false;
  String _stakePickerMode = 'propose';
  List<Map<String, dynamic>> _stakes = [];
  bool _stakesLoading = false;
  bool _isSubmittingStake = false;
  String? _selectedStakeId;
  String? _selectedRelationshipType;
  bool _showRelationshipDropdown = false;

  String get _myUserId => widget.authService.userId ?? '';

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

  void _openStakePicker(String mode) {
    setState(() {
      _showingStakePicker = true;
      _stakePickerMode = mode;
      _selectedStakeId = null;
    });
    if (_stakes.isEmpty) _fetchStakes();
  }

  void _closeStakePicker() {
    setState(() {
      _showingStakePicker = false;
      _selectedStakeId = null;
      _selectedRelationshipType = null;
      _showRelationshipDropdown = false;
    });
  }

  static const _relationshipTypes = [
    'partner',
    'friend',
    'family',
    'coworker',
    'sibling',
    'parent',
  ];

  Future<void> _fetchStakes() async {
    setState(() => _stakesLoading = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final stakes = await _api.fetchStakeCatalog(
        identityToken: token,
        relationshipType: _selectedRelationshipType,
      );
      if (mounted) {
        setState(() {
          _stakes = stakes;
          _stakesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _stakesLoading = false);
        showErrorToast(context, 'Failed to load stakes');
      }
    }
  }

  void _selectRelationshipType(String? type) {
    setState(() {
      _selectedRelationshipType = type;
      _selectedStakeId = null;
      _showRelationshipDropdown = false;
    });
    _fetchStakes();
  }

  Future<void> _submitStakeSelection() async {
    if (_selectedStakeId == null) return;

    setState(() => _isSubmittingStake = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      Map<String, dynamic> result;
      if (_stakePickerMode == 'counter') {
        result = await _api.respondToStake(
          identityToken: token,
          instanceId: _instance['id'] as String,
          accept: false,
          counterStakeId: _selectedStakeId,
        );
      } else {
        result = await _api.proposeStake(
          identityToken: token,
          instanceId: _instance['id'] as String,
          stakeId: _selectedStakeId!,
        );
      }

      if (mounted) {
        final updatedInstance =
            result['instance'] as Map<String, dynamic>?;
        if (updatedInstance != null) {
          setState(() {
            _instance = updatedInstance;
            _showingStakePicker = false;
            _selectedStakeId = null;
            _isSubmittingStake = false;
          });
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmittingStake = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'food':
        return Icons.restaurant;
      case 'activity':
        return Icons.sports_esports;
      case 'experience':
        return Icons.explore;
      case 'act_of_service':
        return Icons.handshake;
      case 'digital':
        return Icons.phone_android;
      default:
        return Icons.star;
    }
  }

  // ── Progress display (driven by resolution rule) ──

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

    final challenge =
        _progress!['challenge'] as Map<String, dynamic>? ?? {};
    final rule = challenge['resolutionRule'] as String? ?? 'higher_total';

    switch (rule) {
      case 'higher_total':
        return _buildHigherTotalProgress();
      default:
        // Fallback: show higher_total style for any unknown rule
        return _buildHigherTotalProgress();
    }
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

    return ContentBoard(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            'WEEKLY STEPS',
            style: PixelText.title(size: 14, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Totals
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('YOU',
                        style: PixelText.title(
                            size: 12, color: AppColors.textMid)),
                    const SizedBox(height: 4),
                    Text(
                      _formatSteps(myTotal),
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
              Text('vs',
                  style:
                      PixelText.body(size: 16, color: AppColors.textMid)),
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
                      _formatSteps(theirTotal),
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
          // Daily breakdown
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
        // Header row
        Row(
          children: [
            SizedBox(
              width: 36,
              child: Text('DAY',
                  style: PixelText.title(size: 10, color: AppColors.textMid)),
            ),
            Expanded(
              child: Text('YOU',
                  style: PixelText.title(size: 10, color: AppColors.textMid),
                  textAlign: TextAlign.right),
            ),
            Expanded(
              child: Text(_friendName().toUpperCase(),
                  style: PixelText.title(size: 10, color: AppColors.textMid),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label,
                style: PixelText.body(size: 11, color: AppColors.textMid)),
          ),
          Expanded(
            child: Text(
              mySteps > 0 ? _formatSteps(mySteps) : '-',
              style: PixelText.body(
                size: 12,
                color: iWon ? AppColors.pillGreen : AppColors.textDark,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            child: Text(
              theirSteps > 0 ? _formatSteps(theirSteps) : '-',
              style: PixelText.body(
                size: 12,
                color: theyWon ? AppColors.pillGreen : AppColors.textDark,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSteps(int steps) {
    if (steps >= 10000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  // ── Stake negotiation ──

  Widget _buildNegotiationView() {
    if (_showingStakePicker) return _buildInlineStakePicker();

    final stakeName = _proposedStakeName();
    final isMyProposal = _isMyProposal();
    final proposedStakeId = _instance['proposedStakeId'] as String?;

    if (proposedStakeId == null) {
      return Column(
        children: [
          TrailSign(
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  'SET THE STAKES',
                  style:
                      PixelText.title(size: 16, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick what the loser owes the winner.',
                  style:
                      PixelText.body(size: 13, color: AppColors.textMid),
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
            onPressed: () => _openStakePicker('propose'),
          ),
        ],
      );
    }

    return Column(
      children: [
        ContentBoard(
          width: double.infinity,
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
          const SizedBox(height: 16),
          PillButton(
            label: 'EDIT STAKE',
            variant: PillButtonVariant.secondary,
            fontSize: 16,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(
                horizontal: 48, vertical: 16),
            onPressed: () => _openStakePicker('edit'),
          ),
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
              onPressed: () => _openStakePicker('counter'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDropdownOption(String? type, String label) {
    final isSelected = _selectedRelationshipType == type;
    return GestureDetector(
      onTap: () => _selectRelationshipType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected
            ? AppColors.pillGreen.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Text(
          label,
          style: PixelText.body(
            size: 12,
            color: isSelected ? AppColors.pillGreen : AppColors.textDark,
          ),
        ),
      ),
    );
  }

  TableRow _buildStakeRow(Map<String, dynamic> stake) {
    final id = stake['id'] as String;
    final name = stake['name'] as String? ?? '';
    final desc = stake['description'] as String? ?? '';
    final category = stake['category'] as String? ?? '';
    final selected = _selectedStakeId == id;

    return TableRow(
      decoration: BoxDecoration(
        color: selected
            ? AppColors.pillGreen.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      children: [
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedStakeId = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Icon(
                _categoryIcon(category),
                size: 18,
                color: selected ? AppColors.pillGreen : AppColors.textMid,
              ),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedStakeId = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: PixelText.title(
                        size: 13, color: AppColors.textDark),
                  ),
                  if (desc.isNotEmpty)
                    Text(
                      desc,
                      style: PixelText.body(
                          size: 11, color: AppColors.textMid),
                    ),
                ],
              ),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedStakeId = id),
            child: selected
                ? const Icon(Icons.check_circle,
                    color: AppColors.pillGreen, size: 20)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineStakePicker() {
    final buttonLabel = _stakePickerMode == 'counter'
        ? 'COUNTER WITH THIS'
        : 'PROPOSE STAKE';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _closeStakePicker,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back,
                      size: 16, color: AppColors.textMid),
                  const SizedBox(width: 4),
                  Text(
                    'BACK',
                    style: PixelText.body(
                        size: 12, color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            Text(
              'PICK A STAKE',
              style:
                  PixelText.title(size: 14, color: AppColors.accent),
            ),
            const SizedBox(width: 60),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'What does the loser owe?',
          style: PixelText.body(size: 13, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (_stakesLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: AppColors.accent),
          )
        else
          ContentBoard(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Relationship type dropdown
                GestureDetector(
                  onTap: () => setState(() =>
                      _showRelationshipDropdown =
                          !_showRelationshipDropdown),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.parchmentLight,
                      border:
                          Border.all(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedRelationshipType?.toUpperCase() ??
                              'ALL',
                          style: PixelText.title(
                              size: 12, color: AppColors.textDark),
                        ),
                        Icon(
                          _showRelationshipDropdown
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: AppColors.textMid,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showRelationshipDropdown)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.parchmentLight,
                      border:
                          Border.all(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    margin: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        _buildDropdownOption(null, 'ALL'),
                        for (final type in _relationshipTypes)
                          _buildDropdownOption(
                              type, type.toUpperCase()),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  height: 1,
                  color: AppColors.parchmentBorder
                      .withValues(alpha: 0.5),
                ),
                const SizedBox(height: 4),
                // Stakes table
                if (_stakes.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No stakes found',
                      style: PixelText.body(
                          size: 13, color: AppColors.textMid),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: AppColors.parchmentBorder
                            .withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(36),
                      1: FlexColumnWidth(),
                      2: FixedColumnWidth(30),
                    },
                    children: [
                      for (final stake in _stakes)
                        _buildStakeRow(stake),
                    ],
                  ),
                const SizedBox(height: 16),
                if (_isSubmittingStake)
                  const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent))
                else
                  PillButton(
                    label: buttonLabel,
                    variant: PillButtonVariant.primary,
                    fontSize: 16,
                    fullWidth: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 16),
                    onPressed: _selectedStakeId != null
                        ? _submitStakeSelection
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Active view (stake agreed) ──

  Widget _buildActiveStakeInfo() {
    final stakeName = _agreedStakeName() ?? 'Unknown';
    return ContentBoard(
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
    );
  }

  // ── Main build ──

  @override
  Widget build(BuildContext context) {
    final status = _instance['status'] as String? ?? '';
    final isActive = status == 'ACTIVE';

    return PopScope(
      canPop: !_showingStakePicker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeStakePicker();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            icon:
                const Icon(Icons.arrow_back, color: AppColors.textDark),
            onPressed: () {
              if (_showingStakePicker) {
                _closeStakePicker();
              } else {
                Navigator.of(context).pop(true);
              }
            },
          ),
          title: Text(
            'vs ${_friendName()}',
            style:
                PixelText.body(size: 14, color: AppColors.textDark),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: GameBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
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
                          widget.challenge['description'] as String? ??
                              '',
                          style: PixelText.body(
                              size: 13, color: AppColors.textMid),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Always show progress
                  _buildProgressSection(),
                  const SizedBox(height: 16),
                  // Stake section
                  if (isActive)
                    _buildActiveStakeInfo()
                  else
                    _buildNegotiationView(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
