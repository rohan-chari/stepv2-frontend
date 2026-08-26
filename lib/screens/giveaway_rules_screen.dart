import 'dart:async';

import 'package:flutter/material.dart';
import '../models/giveaway.dart';
import '../styles.dart';
import '../theme_controller.dart';
import '../widgets/pill_button.dart';

/// In-app presentation of the exact server-owned rules accepted by an entrant.
class GiveawayRulesScreen extends StatefulWidget {
  const GiveawayRulesScreen({
    super.key,
    required this.contest,
    this.onJoin,
    this.onSetDisplayName,
    this.displayNameReady = true,
  });

  final GiveawayContest contest;
  final Future<String?> Function()? onJoin;
  final Future<bool> Function()? onSetDisplayName;
  final bool displayNameReady;

  @override
  State<GiveawayRulesScreen> createState() => _GiveawayRulesScreenState();
}

class _GiveawayRulesScreenState extends State<GiveawayRulesScreen> {
  bool _accepted = false;
  bool _joining = false;
  late bool _displayNameReady;
  String? _error;
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    _displayNameReady = widget.displayNameReady;
    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    super.dispose();
  }

  bool get _entryOpen =>
      widget.contest.status == GiveawayStatus.active &&
      widget.contest.endsAt.isAfter(DateTime.now().toUtc());

  Future<void> _submit() async {
    if (_joining || !_accepted || widget.onJoin == null) return;
    if (!_entryOpen) {
      setState(() => _error = 'This contest is no longer open.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    final error = await widget.onJoin!();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _joining = false;
      _error = error;
    });
  }

  Future<void> _setDisplayName() async {
    final action = widget.onSetDisplayName;
    if (action == null) return;
    final ready = await action();
    if (!mounted) return;
    setState(() {
      _displayNameReady = ready;
      _error = ready ? null : 'Set a Bara display name before joining.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contest.eligibilityMode != GiveawayEligibilityMode.baraAccount) {
      return _LegacyGiveawayRulesView(contest: widget.contest);
    }
    final colors = AppColors.of(context);
    final showJoin = widget.onJoin != null && _entryOpen;
    return Scaffold(
      backgroundColor: colors.roofLight,
      body: SafeArea(
        bottom: false,
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(drawBottomStripe: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _RulesHeader(),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('giveaway-rules-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CompactContestSummary(contest: widget.contest),
                      const SizedBox(height: 22),
                      const _RulesTitle(),
                      const SizedBox(height: 14),
                      _RulesDocument(contest: widget.contest),
                    ],
                  ),
                ),
              ),
              if (showJoin)
                _AgreementFooter(
                  accepted: _accepted,
                  joining: _joining,
                  displayNameReady: _displayNameReady,
                  error: _error,
                  onToggle: _joining
                      ? null
                      : () => setState(() => _accepted = !_accepted),
                  onPressed: !_displayNameReady
                      ? _setDisplayName
                      : _accepted && !_joining
                      ? _submit
                      : null,
                )
              else if (widget.onJoin != null)
                _ClosedContestFooter(contest: widget.contest),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulesHeader extends StatelessWidget {
  const _RulesHeader();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      height: 68,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: IconButton(
              tooltip: 'Back',
              iconSize: 30,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, color: colors.textLight),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'BARA REFERRAL CONTEST',
                textAlign: TextAlign.center,
                style: PixelText.display(size: 16, color: colors.textLight),
              ),
            ),
          ),
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _CompactContestSummary extends StatelessWidget {
  const _CompactContestSummary({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('giveaway-rules-summary-card'),
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: _panelDecoration(context),
      child: Row(
        children: [
          Image.asset(
            'assets/images/referral/pixel_trophy.png',
            width: 56,
            height: 56,
            filterQuality: FilterQuality.none,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${_commas(contest.prize.coins)} COINS',
                    style: PixelText.title(
                      size: 23,
                      color: colors.pillGoldDark,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _timeLeft(contest),
                  style: PixelText.body(size: 14, color: colors.textDark),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusBadge(contest: contest),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final open =
        contest.status == GiveawayStatus.active &&
        contest.endsAt.isAfter(DateTime.now().toUtc());
    final label = open
        ? 'OPEN'
        : contest.status == GiveawayStatus.scheduled
        ? 'SOON'
        : 'ENDED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: open
            ? colors.pillGreen.withValues(alpha: .16)
            : colors.roofDark.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: PixelText.title(
          size: 12,
          color: open ? colors.grassDark : colors.textMid,
        ),
      ),
    );
  }
}

class _RulesTitle extends StatelessWidget {
  const _RulesTitle();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 14)),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'OFFICIAL RULES',
              style: PixelText.display(size: 17, color: colors.textLight),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('✦', style: TextStyle(color: colors.pillGold, fontSize: 14)),
      ],
    );
  }
}

