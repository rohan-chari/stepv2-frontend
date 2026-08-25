import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';
import '../models/giveaway.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
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
  static final Map<String, GiveawayContest> _immutableRulesCache = {};

  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();
  GiveawayCurrent? _data;
  GiveawayContest? _cachedRules;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      _immutableRulesCache['${parsed.contest.slug}:${parsed.contest.rules.sha256}'] =
          parsed.contest;
      if (!mounted) return;
      setState(() {
        _data = parsed;
        _cachedRules = parsed.contest;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      GiveawayContest? cached;
      for (final entry in _immutableRulesCache.entries) {
        if (entry.key.startsWith('${widget.slug}:')) cached = entry.value;
      }
      setState(() {
        _data = null; // Never retain potentially stale ranking.
        _cachedRules = cached;
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
                'REFERRAL CONTEST',
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
            r'US$50 + 5,000 COINS',
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

  Widget _leaderboard(GiveawayCurrent data, AppPalette colors) {
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
                'No referrals have qualified yet. Share your invite to get started.',
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
      MaterialPageRoute(
        builder: (_) => GiveawayRulesScreen(
          title: contest.title,
          rules: contest.rules,
          minimumAge: contest.minimumAge,
          governingTimeZone: contest.governingTimeZone,
          startsAt: contest.startsAt,
          endsAt: contest.endsAt,
          sponsorLegalName: contest.sponsorLegalName,
          sponsorMailingAddress: contest.sponsorMailingAddress,
        ),
      ),
    );
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
