import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

class StakePickerScreen extends StatefulWidget {
  final AuthService authService;
  final String? instanceId;
  final String friendName;
  final String? currentProposalId;

  const StakePickerScreen({
    super.key,
    required this.authService,
    this.instanceId,
    required this.friendName,
    this.currentProposalId,
  });

  @override
  State<StakePickerScreen> createState() => _StakePickerScreenState();
}

class _StakePickerScreenState extends State<StakePickerScreen> {
  final BackendApiService _api = BackendApiService();
  List<Map<String, dynamic>> _stakes = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _selectedStakeId;
  String? _selectedRelationshipType;
  bool _showRelationshipDropdown = false;

  static const _relationshipTypes = [
    'partner',
    'friend',
    'family',
    'coworker',
    'sibling',
    'parent',
  ];

  @override
  void initState() {
    super.initState();
    _fetchStakes();
  }

  Future<void> _fetchStakes() async {
    setState(() => _isLoading = true);
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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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

  Future<void> _submitProposal() async {
    if (_selectedStakeId == null) return;

    // Selection-only mode: no instanceId, just return the chosen stakeId
    if (widget.instanceId == null) {
      Navigator.of(context).pop(_selectedStakeId);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      if (widget.currentProposalId != null) {
        // Counter-proposing
        await _api.respondToStake(
          identityToken: token,
          instanceId: widget.instanceId!,
          accept: false,
          counterStakeId: _selectedStakeId,
        );
      } else {
        // Initial proposal
        await _api.proposeStake(
          identityToken: token,
          instanceId: widget.instanceId!,
          stakeId: _selectedStakeId!,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showErrorToast(context, e.toString());
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final buttonLabel = widget.currentProposalId != null
        ? 'COUNTER WITH THIS'
        : 'PROPOSE STAKE';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Pick a Stake',
          style: PixelText.body(size: 14, color: AppColors.textDark),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: TrailSign(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        'vs ${widget.friendName}',
                        style: PixelText.title(
                            size: 16, color: AppColors.textDark),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'What does the loser owe?',
                        style: PixelText.body(
                            size: 13, color: AppColors.textMid),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: ContentBoard(
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
                                    border: Border.all(
                                        color: AppColors.parchmentBorder),
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
                                            size: 12,
                                            color: AppColors.textDark),
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
                                    border: Border.all(
                                        color: AppColors.parchmentBorder),
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
                            ],
                          ),
                        ),
                      ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: _isSubmitting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent))
                      : PillButton(
                          label: buttonLabel,
                          variant: PillButtonVariant.primary,
                          fontSize: 16,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 48, vertical: 16),
                          onPressed:
                              _selectedStakeId != null ? _submitProposal : null,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
