import 'package:flutter/material.dart';

import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/funded_exposure_error_copy.dart';
import 'game_container.dart';
import 'home_chrome.dart';
import 'pill_button.dart';

enum QuickRacePreset { twoDay, sevenDay }

extension QuickRacePresetValue on QuickRacePreset {
  int get days => this == QuickRacePreset.twoDay ? 2 : 7;
  String get label =>
      this == QuickRacePreset.twoDay ? '2-DAY RACE' : '7-DAY RACE';
}

class QuickCreateRaceSheet extends StatefulWidget {
  const QuickCreateRaceSheet({
    super.key,
    required this.onCreate,
    required this.onCustomize,
  });

  final Future<void> Function(QuickRacePreset preset) onCreate;
  final VoidCallback onCustomize;

  @override
  State<QuickCreateRaceSheet> createState() => _QuickCreateRaceSheetState();
}

class _QuickCreateRaceSheetState extends State<QuickCreateRaceSheet> {
  QuickRacePreset? _creating;
  String? _error;

  Future<void> _create(QuickRacePreset preset) async {
    if (_creating != null) return;
    setState(() {
      _creating = preset;
      _error = null;
    });
    try {
      await widget.onCreate(preset);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = null;
        _error = error is ApiException
            ? fundedExposureErrorCopy(error)
            : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottom),
        child: GameContainer(
          frameColor: AppColors.of(context).accent,
          surfaceColor: AppColors.of(context).parchmentLight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'START A RACE',
                textAlign: TextAlign.center,
                style: HomeText.display(
                  size: 24,
                  color: AppColors.of(context).ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick a length. Your race starts when another walker joins.',
                textAlign: TextAlign.center,
                style: HomeText.body(
                  size: 13,
                  color: AppColors.of(context).muted,
                ),
              ),
              const SizedBox(height: 18),
              for (final preset in QuickRacePreset.values) ...[
                PillButton(
                  key: Key('quick-create-${preset.days}d'),
                  label: _creating == preset ? 'CREATING…' : preset.label,
                  icon: preset == QuickRacePreset.twoDay
                      ? Icons.bolt_rounded
                      : Icons.flag_rounded,
                  fullWidth: true,
                  onPressed: _creating == null ? () => _create(preset) : null,
                ),
                const SizedBox(height: 10),
              ],
              PillButton(
                key: const Key('quick-create-customize'),
                label: 'CUSTOMIZE…',
                icon: Icons.tune_rounded,
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                onPressed: _creating == null ? widget.onCustomize : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  key: const Key('quick-create-error'),
                  _error!,
                  textAlign: TextAlign.center,
                  style: HomeText.body(
                    size: 12,
                    color: AppColors.of(context).accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
