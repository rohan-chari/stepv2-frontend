import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';
import '../models/giveaway.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import 'display_name_screen.dart';
import 'giveaway_rules_screen.dart';
import 'referral_screen.dart' show shareReferral;

class GiveawayScreen extends StatefulWidget {
  const GiveawayScreen({
    super.key,
    required this.slug,
    required this.authService,
    this.backendApiService,
  });

  final String slug;
  final AuthService authService;
  final BackendApiService? backendApiService;

  @override
  State<GiveawayScreen> createState() => _GiveawayScreenState();
}

class _GiveawayScreenState extends State<GiveawayScreen> {
  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();
  final ScrollController _globalRulesController = ScrollController();
  GiveawayCurrent? _data;
  GiveawayContest? _cachedRules;
  bool _loading = true;
  bool _readRulesToEnd = false;
  bool _rulesAccepted = false;
  bool _joining = false;
  bool _whatCountsOpen = false;
  bool _displayNameRequired = false;
  String? _error;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _globalRulesController.addListener(_onRulesScroll);
    _load();
  }

  @override
  void dispose() {
    _globalRulesController
      ..removeListener(_onRulesScroll)
      ..dispose();
    super.dispose();
  }

  void _onRulesScroll() {
    if (!_globalRulesController.hasClients) return;
    final position = _globalRulesController.position;
    final reached =
        position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 2;
    if (reached != _readRulesToEnd && mounted) {
      setState(() => _readRulesToEnd = reached);
    }
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Contest unavailable';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.fetchCurrentGiveaway(identityToken: token);
      final parsed = GiveawayCurrent.tryParse(raw);
      if (parsed == null || parsed.contest.slug != widget.slug) {
        throw const FormatException('Malformed contest');
      }
      if (!mounted) return;
      setState(() {
        _data = parsed;
        _cachedRules = parsed.contest;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = null; // Never retain potentially stale ranking.
        _loading = false;
        _error = 'Contest unavailable';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.roofLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(colors),
            Expanded(
              child: _loading
                  ? _skeleton(colors)
                  : _data == null
                  ? _errorBody(colors)
                  : _content(_data!, colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette colors) => DecoratedBox(
    decoration: BoxDecoration(color: colors.roofLight),
    child: CustomPaint(
      painter: const ArcadeCheckerPainter(drawBottomStripe: false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, color: colors.textLight),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                _data?.contest.eligibilityMode ==
                        GiveawayEligibilityMode.baraAccount
                    ? _data?.contest.title.toUpperCase() ?? 'REFERRAL CONTEST'
                    : 'REFERRAL CONTEST',
                style: PixelText.title(size: 22, color: colors.textLight),
              ),
            ),
            IconButton(
              key: const Key('giveaway-retry'),
              tooltip: 'Refresh contest',
              onPressed: _loading ? null : _load,
              icon: Icon(Icons.refresh, color: colors.textLight),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _skeleton(AppPalette colors) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _card(colors, child: const ListSkeleton(itemCount: 3)),
      const SizedBox(height: 16),
      _card(colors, child: const ListSkeleton(itemCount: 5)),
    ],
  );

  Widget _errorBody(AppPalette colors) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
    children: [
      _card(
        colors,
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: colors.textMid),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Contest unavailable',
              style: PixelText.title(size: 18, color: colors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ordinary referrals still work. Try again later.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 13, color: colors.textMid),
            ),
            const SizedBox(height: 16),
            PillButton(label: 'RETRY', onPressed: _load),
            if (_cachedRules != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _openRules(_cachedRules!),
                child: const Text('OFFICIAL RULES'),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _content(GiveawayCurrent data, AppPalette colors) {
    if (data.contest.eligibilityMode == GiveawayEligibilityMode.baraAccount) {
      return data.entry?.status == GiveawayEntryStatus.actionRequired
          ? _globalPreEntry(data, colors)
          : _globalJoinedHub(data, colors);
    }
    final contest = data.contest;
    return SingleChildScrollView(
      key: const Key('giveaway-content-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(data, colors),
          const SizedBox(height: 14),
          _eligibility(data, colors),
          const SizedBox(height: 14),
          if (data.standing != null) ...[
            _standing(data, colors),
            const SizedBox(height: 14),
          ],
          _leaderboard(data, colors),
          const SizedBox(height: 14),
          _card(
            colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW A REFERRAL COUNTS',
                  style: PixelText.title(size: 16, color: colors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your friend must use your invite and finish a qualifying race with another real player after you enter and before the contest ends. Daily and Weekly challenges don’t count.',
                  style: PixelText.body(size: 14, color: colors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bots, duplicate accounts, self-referrals, and coordinated dummy accounts are disqualified. All positions remain subject to fraud review.',
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'SHARE YOUR INVITE',
            icon: Icons.ios_share_rounded,
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            onPressed: data.share == null ? null : () => _share(data.share!),
          ),
          if (contest.socialLinks.isNotEmpty) ...[
            const SizedBox(height: 14),
            _card(
              colors,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOLLOW BARA',
                    style: PixelText.title(size: 15, color: colors.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Optional — does not affect contest eligibility, score, or odds.',
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final link in contest.socialLinks)
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            link.url,
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(link.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _openRules(contest),
            child: const Text('OFFICIAL RULES'),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('${BackendConfig.baseUrl}/privacy.html'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('PRIVACY NOTICE'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'No purchase necessary. Open to legal residents of the 50 United States and D.C., age ${contest.minimumAge}+. Apple and Google are not sponsors, administrators, endorsers, or otherwise involved.',
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 11,
                color: colors.textLight.withValues(alpha: 0.88),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(GiveawayCurrent data, AppPalette colors) {
    final contest = data.contest;
    final status = switch (contest.status) {
      GiveawayStatus.scheduled => 'SCHEDULED',
      GiveawayStatus.active => 'PROVISIONAL',
      GiveawayStatus.verifying => 'VERIFYING',
      GiveawayStatus.finalResult => 'FINAL',
    };
    return _card(
      colors,
      borderColor: colors.coinDark,
      child: Column(
        children: [
          Icon(Icons.emoji_events_rounded, size: 42, color: colors.coinDark),
          const SizedBox(height: 6),
          Text(
            _prizeLabel(contest.prize),
            textAlign: TextAlign.center,
            style: PixelText.title(size: 23, color: colors.textDark),
          ),
          const SizedBox(height: 8),
          _badge(status, colors),
          const SizedBox(height: 8),
          Text(
            'Ends ${_utcInstant(contest.endsAt)} · ${contest.governingTimeZone} governs',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 13, color: colors.textMid),
          ),
          if (_remaining(contest.endsAt) case final remaining?) ...[
            const SizedBox(height: 3),
            Text(
              remaining,
              textAlign: TextAlign.center,
              style: PixelText.body(size: 12, color: colors.textMid),
            ),
          ],
          if (contest.status == GiveawayStatus.verifying) ...[
            const SizedBox(height: 8),
            Text(
              'The results are under review. Positions remain provisional.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 13, color: colors.textDark),
            ),
          ],
          if (contest.status == GiveawayStatus.finalResult) ...[
            const SizedBox(height: 10),
            if (data.winner case final winner?) ...[
              Text(
                'WINNER: ${winner.displayName.toUpperCase()}',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 18, color: colors.textDark),
              ),
              if (winner.originalRank > 1)
                Text(
                  'Verified winner, originally ranked #${winner.originalRank}.',
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
            ] else
              Text(
                'NO WINNER',
                style: PixelText.title(size: 18, color: colors.textDark),
              ),
          ],
        ],
      ),
    );
  }

  static String _prizeLabel(GiveawayPrize prize) {
    final parts = <String>[];
    if (prize.cashMinor > 0) {
      final dollars = prize.cashMinor ~/ 100;
      final cents = prize.cashMinor % 100;
      parts.add(
        cents == 0
            ? 'US\$${_commas(dollars)}'
            : 'US\$${_commas(dollars)}.${cents.toString().padLeft(2, '0')}',
      );
    }
    if (prize.coins > 0) parts.add('${_commas(prize.coins)} COINS');
    return parts.join(' + ');
  }

  static String _commas(int value) {
    final digits = value.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) output.write(',');
      output.write(digits[index]);
    }
    return output.toString();
  }

  Widget _eligibility(GiveawayCurrent data, AppPalette colors) {
    final entry = data.entry;
    final statusText = switch (entry?.status) {
      GiveawayEntryStatus.eligible => 'YOU’RE ENTERED',
      GiveawayEntryStatus.underReview => 'UNDER_REVIEW',
      GiveawayEntryStatus.ineligible => 'INELIGIBLE',
      GiveawayEntryStatus.withdrawn => 'WITHDRAWN',
      _ => 'U.S. RESIDENTS 18+',
    };
    final canEnter =
        entry?.status == GiveawayEntryStatus.actionRequired &&
        data.contest.status == GiveawayStatus.active;
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ELIGIBILITY',
            style: PixelText.title(size: 16, color: colors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: PixelText.title(size: 15, color: colors.roofMid),
          ),
          const SizedBox(height: 6),
          Text(
            'Legal residents of the 50 United States or D.C., age ${data.contest.minimumAge}+. No purchase necessary.',
            style: PixelText.body(size: 13, color: colors.textDark),
          ),
          if (canEnter) ...[
            const SizedBox(height: 14),
            PillButton(
              label: 'ENTER CONTEST',
              fullWidth: true,
              onPressed: () => _showEntry(data),
            ),
          ],
        ],
      ),
    );
  }

  Widget _standing(GiveawayCurrent data, AppPalette colors) {
    final standing = data.standing!;
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR STANDING',
            style: PixelText.title(size: 16, color: colors.textDark),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(
                standing.provisionalRank == null
                    ? 'UNRANKED'
                    : '#${standing.provisionalRank}',
                colors,
              ),
              _badge('${standing.verifiedCount} VERIFIED', colors),
              if (standing.reviewableCount > 0)
                _badge('${standing.reviewableCount} UNDER REVIEW', colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderboard(
    GiveawayCurrent data,
    AppPalette colors, {
    bool global = false,
  }) {
    final standingRank = data.standing?.provisionalRank;
    final entry = data.entry;
    final userAlreadyListed =
        standingRank != null &&
        data.leaderboard.any((row) => row.rank == standingRank);
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LEADERBOARD',
            style: PixelText.title(size: 16, color: colors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            data.contest.status == GiveawayStatus.finalResult
                ? 'Final verified results'
                : 'Provisional—positions may change after fraud review',
            style: PixelText.body(size: 11, color: colors.textMid),
          ),
          const SizedBox(height: 10),
          if (data.leaderboard.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                global
                    ? 'No verified referrals yet. Share your invite to lead the trail.'
                    : 'No referrals have qualified yet. Share your invite to get started.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 13, color: colors.textMid),
              ),
            )
          else
            for (final row in data.leaderboard)
              _leaderRow(row.rank, row.displayName, row.completedCount, colors),
          if (!userAlreadyListed &&
              standingRank != null &&
              entry != null &&
              data.standing != null) ...[
            Divider(color: colors.parchmentBorder),
            _leaderRow(
              standingRank,
              entry.displayName ?? 'Entrant',
              data.standing!.verifiedCount,
              colors,
              isMe: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _leaderRow(
    int rank,
    String name,
    int count,
    AppPalette colors, {
    bool isMe = false,
  }) => Semantics(
    label:
        'Rank $rank, $name, $count completed referrals${isMe ? ', your standing' : ''}',
    child: Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? colors.pillGold.withValues(alpha: 0.35)
            : colors.parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.parchmentBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              '#$rank',
              style: PixelText.title(size: 14, color: colors.textDark),
            ),
          ),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: PixelText.body(size: 14, color: colors.textDark),
            ),
          ),
          Text(
            '$count',
            style: PixelText.title(size: 15, color: colors.textDark),
          ),
        ],
      ),
    ),
  );

  Widget _badge(String value, AppPalette colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: colors.pillGold,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: colors.pillGoldDark),
    ),
    child: Text(
      value,
      style: PixelText.title(size: 11, color: colors.textDark),
    ),
  );

  Widget _card(
    AppPalette colors, {
    required Widget child,
    Color? borderColor,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: borderColor ?? colors.roofDark.withValues(alpha: 0.55),
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

  Future<void> _share(GiveawayShare share) => shareReferral(
    context,
    code: share.code,
    url: share.url.toString(),
    referrerCoins: null,
    refereeCoins: null,
  );

  void _openRules(GiveawayContest contest) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GiveawayRulesScreen(contest: contest)),
    );
  }

  Widget _globalPreEntry(GiveawayCurrent data, AppPalette colors) {
    final contest = data.contest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_globalRulesController.hasClients) return;
      _onRulesScroll();
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _onRulesScroll();
              return false;
            },
            child: SingleChildScrollView(
              key: const Key('giveaway-global-rules-scroll'),
              controller: _globalRulesController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _globalPrizeHero(contest, colors),
                  const SizedBox(height: 18),
                  _sectionLabel('ROUTE TO THE PRIZE', colors),
                  const SizedBox(height: 10),
                  _trailRoute(colors),
                  const SizedBox(height: 20),
                  _sectionLabel('OFFICIAL RULES', colors),
                  const SizedBox(height: 10),
                  _card(
                    colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contest.eligibilitySummary,
                          style: PixelText.body(
                            size: 14,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Rules ${contest.rules.version}',
                          style: PixelText.body(
                            size: 11,
                            color: colors.textMid,
                          ),
                        ),
                        for (final section in contest.rules.sections) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: 28,
                            height: 3,
                            color: colors.pillGoldDark,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            section.heading.toUpperCase(),
                            style: PixelText.title(
                              size: 14,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            section.body,
                            style: PixelText.body(
                              size: 14,
                              color: colors.textDark,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Sponsored by ${contest.sponsorName}. Apple and Google are not sponsors, administrators, endorsers, or involved in this contest.',
                          style: PixelText.body(
                            size: 12,
                            color: colors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          label: _readRulesToEnd
              ? 'Official Rules read progress complete'
              : 'Official Rules read progress incomplete',
          child: LinearProgressIndicator(
            key: const Key('giveaway-rules-progress'),
            minHeight: 4,
            value: _rulesProgress,
            color: colors.pillGold,
            backgroundColor: colors.parchmentBorder,
          ),
        ),
        _globalEntryFooter(data, colors),
      ],
    );
  }

  double get _rulesProgress {
    if (_readRulesToEnd) return 1;
    if (!_globalRulesController.hasClients) return 0;
    final position = _globalRulesController.position;
    if (position.maxScrollExtent <= 0) return 1;
    return (position.pixels / position.maxScrollExtent).clamp(0, 1);
  }

  Widget _globalEntryFooter(GiveawayCurrent data, AppPalette colors) {
    final contest = data.contest;
    final missingName =
        _displayNameRequired ||
        (widget.authService.displayName?.trim().isEmpty ?? true) ||
        (data.entry?.displayName?.trim().isEmpty ?? true);
    final active = contest.status == GiveawayStatus.active;
    final ready =
        active &&
        !missingName &&
        _readRulesToEnd &&
        _rulesAccepted &&
        !_joining;
    final buttonLabel = missingName
        ? 'SET DISPLAY NAME TO JOIN'
        : _joining
        ? 'JOINING…'
        : 'JOIN CONTEST';

    return Container(
      key: const Key('giveaway-entry-footer'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: colors.parchment,
        border: Border(top: BorderSide(color: colors.woodDarker, width: 2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, -3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active && !missingName)
            Material(
              color: colors.parchment,
              child: CheckboxListTile(
                key: const Key('giveaway-global-rules-accepted'),
                value: _rulesAccepted,
                enabled: !_joining,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setState(() => _rulesAccepted = value == true),
                title: Text(
                  'I agree to the contest rules',
                  style: PixelText.body(size: 13, color: colors.textDark),
                ),
              ),
            ),
          if (_joinError case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: colors.error),
              ),
            ),
          if (!active)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                contest.status == GiveawayStatus.scheduled
                    ? 'JOINING OPENS ${_utcInstant(contest.startsAt)}'
                    : 'THIS CONTEST IS NO LONGER OPEN',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 12, color: colors.textDark),
              ),
            )
          else
            PillButton(
              label: buttonLabel,
              fullWidth: true,
              onPressed: missingName
                  ? _openDisplayNameRecovery
                  : ready
                  ? () => _joinGlobal(data)
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _joinGlobal(GiveawayCurrent data) async {
    if (_joining) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _joining = true;
      _joinError = null;
    });
    try {
      final raw = await _api.enterGlobalGiveaway(
        identityToken: token,
        slug: data.contest.slug,
        rulesVersion: data.contest.rules.version,
        rulesAccepted: true,
      );
      final entry = GiveawayEntry.tryParse(raw['entry']);
      if (entry == null ||
          entry.status != GiveawayEntryStatus.eligible ||
          entry.acceptedAt == null ||
          entry.country != null ||
          entry.region != null ||
          entry.rulesVersion != data.contest.rules.version) {
        throw const FormatException('Malformed global entry');
      }
      if (!mounted) return;
      setState(() {
        _data = GiveawayCurrent(
          contest: data.contest,
          leaderboard: data.leaderboard,
          entry: entry,
          standing: data.standing,
          share: data.share,
          winner: data.winner,
        );
        _joining = false;
        _joinError = null;
      });
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        if (error.code == 'DISPLAY_NAME_REQUIRED') {
          _displayNameRequired = true;
          _joinError = 'Set a Bara display name, then return to join.';
        } else if (error.code == 'RULES_CHANGED') {
          _joinError =
              'The rules changed. Refresh and read the latest version.';
        } else if (error.code == 'CONTEST_NOT_OPEN') {
          _joinError = 'This contest is not open for joining.';
        } else {
          _joinError = error.message;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = 'Couldn’t join. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _openDisplayNameRecovery() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DisplayNameScreen(authService: widget.authService),
      ),
    );
    if (!mounted) return;
    setState(() {
      _displayNameRequired = false;
      _joinError = null;
    });
    await _load();
  }

  Widget _globalPrizeHero(GiveawayContest contest, AppPalette colors) => _card(
    colors,
    borderColor: colors.coinDark,
    child: Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 5,
          children: [
            Icon(Icons.emoji_events_rounded, color: colors.coinDark, size: 25),
            Text(
              _prizeLabel(contest.prize),
              textAlign: TextAlign.center,
              style: PixelText.title(size: 24, color: colors.textDark),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          '${_shortDate(contest.startsAt)} — ${_shortDate(contest.endsAt)}',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 13, color: colors.textMid),
        ),
        if (_remaining(contest.endsAt) case final remaining?) ...[
          const SizedBox(height: 3),
          Text(
            remaining.toUpperCase(),
            style: PixelText.pill(size: 10, color: colors.roofMid),
          ),
        ],
      ],
    ),
  );

  Widget _trailRoute(AppPalette colors) {
    const steps = [
      ('Join the contest', 'Read these rules and agree.'),
      ('Share your invite', 'Send your unique Bara link.'),
      ('Your friend signs up', 'They must use your invite.'),
      (
        'They finish a qualifying race',
        'The race must include another real player during the contest window.',
      ),
      (
        'Most verified referrals wins',
        'Ties go to whoever reached the final count first.',
      ),
    ];
    return _card(
      colors,
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            _TrailStep(
              number: index + 1,
              title: steps[index].$1,
              detail: steps[index].$2,
              last: index == steps.length - 1,
              colors: colors,
            ),
        ],
      ),
    );
  }

  Widget _globalJoinedHub(GiveawayCurrent data, AppPalette colors) {
    final contest = data.contest;
    final standing = data.standing;
    final rank = standing?.provisionalRank;
    final active = contest.status == GiveawayStatus.active;
    return SingleChildScrollView(
      key: const Key('giveaway-content-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _globalPrizeHero(contest, colors),
          const SizedBox(height: 18),
          _sectionLabel('YOUR RUN', colors),
          const SizedBox(height: 10),
          _card(
            colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _RunStat(
                        value: '${standing?.verifiedCount ?? 0}',
                        label: 'VERIFIED REFERRALS',
                        colors: colors,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 52,
                      color: colors.parchmentBorder,
                    ),
                    Expanded(
                      child: _RunStat(
                        value: rank == null ? '—' : '#$rank',
                        label: 'PROVISIONAL RANK',
                        colors: colors,
                      ),
                    ),
                  ],
                ),
                if ((standing?.reviewableCount ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${standing?.reviewableCount ?? 0} referral${standing?.reviewableCount == 1 ? '' : 's'} under review',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 11, color: colors.textMid),
                  ),
                ],
                const SizedBox(height: 14),
                PillButton(
                  label: active ? 'SHARE YOUR INVITE' : 'CONTEST CLOSED',
                  icon: active ? Icons.ios_share_rounded : null,
                  fullWidth: true,
                  onPressed: active && data.share != null
                      ? () => _share(data.share!)
                      : null,
                ),
                const SizedBox(height: 7),
                Text(
                  active
                      ? 'Invite a friend, then help them finish a qualifying race.'
                      : contest.status == GiveawayStatus.verifying
                      ? 'Final checks are underway. Rankings remain provisional.'
                      : 'This contest has finished.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel('LEADERS', colors),
          const SizedBox(height: 10),
          _leaderboard(data, colors, global: true),
          const SizedBox(height: 14),
          _card(
            colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  key: const Key('giveaway-what-counts'),
                  onTap: () =>
                      setState(() => _whatCountsOpen = !_whatCountsOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'WHAT COUNTS?',
                            style: PixelText.title(
                              size: 15,
                              color: colors.textDark,
                            ),
                          ),
                        ),
                        Icon(
                          _whatCountsOpen
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: colors.textDark,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_whatCountsOpen) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Your friend uses your invite, signs up, and finishes a qualifying race with another real player after you join and before the contest ends. Bots, self-referrals, duplicates, and coordinated dummy accounts do not count.',
                    style: PixelText.body(size: 13, color: colors.textDark),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _openRules(contest),
            child: const Text('OFFICIAL RULES'),
          ),
          if (contest.socialLinks.isNotEmpty) ...[
            Text(
              'Optional — does not affect the contest.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 11, color: colors.textLight),
            ),
            for (final link in contest.socialLinks)
              TextButton.icon(
                onPressed: () =>
                    launchUrl(link.url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(link.label),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, AppPalette colors) => Row(
    children: [
      Container(width: 18, height: 3, color: colors.pillGold),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: PixelText.title(size: 15, color: colors.textLight),
        ),
      ),
    ],
  );

  static String _shortDate(DateTime value) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final local = value.toLocal();
    return '${months[local.month - 1]} ${local.day}';
  }

  Future<void> _showEntry(GiveawayCurrent data) async {
    final entered = await Navigator.of(context).push<GiveawayEntry>(
      MaterialPageRoute(
        builder: (_) => _GiveawayEntryPage(
          data: data,
          api: _api,
          token: widget.authService.authToken!,
        ),
      ),
    );
    if (entered != null && mounted) {
      setState(() {
        _data = GiveawayCurrent(
          contest: data.contest,
          leaderboard: data.leaderboard,
          entry: entered,
          standing: data.standing,
          share: data.share,
          winner: data.winner,
        );
      });
    }
  }

  static String _utcInstant(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day $hour:$minute UTC';
  }

  static String? _remaining(DateTime end) {
    final duration = end.difference(DateTime.now().toUtc());
    if (duration <= Duration.zero) return null;
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hours}h remaining';
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${minutes}m remaining';
    }
    return '${duration.inMinutes.clamp(1, 59)}m remaining';
  }
}

