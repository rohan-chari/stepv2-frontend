import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchStakes();
  }

  Future<void> _fetchStakes() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final stakes = await _api.fetchStakeCatalog(identityToken: token);

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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        itemCount: _stakes.length,
                        itemBuilder: (context, index) {
                          final stake = _stakes[index];
                          final id = stake['id'] as String;
                          final name = stake['name'] as String? ?? '';
                          final desc = stake['description'] as String? ?? '';
                          final category = stake['category'] as String? ?? '';
                          final selected = _selectedStakeId == id;

                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedStakeId = id),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.pillGreen.withValues(alpha: 0.15)
                                    : AppColors.parchmentLight,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.pillGreen
                                      : AppColors.parchmentBorder,
                                  width: selected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _categoryIcon(category),
                                    size: 20,
                                    color: selected
                                        ? AppColors.pillGreen
                                        : AppColors.textMid,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: PixelText.title(
                                            size: 14,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            desc,
                                            style: PixelText.body(
                                              size: 12,
                                              color: AppColors.textMid,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: AppColors.pillGreen,
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
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
