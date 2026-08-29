import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../styles.dart';
import 'arcade_tab_selector.dart';
import 'game_container.dart';
import 'powerup_icon.dart';

class PowerupGuideSheet extends StatefulWidget {
  const PowerupGuideSheet({super.key});

  @override
  State<PowerupGuideSheet> createState() => _PowerupGuideSheetState();
}

class _PowerupGuideSheetState extends State<PowerupGuideSheet> {
  final ScrollController _powerupsController = ScrollController();
  final ScrollController _stackingController = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _powerupsController.dispose();
    _stackingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = PowerupCopy.guideEntries;
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.of(context).woodMid,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'POWERUP CHEAT SHEET',
                style: PixelText.title(
                  size: 19,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ArcadeTabSelector(
                labels: const ['POWERUPS', 'STACKING'],
                activeIndex: _page,
                onChanged: (page) => setState(() => _page = page),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: IndexedStack(
                  index: _page,
                  children: [
                    ListView.separated(
                      key: const Key('powerup-guide-powerups-page'),
                      controller: _powerupsController,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) =>
                          _PowerupManualRow(entry: entries[index]),
                    ),
                    ListView.separated(
                      key: const Key('powerup-guide-stacking-page'),
                      controller: _stackingController,
                      itemCount: entries.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        if (index == 0) return const _StackingIntro();
                        return _StackingManualRow(entry: entries[index - 1]);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PowerupManualRow extends StatelessWidget {
  const _PowerupManualRow({required this.entry});
  final PowerupCopyEntry entry;

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.all(11),
      frameColor: AppColors.of(context).parchmentBorder,
      surfaceColor: AppColors.of(context).parchmentLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PowerupIcon(
            type: entry.type,
            size: 36,
            spinning: !MediaQuery.disableAnimationsOf(context),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.description,
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StackingIntro extends StatelessWidget {
  const _StackingIntro();

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.all(12),
      frameColor: AppColors.of(context).pillGoldDark,
      surfaceColor: AppColors.of(context).parchmentLight,
      child: Text(
        '“Stacking” can mean using another copy of the same powerup while one '
        'is active, or combining different effects at the same time. Each '
        'entry explains both rules.',
        style: PixelText.body(size: 12, color: AppColors.of(context).textDark),
      ),
    );
  }
}

class _StackingManualRow extends StatelessWidget {
  const _StackingManualRow({required this.entry});
  final PowerupCopyEntry entry;

  String _sameLabel(SamePowerupStacking value) => switch (value) {
    SamePowerupStacking.notApplicable => 'NOT APPLICABLE',
    SamePowerupStacking.blocked => 'BLOCKED',
    SamePowerupStacking.extendsDuration => 'EXTENDS',
    SamePowerupStacking.allowed => 'ALLOWED',
    SamePowerupStacking.limited => 'LIMITED',
  };

  String _otherLabel(OtherEffectsStacking value) => switch (value) {
    OtherEffectsStacking.notApplicable => 'NOT APPLICABLE',
    OtherEffectsStacking.allowed => 'ALLOWED',
    OtherEffectsStacking.conditional => 'CONDITIONAL',
    OtherEffectsStacking.conflicts => 'CONFLICTS',
  };

  @override
  Widget build(BuildContext context) {
    final rule = entry.stacking;
    return GameContainer(
      padding: const EdgeInsets.all(11),
      frameColor: AppColors.of(context).parchmentBorder,
      surfaceColor: AppColors.of(context).parchmentLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PowerupIcon(
                type: entry.type,
                size: 34,
                spinning: !MediaQuery.disableAnimationsOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.name,
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (rule == null)
            Text(
              'Stacking details unavailable',
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            )
          else ...[
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _RulePlate(
                  title: 'SAME POWERUP',
                  value: _sameLabel(rule.samePowerup),
                ),
                _RulePlate(
                  title: 'OTHER EFFECTS',
                  value: _otherLabel(rule.otherEffects),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rule.summary,
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textMid,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RulePlate extends StatelessWidget {
  const _RulePlate({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.of(context).parchmentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: PixelText.title(
              size: 9,
              color: AppColors.of(context).textMid,
            ),
          ),
          Text(
            value,
            style: PixelText.title(
              size: 11,
              color: AppColors.of(context).textDark,
            ),
          ),
        ],
      ),
    );
  }
}