class _TrailStep extends StatelessWidget {
  const _TrailStep({
    required this.number,
    required this.title,
    required this.detail,
    required this.last,
    required this.colors,
  });

  final int number;
  final String title;
  final String detail;
  final bool last;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 34,
        child: Column(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.pillGold,
                shape: BoxShape.circle,
                border: Border.all(color: colors.woodDarker, width: 2),
              ),
              child: Text(
                '$number',
                style: PixelText.title(size: 12, color: colors.textDark),
              ),
            ),
            if (!last)
              Container(width: 3, height: 42, color: colors.pillGoldDark),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PixelText.title(size: 14, color: colors.textDark),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: PixelText.body(size: 12, color: colors.textMid),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _RunStat extends StatelessWidget {
  const _RunStat({
    required this.value,
    required this.label,
    required this.colors,
  });

  final String value;
  final String label;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: PixelText.title(size: 25, color: colors.textDark),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: PixelText.pill(size: 9, color: colors.textMid),
        ),
      ],
    ),
  );
}

class _GiveawayEntryPage extends StatelessWidget {
  const _GiveawayEntryPage({
    required this.data,
    required this.api,
    required this.token,
  });

  final GiveawayCurrent data;
  final BackendApiService api;
  final String token;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).parchment,
    appBar: AppBar(
      title: const Text('Contest entry'),
      backgroundColor: AppColors.of(context).parchment,
      foregroundColor: AppColors.of(context).textDark,
    ),
    body: SafeArea(
      child: _GiveawayEntrySheet(data: data, api: api, token: token),
    ),
  );
}

