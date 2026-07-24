import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'app_avatar.dart';
import 'fire_aura.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/race_participant_display.dart';

/// A styled wooden plank for leaderboard rows with medal and depth.
class LeaderboardPlank extends StatelessWidget {
  final int rank;
  final String name;
  final int steps;
  final bool isUser;
  final bool isStealthed;
  final bool isFinished;
  final int? finishPlace;
  final String formattedSteps;
  final List<Widget> effectIcons;
  final String? profilePhotoUrl;

  /// The participant's current (stacked, global-event-inclusive) step
  /// multiplier from the backend. Nullable/absent on older backends → no badge
  /// and no fire (safe degradation). Semantics: >1 buffed (fire + "Nx" badge),
  /// 1 neutral (nothing), 0 frozen (frost chip), <0 reversed (reversed chip).
  final double? currentMultiplier;

  // Issue 1: team races render larger, more legible rows. These default to the
  // solo/ranked values so those layouts are UNCHANGED; the team-grouped
  // standings pass bumped sizes.
  final double avatarSize;
  final double nameSize;
  final double stepsSize;
  final double verticalPadding;

  const LeaderboardPlank({
    super.key,
    required this.rank,
    required this.name,
    required this.steps,
    required this.formattedSteps,
    this.isUser = false,
    this.isStealthed = false,
    this.isFinished = false,
    this.finishPlace,
    this.effectIcons = const [],
    this.profilePhotoUrl,
    this.currentMultiplier,
    this.avatarSize = 32,
    this.nameSize = 15,
    this.stepsSize = 16,
    this.verticalPadding = 8,
  });

  Color? _medalColor(BuildContext context) {
    switch (rank) {
      case 0:
        return AppColors.of(context).medalGold;
      case 1:
        return AppColors.of(context).medalSilver;
      case 2:
        return AppColors.of(context).medalBronze;
      default:
        return null;
    }
  }