class _RulesDocument extends StatelessWidget {
  const _RulesDocument({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final sections = _presentedSections(contest);
    return Container(
      key: const Key('giveaway-rules-document-card'),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
      decoration: _panelDecoration(context),
      child: Column(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            _RuleSection(section: sections[index]),
            if (index != sections.length - 1) const _GoldDivider(),
          ],
        ],
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({required this.section});

  final _PresentedRule section;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          section.asset,
          width: 38,
          height: 38,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.heading,
                style: PixelText.display(size: 15, color: colors.grassDark),
              ),
              const SizedBox(height: 5),
              if (section.sponsor case final sponsor?) ...[
                SelectableText(
                  sponsor,
                  style: PixelText.body(
                    size: 14,
                    color: colors.textDark,
                  ).copyWith(height: 1.35, fontWeight: FontWeight.w700),
                ),
                if (section.address case final address?)
                  SelectableText(
                    address,
                    style: PixelText.body(
                      size: 14,
                      color: colors.textDark,
                    ).copyWith(height: 1.35),
                  ),
                const SizedBox(height: 5),
              ],
              SelectableText(
                section.body,
                style: PixelText.body(
                  size: 14,
                  color: colors.textDark,
                ).copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoldDivider extends StatelessWidget {
  const _GoldDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 17),
    color: AppColors.of(context).pillGold.withValues(alpha: .42),
  );
}

class _AgreementFooter extends StatelessWidget {
  const _AgreementFooter({
    required this.accepted,
    required this.joining,
    required this.displayNameReady,
    required this.error,
    required this.onToggle,
    required this.onPressed,
  });