class _GiveawayEntrySheet extends StatefulWidget {
  const _GiveawayEntrySheet({
    required this.data,
    required this.api,
    required this.token,
  });
  final GiveawayCurrent data;
  final BackendApiService api;
  final String token;

  @override
  State<_GiveawayEntrySheet> createState() => _GiveawayEntrySheetState();
}

class _GiveawayEntrySheetState extends State<_GiveawayEntrySheet> {
  bool _age = false;
  bool _residency = false;
  bool _rules = false;
  bool _submitting = false;
  String? _region;
  String? _error;

  bool get _ready =>
      _age && _residency && _rules && _region != null && !_submitting;

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final raw = await widget.api.enterGiveaway(
        identityToken: widget.token,
        slug: widget.data.contest.slug,
        rulesVersion: widget.data.contest.rules.version,
        country: 'US',
        region: _region!,
        ageConfirmed: _age,
        residencyConfirmed: _residency,
        rulesAccepted: _rules,
      );
      final entry = GiveawayEntry.tryParse(raw['entry']);
      if (entry == null ||
          entry.status != GiveawayEntryStatus.eligible ||
          entry.acceptedAt == null ||
          entry.country != 'US' ||
          entry.region != _region ||
          entry.rulesVersion != widget.data.contest.rules.version) {
        throw const FormatException('Malformed entry');
      }
      if (mounted) Navigator.of(context).pop(entry);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.code == 'RULES_CHANGED'
            ? 'The rules changed. Close this form and review the latest version.'
            : error.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Couldn’t enter. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CONFIRM ENTRY',
              textAlign: TextAlign.center,
              style: PixelText.title(size: 21, color: colors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Your leaderboard name will be “${widget.data.entry?.displayName ?? ''}”.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 13, color: colors.textMid),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              key: const Key('giveaway-age-confirmed'),
              value: _age,
              onChanged: (value) => setState(() => _age = value == true),
              title: const Text('I confirm I am 18 or older.'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              key: const Key('giveaway-residency-confirmed'),
              value: _residency,
              onChanged: (value) => setState(() => _residency = value == true),
              title: const Text(
                'I am a legal resident of the 50 United States or D.C.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            DropdownButtonFormField<String>(
              key: const Key('giveaway-region-field'),
              initialValue: _region,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'State or D.C.'),
              items: widget.data.contest.eligibleRegions
                  .map(
                    (region) => DropdownMenuItem(
                      value: region,
                      child: Text(_regionName(region)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _region = value),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('giveaway-rules-accepted'),
              value: _rules,
              onChanged: (value) => setState(() => _rules = value == true),
              title: Text(
                'I accept Official Rules version ${widget.data.contest.rules.version}.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error),
                ),
              ),
            PillButton(
              label: _submitting ? 'ENTERING…' : 'CONFIRM ENTRY',
              fullWidth: true,
              onPressed: _ready ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _regionName(String code) =>
      const {
        'US-AL': 'Alabama',
        'US-AK': 'Alaska',
        'US-AZ': 'Arizona',
        'US-AR': 'Arkansas',
        'US-CA': 'California',
        'US-CO': 'Colorado',
        'US-CT': 'Connecticut',
        'US-DE': 'Delaware',
        'US-DC': 'District of Columbia',
        'US-FL': 'Florida',
        'US-GA': 'Georgia',
        'US-HI': 'Hawaii',
        'US-ID': 'Idaho',
        'US-IL': 'Illinois',
        'US-IN': 'Indiana',
        'US-IA': 'Iowa',
        'US-KS': 'Kansas',
        'US-KY': 'Kentucky',
        'US-LA': 'Louisiana',
        'US-ME': 'Maine',
        'US-MD': 'Maryland',
        'US-MA': 'Massachusetts',
        'US-MI': 'Michigan',
        'US-MN': 'Minnesota',
        'US-MS': 'Mississippi',
        'US-MO': 'Missouri',
        'US-MT': 'Montana',
        'US-NE': 'Nebraska',
        'US-NV': 'Nevada',
        'US-NH': 'New Hampshire',
        'US-NJ': 'New Jersey',
        'US-NM': 'New Mexico',
        'US-NY': 'New York',
        'US-NC': 'North Carolina',
        'US-ND': 'North Dakota',
        'US-OH': 'Ohio',
        'US-OK': 'Oklahoma',
        'US-OR': 'Oregon',
        'US-PA': 'Pennsylvania',
        'US-RI': 'Rhode Island',
        'US-SC': 'South Carolina',
        'US-SD': 'South Dakota',
        'US-TN': 'Tennessee',
        'US-TX': 'Texas',
        'US-UT': 'Utah',
        'US-VT': 'Vermont',
        'US-VA': 'Virginia',
        'US-WA': 'Washington',
        'US-WV': 'West Virginia',
        'US-WI': 'Wisconsin',
        'US-WY': 'Wyoming',
      }[code] ??
      code;
}