  /// The avatar, optionally wrapped in a fire aura when the multiplier is >1.
  /// A stealthed runner never shows fire (its own multiplier is hidden). The
  /// fire is centered behind the avatar via an [OverflowBox] so it can lick
  /// past the edges without changing the row's layout size.
  Widget _buildAvatar(BuildContext context) {
    final avatar = AppAvatar(
      // The raw name, not displayName: the " (you)" suffix would turn the
      // fallback initials into "M(".
      name: isStealthed ? '???' : name,
      imageUrl: isStealthed ? null : profilePhotoUrl,
      size: avatarSize,
      isUser: isUser,
      isStealthed: isStealthed,
      borderColor: isUser ? AppColors.of(context).accent : Colors.white,
    );

    final m = currentMultiplier;
    if (isStealthed || m == null || m <= 1.001) return avatar;

    final tier = m.floor();
    final fireSize = avatarSize * (1.55 + 0.12 * (tier - 2).clamp(0, 4));
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          OverflowBox(
            maxWidth: fireSize,
            maxHeight: fireSize,
            child: FireAura(size: fireSize, tier: tier),
          ),
          avatar,
        ],
      ),
    );
  }

  /// The name-row chip reflecting the multiplier: "Nx" for a buff, a frost chip
  /// when frozen (0), a reversed chip when negative. Null (no chip) at exactly
  /// 1x, a mild sub-1 debuff, absent multiplier, or for a stealthed runner.
  Widget? _multiplierChip(BuildContext context) {
    final m = currentMultiplier;
    if (isStealthed || m == null) return null;
    if (m <= -0.001) {
      // Reversed (e.g. Wrong Turn) — steps counting backward.
      return _chip(
        context,
        icon: Icons.u_turn_left_rounded,
        label: '${_fmtMult(m.abs())}x',
        bg: AppColors.of(context).feedAttack,
      );
    }
    if (m < 0.5) {
      // Frozen (e.g. Leg Cramp) — no forward progress.
      return _chip(
        context,
        icon: Icons.ac_unit_rounded,
        label: 'FROZEN',
        bg: AppColors.of(context).feedShield,
      );
    }
    if (m > 1.001) {
      // Buffed — warm ember chip to match the fire aura.
      return _chip(
        context,
        icon: Icons.local_fire_department_rounded,
        label: '${_fmtMult(m)}x',
        bg: const Color(0xFFE8622A),
      );
    }
    return null;
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: bg.withValues(alpha: 0.85), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: bg),
          const SizedBox(width: 3),
          Text(label, style: PixelText.title(size: 10, color: bg)),
        ],
      ),
    );
  }

  static String _fmtMult(double v) {
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 0.05) return rounded.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final medalColor = _medalColor(context);
    final displayName = isStealthed ? '???' : (isUser ? '$name (you)' : name);
    final finishLabel = finishPlace == null
        ? 'FINISH'
        : '${formatOrdinal(finishPlace!)} FINISH';

    return Padding(
      padding: EdgeInsets.only(top: rank == 0 ? 0 : 4),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: isFinished
              ? AppColors.of(context).coinLight.withValues(alpha: 0.14)
              : medalColor?.withValues(alpha: 0.08) ??
                    AppColors.of(context).parchmentDark.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFinished
                ? AppColors.of(context).coinDark.withValues(alpha: 0.45)
                : medalColor?.withValues(alpha: 0.3) ??
                      AppColors.of(
                        context,
                      ).parchmentBorder.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: isFinished
              ? [
                  BoxShadow(
                    color: AppColors.of(
                      context,
                    ).coinDark.withValues(alpha: 0.18),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Medal/rank badge
            SizedBox(
              width: 26,
              height: 30,
              child: CustomPaint(
                painter: _MedalPainter(
                  rank: rank,
                  color: medalColor ?? AppColors.of(context).woodMid,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildAvatar(context),
            const SizedBox(width: 8),
            // Name + effects
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      atName(displayName),
                      style: PixelText.body(
                        size: nameSize,
                        color: isStealthed
                            ? AppColors.of(
                                context,
                              ).textMid.withValues(alpha: 0.5)
                            : isUser
                            ? AppColors.of(context).textAccent
                            : AppColors.of(context).textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...() {
                    final chip = _multiplierChip(context);
                    return chip == null
                        ? const <Widget>[]
                        : [const SizedBox(width: 6), chip];
                  }(),
                  if (effectIcons.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    ...effectIcons,
                  ],
                  if (isFinished && !isStealthed) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.of(context).roofLight,
                            AppColors.of(context).roofMid,
                            AppColors.of(context).roofDark,
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.of(
                            context,
                          ).coinLight.withValues(alpha: 0.9),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.of(
                              context,
                            ).coinDark.withValues(alpha: 0.45),
                            offset: const Offset(0, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 12,
                            color: AppColors.of(context).coinLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            finishLabel,
                            style: PixelText.title(
                              size: 9.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Step count
            Text(
              isStealthed ? '???' : formattedSteps,
              style: PixelText.number(
                size: stepsSize,
                color: isStealthed
                    ? AppColors.of(context).textMid.withValues(alpha: 0.5)
                    : AppColors.of(context).textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a shield/medallion shape with the rank number inside.
class _MedalPainter extends CustomPainter {
  final int rank;
  final Color color;

  _MedalPainter({required this.rank, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shield path
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.08)
      ..lineTo(w, h * 0.65)
      ..quadraticBezierTo(w, h * 0.85, w * 0.5, h)
      ..quadraticBezierTo(0, h * 0.85, 0, h * 0.65)
      ..lineTo(0, h * 0.08)
      ..close();

    // Fill
    final fillPaint = Paint()..color = color;
    canvas.drawPath(path, fillPaint);

    // Dark border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.6) == color
          ? AppColors.woodShadow
          : Color.lerp(color, Colors.black, 0.4)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);

    // Inner highlight
    final highlightPath = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.88, h * 0.14)
      ..lineTo(w * 0.88, h * 0.45)
      ..quadraticBezierTo(w * 0.88, h * 0.55, w * 0.5, h * 0.65)
      ..quadraticBezierTo(w * 0.12, h * 0.55, w * 0.12, h * 0.45)
      ..lineTo(w * 0.12, h * 0.14)
      ..close();
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawPath(highlightPath, highlightPaint);

    // Rank text
    final labels = ['1', '2', '3'];
    final label = rank < 3 ? labels[rank] : '${rank + 1}';

    final paragraphBuilder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: h * 0.4,
              fontWeight: FontWeight.w900,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: Colors.white,
              fontSize: h * 0.4,
              fontWeight: FontWeight.w900,
              shadows: [
                const Shadow(
                  color: Color(0x80000000),
                  offset: Offset(1, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          )
          ..addText(label);

    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: w));

    canvas.drawParagraph(
      paragraph,
      Offset(0, (h - paragraph.height) / 2 - h * 0.02),
    );
  }

  @override
  bool shouldRepaint(covariant _MedalPainter oldDelegate) =>
      oldDelegate.rank != rank || oldDelegate.color != color;
}
