import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/filter_dropdown.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

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

  static const _relationshipTypes = [
    'partner',
    'friend',
    'family',
    'coworker',
    'sibling',
    'parent',
  ];

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
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
    });
    _fetchStakes();
  }

  Future<void> _submitProposal() async {
    if (_selectedStakeId == null) return;

    if (widget.instanceId == null) {
      Navigator.of(context).pop(_selectedStakeId);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      if (widget.currentProposalId != null) {
        await _api.respondToStake(
          identityToken: token,
          instanceId: widget.instanceId!,
          accept: false,
          counterStakeId: _selectedStakeId,
        );
      } else {
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
      body: Container(
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
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.arrow_back,
                          color: AppColors.textDark,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'vs ${widget.friendName}',
                            style: PixelText.title(size: 22, color: AppColors.textDark)
                                .copyWith(shadows: _textShadows),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'What does the loser owe?',
                            style: PixelText.body(size: 13, color: AppColors.textMid)
                                .copyWith(shadows: _textShadows),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Filter dropdown
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: FilterDropdown<String>(
                  value: _selectedRelationshipType,
                  options: [
                    (null, 'ALL'),
                    for (final type in _relationshipTypes)
                      (type, type.toUpperCase()),
                  ],
                  onChanged: (val) => _selectRelationshipType(val),
                ),
              ),
              const SizedBox(height: 8),

              // Stakes list
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      )
                    : _stakes.isEmpty
                        ? Center(
                            child: Text(
                              'No stakes found',
                              style: PixelText.body(size: 13, color: AppColors.textMid)
                                  .copyWith(shadows: _textShadows),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _stakes.length,
                            itemBuilder: (context, index) =>
                                _buildStakeCard(_stakes[index]),
                          ),
              ),

              // Submit button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: _isSubmitting
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      )
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStakeCard(Map<String, dynamic> stake) {
    final id = stake['id'] as String;
    final name = stake['name'] as String? ?? '';
    final desc = stake['description'] as String? ?? '';
    final category = stake['category'] as String? ?? '';
    final selected = _selectedStakeId == id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedStakeId = id),
        child: RetroCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          highlightColor: selected ? AppColors.pillGreen : null,
          child: Row(
            children: [
              Icon(
                _categoryIcon(category),
                size: 22,
                color: selected ? AppColors.pillGreen : AppColors.textMid,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: PixelText.title(size: 14, color: AppColors.textDark),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: PixelText.body(size: 12, color: AppColors.textMid),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.pillGreen, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
