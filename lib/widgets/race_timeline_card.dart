import 'package:flutter/material.dart';

import '../styles.dart';
import 'retro_card.dart';

/// The TIMELINE card — the one control that says how long a race runs.
///
/// Shared by `CreateRaceScreen` and `EditRaceScreen` **on purpose** (race
/// timeline options spec §6 / §10.1 risk 5): the two screens' duration blocks
/// were already near-identical copies, which is exactly why both needed editing
/// for this feature. A third copy guarantees the next chip change misses one.
///
/// Visually it stays inside the app's carved-arcade language: pixel type,
/// parchment plates, a pressed-in selected chip with a hard 2px shadow, and the
/// custom window revealed as an inset panel **within the same card** rather
/// than a new card below it.
///
/// The widget is stateless: every value is owned by the hosting screen, because
/// `scheduledStartAt` must have exactly one writer (spec §4.3).

/// The three presets left on the picker. `3` is retired from the UI but stays a
/// legal server-side value — frozen clients still send it and 3-day races exist
/// in prod, so nothing about validation or the prize-pool bands changed.
const List<int> kRaceTimelinePresets = [1, 7, 14];

/// `1 DAY` / `1 WEEK` / `2 WEEKS`. Anything else degrades to the old `Nd` form
/// rather than throwing, so an unexpected value still renders.
String raceTimelinePresetLabel(int days) {
  switch (days) {
    case 1:
      return '1 DAY';
    case 7:
      return '1 WEEK';
    case 14:
      return '2 WEEKS';
    default:
      return '${days}d';
  }
}