  final bool accepted;
  final bool joining;
  final bool displayNameReady;
  final String? error;
  final VoidCallback? onToggle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const Key('giveaway-rules-sticky-footer'),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 12),
      decoration: BoxDecoration(
        color: colors.parchment,
        border: Border(
          top: BorderSide(
            color: colors.roofDark.withValues(alpha: .4),
            width: 1.5,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x35183021),
            offset: Offset(0, -3),
            blurRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            toggled: accepted,
            label: 'I agree to the contest rules',
            child: InkWell(
              key: const Key('giveaway-global-rules-accepted'),
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: ExcludeSemantics(
                        child: Checkbox(
                          value: accepted,
                          onChanged: onToggle == null
                              ? null
                              : (_) => onToggle!(),
                          activeColor: colors.pillGreen,
                          checkColor: colors.textLight,
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? colors.pillGreen
                                : colors.parchment,
                          ),
                          side: BorderSide(color: colors.roofDark, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        'I agree to the contest rules',
                        style: PixelText.body(
                          size: 15,
                          color: colors.textDark,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (error case final message?) ...[
            const SizedBox(height: 3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: PixelText.body(size: 12, color: colors.error),
            ),
          ],
          const SizedBox(height: 8),
          Semantics(
            button: true,
            enabled: onPressed != null,
            label: displayNameReady
                ? 'Join referral contest'
                : 'Set display name',
            child: PillButton(
              label: !displayNameReady
                  ? 'SET DISPLAY NAME'
                  : joining
                  ? 'JOINING…'
                  : 'JOIN CONTEST',
              variant: PillButtonVariant.secondary,
              fontSize: 22,
              fullWidth: true,
              loading: false,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedContestFooter extends StatelessWidget {
  const _ClosedContestFooter({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      color: colors.parchment,
      child: Text(
        contest.status == GiveawayStatus.scheduled
            ? 'THIS CONTEST IS NOT OPEN YET'
            : 'THIS CONTEST IS NO LONGER OPEN',
        textAlign: TextAlign.center,
        style: PixelText.title(size: 14, color: colors.textDark),
      ),
    );
  }
}

/// The published US_18 contest contract predates the Bara-account contest.
/// Keep its read-only presentation intact so this visual refresh cannot hide
/// cash, sponsor, address, timezone, or immutable-rules metadata.
class _LegacyGiveawayRulesView extends StatelessWidget {
  const _LegacyGiveawayRulesView({required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.roofLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.roofLight),
              child: CustomPaint(
                painter: const ArcadeCheckerPainter(drawBottomStripe: false),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: colors.textLight),
                      ),
                      Expanded(
                        child: Text(
                          'OFFICIAL RULES',
                          style: PixelText.title(
                            size: 22,
                            color: colors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                children: [
                  _LegacyRulesCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contest.title,
                          style: PixelText.title(
                            size: 20,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Rules version ${contest.rules.version}',
                          style: PixelText.body(
                            size: 12,
                            color: colors.textMid,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Open to legal residents of the 50 United States and D.C., age ${contest.minimumAge ?? 18}+. No purchase necessary.',
                          style: PixelText.body(
                            size: 14,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Contest window (UTC): ${contest.startsAt.toUtc().toIso8601String()} through ${contest.endsAt.toUtc().toIso8601String()}. Governing timezone: ${contest.governingTimeZone}.',
                          style: PixelText.body(
                            size: 13,
                            color: colors.textMid,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'SPONSOR',
                          style: PixelText.title(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          contest.sponsorLegalName ?? contest.sponsorName,
                          style: PixelText.body(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        if (contest.sponsorMailingAddress case final address?)
                          SelectableText(
                            address,
                            style: PixelText.body(
                              size: 13,
                              color: colors.textMid,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final section in contest.rules.sections) ...[
                    const SizedBox(height: 14),
                    _LegacyRulesCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.heading,
                            style: PixelText.title(
                              size: 16,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            section.body,
                            style: PixelText.body(
                              size: 14,
                              color: colors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _LegacyRulesCard(
                    child: Text(
                      'Apple and Google are not sponsors, administrators, endorsers, or otherwise involved in this promotion.',
                      style: PixelText.body(size: 13, color: colors.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyRulesCard extends StatelessWidget {
  const _LegacyRulesCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).parchmentBorder,
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _PresentedRule {
  const _PresentedRule({
    required this.heading,
    required this.body,
    required this.asset,
    this.sponsor,
    this.address,
  });

  final String heading;
  final String body;
  final String asset;
  final String? sponsor;
  final String? address;
}

List<_PresentedRule> _presentedSections(GiveawayContest contest) {
  final sections = <_PresentedRule>[];
  var hasEligibility = false;
  var hasWindow = false;
  var hasPlatformsOrSponsor = false;

  for (final rule in contest.rules.sections) {
    final normalized = rule.heading.toLowerCase();
    hasEligibility |=
        normalized.contains('who can') ||
        normalized.contains('eligib') ||
        normalized.contains('enter');
    hasWindow |= normalized.contains('window') || normalized.contains('date');
    hasPlatformsOrSponsor |=
        normalized.contains('platform') ||
        normalized.contains('sponsor') ||
        rule.body.toLowerCase().contains('apple and google');
  }

  if (!hasEligibility) {
    sections.add(
      _PresentedRule(
        heading: 'Who can join',
        body: contest.eligibilitySummary,
        asset: 'assets/images/referral/rules_who_can_join.png',
      ),
    );
  }
  if (!hasWindow) {
    sections.add(
      _PresentedRule(
        heading: 'Contest window',
        body: _contestWindow(contest),
        asset: 'assets/images/referral/rules_contest_window.png',
      ),
    );
  }

  for (final rule in contest.rules.sections) {
    final normalized = rule.heading.toLowerCase();
    sections.add(
      _PresentedRule(
        heading: rule.heading,
        body: _formatEasternIsoInstants(rule.body),
        asset: _assetForHeading(normalized),
      ),
    );
  }

  if (!hasPlatformsOrSponsor) {
    final sponsor = contest.sponsorLegalName ?? contest.sponsorName;
    final address = contest.sponsorMailingAddress;
    sections.add(
      _PresentedRule(
        heading: 'Platforms & sponsor',
        body:
            'Apple and Google are not sponsors, administrators, endorsers, or otherwise involved in this contest.',
        asset: 'assets/images/referral/rules_platforms_sponsor.png',
        sponsor: sponsor,
        address: address,
      ),
    );
  }
  return sections;
}

String _assetForHeading(String heading) {
  if (heading.contains('rank') || heading.contains('review')) {
    return 'assets/images/referral/rules_ranking_review.png';
  }
  if (heading.contains('win')) {
    return 'assets/images/referral/pixel_trophy.png';
  }
  if (heading.contains('prize')) {
    return 'assets/images/referral/rules_prize.png';
  }
  if (heading.contains('platform') || heading.contains('sponsor')) {
    return 'assets/images/referral/rules_platforms_sponsor.png';
  }
  if (heading.contains('window') || heading.contains('date')) {
    return 'assets/images/referral/rules_contest_window.png';
  }
  return 'assets/images/referral/rules_who_can_join.png';
}

BoxDecoration _panelDecoration(BuildContext context) {
  final colors = AppColors.of(context);
  return BoxDecoration(
    color: colors.parchment,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(
      color: colors.roofDark.withValues(alpha: .48),
      width: 1.5,
    ),
    boxShadow: const [
      BoxShadow(color: Color(0xA6183021), offset: Offset(0, 5), blurRadius: 1),
    ],
  );
}

String _contestWindow(GiveawayContest contest) {
  return 'The contest runs from ${_easternDateTime(contest.startsAt)} through ${_easternDateTime(contest.endsAt)}.';
}

String _formatEasternIsoInstants(String value) {
  final formatted = value.replaceAllMapped(
    RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z'),
    (match) {
      final instant = DateTime.tryParse(match.group(0)!);
      return instant == null ? match.group(0)! : _easternDateTime(instant);
    },
  );
  return formatted.replaceAll(RegExp(r'\b(EDT|EST) UTC\b'), r'$1');
}

String _easternDateTime(DateTime instant) {
  const months = <String>[
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
  final utc = instant.toUtc();
  final offset = AppThemeController.easternOffset(utc);
  final eastern = utc.add(offset);
  final hour = eastern.hour % 12 == 0 ? 12 : eastern.hour % 12;
  final minute = eastern.minute.toString().padLeft(2, '0');
  final period = eastern.hour < 12 ? 'AM' : 'PM';
  final zone = offset == const Duration(hours: -4) ? 'EDT' : 'EST';
  return '${months[eastern.month - 1]} ${eastern.day}, ${eastern.year} at $hour:$minute $period $zone';
}

String _commas(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _timeLeft(GiveawayContest contest) {
  if (contest.status == GiveawayStatus.finalResult ||
      contest.status == GiveawayStatus.verifying) {
    return 'ENDED';
  }
  final delta = contest.endsAt.difference(DateTime.now().toUtc());
  if (delta <= Duration.zero) return 'ENDED';
  return '${delta.inDays}D ${delta.inHours.remainder(24)}H LEFT';
}