const List<String> _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Fri, Aug 22 · 5:00 PM`, in the device's local zone — the window is picked
/// on a local clock and stored as an absolute instant (spec §2).
String formatRaceTimelineInstant(DateTime instant) {
  final local = instant.toLocal();
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour < 12 ? 'AM' : 'PM';
  return '${weekdays[local.weekday - 1]}, '
      '${_monthAbbrev[local.month - 1]} ${local.day} · '
      '$hour:$minute $meridiem';
}

/// `4 DAYS 9 HOURS` — the live length under the two pickers. Minutes are
/// deliberately dropped: the floor is a day, so minute precision is noise.
String raceWindowLengthLabel(Duration window) {
  if (window.isNegative) return '—';
  final days = window.inDays;
  final hours = window.inHours - days * 24;
  final parts = <String>[];
  if (days > 0) parts.add('$days ${days == 1 ? 'DAY' : 'DAYS'}');
  if (hours > 0 || days == 0) {
    parts.add('$hours ${hours == 1 ? 'HOUR' : 'HOURS'}');
  }
  return parts.join(' ');
}

/// Bara-themed wrapper for the stock Material date/time pickers: parchment
/// surfaces, accent-green selection, wood-frame border — so they read like the
/// app's RetroCard dialogs instead of raw Material 3.
///
/// **Not optional** (§10.1 risk 7): the onboarding flow pins a light `Theme`
/// above these screens, so an unthemed picker renders black-on-black fields at
/// night. Every date/time picker opened from a race timeline passes this as its
/// `builder`.
Widget raceThemedPickerBuilder(BuildContext context, Widget? child) {
  final base = Theme.of(context);
  final palette = AppColors.of(context);
  return Theme(
    data: base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: palette.accent,
        onPrimary: palette.parchment,
        secondary: palette.accentLight,
        surface: palette.parchment,
        onSurface: palette.textDark,
        onSurfaceVariant: palette.textMid,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.parchment,
        headerBackgroundColor: palette.accent,
        headerForegroundColor: palette.parchment,
        weekdayStyle: PixelText.body(size: 13, color: palette.textMid),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.accent, width: 2),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: palette.parchment,
        dialBackgroundColor: palette.parchmentDark,
        dialHandColor: palette.accent,
        hourMinuteColor: palette.parchmentDark,
        hourMinuteTextColor: palette.textDark,
        dayPeriodTextColor: palette.textDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.accent, width: 2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          textStyle: PixelText.button(size: 14, color: palette.buttonText),
        ),
      ),
    ),
    child: child!,
  );
}

class RaceTimelineCard extends StatelessWidget {
  const RaceTimelineCard({
    super.key,
    this.outerKey,
    required this.selectedDays,
    this.customSelected = false,
    this.customChipEnabled = false,
    this.customStartAt,
    this.customEndAt,
    this.windowError,
    this.onPresetSelected,
    this.onCustomSelected,
    this.onPickStart,
    this.onPickEnd,
    this.readOnly = false,
    this.readOnlyEndsAt,
  });

  /// Applied at the OUTERMOST node of this widget (§10.1 risk 3). The demo
  /// coach spotlights the whole card by measuring this key's render box; if it
  /// landed on the chip `Row` instead, the cut-out would mis-aim with no
  /// compile error and no failing test.
  final Key? outerKey;

  /// The preset currently selected. Ignored while [customSelected].
  final int selectedDays;
  final bool customSelected;

  /// Whether the CUSTOM chip is offered at all
  /// (`featureFlags.customRaceWindowEnabled`, default false).
  final bool customChipEnabled;

  /// The window's start — `null` means no scheduled start, which is not "now"
  /// but "when everyone's in" (architect R2): an unscheduled private race
  /// already auto-starts once it has two accepted runners and no open invites.
  final DateTime? customStartAt;
  final DateTime? customEndAt;

  /// Set when the picked window breaks a rule; shown in place of the derived
  /// length, in the error colour. The host also disables its submit button.
  final String? windowError;

  final ValueChanged<int>? onPresetSelected;
  final VoidCallback? onCustomSelected;
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;

  /// A started race's end is history: no chips, no pickers, just the stamped
  /// instant. Editing it would 400 with `RACE_ALREADY_STARTED`.
  final bool readOnly;
  final DateTime? readOnlyEndsAt;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return KeyedSubtree(
      key: outerKey,
      child: RetroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TIMELINE',
              style: PixelText.title(size: 13, color: palette.textMid),
            ),
            const SizedBox(height: 10),
            if (readOnly)
              _readOnlyBody(context)
            else ...[
              Row(children: _chips(context)),
              // The custom window lives INSIDE this card, growing it rather
              // than appearing as a second card under the plaque.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                // Three states, not two. With the kill switch off on a race
                // that already HAS a window, the window is shown but locked:
                // the server still accepts the clear (that is the creator's
                // escape hatch) while refusing any new end, so the presets stay
                // live above and only the pickers go away.
                child: !customSelected
                    ? const SizedBox(width: double.infinity)
                    : customChipEnabled
                    ? _customPanel(context)
                    : _lockedWindow(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _chips(BuildContext context) {
    return [
      for (final days in kRaceTimelinePresets)
        _chip(
          context,
          key: Key('duration-option-$days'),
          label: raceTimelinePresetLabel(days),
          selected: !customSelected && selectedDays == days,
          onTap: () => onPresetSelected?.call(days),
        ),
      if (customChipEnabled)
        _chip(
          context,
          key: const Key('duration-option-custom'),
          label: 'CUSTOM',
          selected: customSelected,
          onTap: () => onCustomSelected?.call(),
        ),
    ];
  }

  Widget _chip(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? palette.pillGreenDark : palette.parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? palette.pillGreenDark : palette.parchmentBorder,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.parchmentBorder,
                      offset: const Offset(0, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          // Four labels on one row on a 320dp phone: scale down rather than
          // clip or wrap ("2 WEEKS" is the tight one).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: PixelText.title(
                size: 12,
                color: selected ? Colors.white : palette.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _customPanel(BuildContext context) {
    final palette = AppColors.of(context);
    final invalid = windowError != null && windowError!.isNotEmpty;
    final start = customStartAt;
    final end = customEndAt;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        key: const Key('timeline-custom-rows'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: palette.parchmentDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.parchmentBorder, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pickerRow(
              context,
              key: const Key('timeline-starts-row'),
              label: 'STARTS',
              icon: Icons.play_arrow_rounded,
              // Not "Now (start manually)": an unscheduled race starts when the
              // field fills, which is what this copy has to promise.
              value: start == null
                  ? "When everyone's in"
                  : formatRaceTimelineInstant(start),
              muted: start == null,
              onTap: onPickStart,
            ),
            const SizedBox(height: 8),
            _pickerRow(
              context,
              key: const Key('timeline-ends-row'),
              label: 'ENDS',
              icon: Icons.flag_rounded,
              value: end == null ? 'Pick an end' : formatRaceTimelineInstant(end),
              muted: end == null,
              onTap: onPickEnd,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _hairline(context)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    invalid
                        ? windowError!
                        : (start == null || end == null
                              ? '—'
                              : raceWindowLengthLabel(end.difference(start))),
                    key: const Key('timeline-window-label'),
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 11,
                      color: invalid ? palette.error : palette.textMid,
                    ),
                  ),
                ),
                Expanded(child: _hairline(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The custom window, shown but not editable: the kill switch is off and
  /// this race already has one.
  ///
  /// It is deliberately NOT the same as [readOnly]. A started race is a dead
  /// end — every chip would 400. Here the presets above are live and tapping
  /// one CLEARS the window, which the server permits with the flag off
  /// precisely so a creator is never stranded holding a window it no longer
  /// honors. So the user has to be able to see what they are about to clear.
  Widget _lockedWindow(BuildContext context) {
    final palette = AppColors.of(context);
    final start = customStartAt;
    final end = customEndAt;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        key: const Key('timeline-locked-window'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: palette.parchmentDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.parchmentBorder, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, size: 13, color: palette.textMid),
                const SizedBox(width: 6),
                Text(
                  'CUSTOM WINDOW',
                  style: PixelText.title(size: 11, color: palette.textMid),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _lockedRow(
              context,
              label: 'STARTS',
              value: start == null
                  ? "When everyone's in"
                  : formatRaceTimelineInstant(start),
            ),
            const SizedBox(height: 4),
            _lockedRow(
              context,
              label: 'ENDS',
              value: end == null ? '—' : formatRaceTimelineInstant(end),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a length above to replace this window.',
              key: const Key('timeline-locked-note'),
              style: PixelText.body(size: 11, color: palette.textMid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockedRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final palette = AppColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: PixelText.body(size: 11, color: palette.textMid),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PixelText.body(size: 12, color: palette.textDark),
          ),
        ),
      ],
    );
  }

  Widget _hairline(BuildContext context) => Container(
    height: 2,
    color: AppColors.of(context).parchmentBorder,
  );

  Widget _pickerRow(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required String value,
    required bool muted,
    VoidCallback? onTap,
  }) {
    final palette = AppColors.of(context);
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: PixelText.body(size: 11, color: palette.textMid),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: palette.parchment,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.parchmentBorder, width: 2),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: palette.textMid),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(
                        size: 12,
                        color: muted
                            ? palette.textMid
                            : palette.textDark,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: palette.textMid.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyBody(BuildContext context) {
    final palette = AppColors.of(context);
    final end = readOnlyEndsAt;
    return Container(
      key: const Key('timeline-readonly-end'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.parchmentBorder, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 14, color: palette.textMid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              end == null
                  ? 'This race is already running.'
                  : 'Ends ${formatRaceTimelineInstant(end)}',
              style: PixelText.body(size: 12, color: palette.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
