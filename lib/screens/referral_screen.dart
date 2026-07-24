import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/health_service.dart';
import '../styles.dart';
import '../widgets/app_refresh_indicator.dart';
import '../utils/at_name.dart';
import '../utils/share_helper.dart';
import 'referral_rules_screen.dart';
import '../widgets/app_avatar.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';

/// Invite-friends screen: shows the user's referral link + a share CTA, a
/// dashboard of who they've referred (with stage badges + coins earned), and a
/// low-key "have an invite code?" entry for a freshly-installed referee who
/// wasn't auto-attributed (deferred to the redeem endpoint, which only credits
/// before their first race).
///
/// Every backend field is read defensively — an older backend that 404s the
/// referral endpoints leaves the page in a friendly error state rather than
/// crashing (CLAUDE.md: never assume the backend matches this build).
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({
    super.key,
    required this.authService,
    this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _api;

  bool _loading = true;
  bool _error = false;
  String? _code;
  String? _url;
  int _referredCount = 0;
  int _completedCount = 0;
  int _coinsEarned = 0;
  List<Map<String, dynamic>> _friends = const [];

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final data = await _api.fetchReferralStatus(identityToken: token);
      if (!mounted) return;
      setState(() {
        _code = data['code'] as String?;
        _url = data['url'] as String?;
        _referredCount = (data['referredCount'] as num?)?.toInt() ?? 0;
        _completedCount = (data['completedCount'] as num?)?.toInt() ?? 0;
        _coinsEarned = (data['coinsEarned'] as num?)?.toInt() ?? 0;
        final friends = data['friends'];
        _friends = friends is List
            ? friends
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _share() async {
    final url = _url;
    final code = _code;
    if (url == null || code == null) return;
    await shareReferral(context, code: code, url: url);
  }

  Future<void> _enterCode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _EnterCodeSheet(),
    );
    if (code == null || code.isEmpty) return;

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    String message;
    var success = false;
    try {
      final result = await _api.redeemReferralCode(
        identityToken: token,
        code: code,
      );
      success = result['attributed'] == true;
      message = success
          ? "You're in! Finish your first race to earn coins."
          : _reasonMessage(result['reason'] as String?);
    } catch (_) {
      message = "Couldn't apply that code. Please try again.";
    }
    if (!mounted) return;
    if (success) {
      showInfoToast(context, message);
    } else {
      showErrorToast(context, message);
    }
  }

  String _reasonMessage(String? reason) {
    switch (reason) {
      case 'self_referral':
        return "You can't use your own invite code.";
      case 'already_attributed':
        return 'You already have an invite credited.';
      case 'already_raced':
        return 'Invite codes only work before your first race.';
      case 'unknown_code':
      case 'invalid_code':
        return "That code doesn't look right.";
      default:
        return "Couldn't apply that code.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.of(context).roofLight,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(
                  child: AppRefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      children: _buildBody(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofDark, width: 1),
        ),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.arrow_back,
                    color: AppColors.of(context).textLight,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'INVITE FRIENDS',
                style: PixelText.title(
                  size: 28,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'Share your link. When a friend finishes their first race, '
                'you BOTH earn coins.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_loading) {
      return [
        Container(
          decoration: _referralCardDecoration(),
          padding: const EdgeInsets.all(12),
          child: const ListSkeleton(itemCount: 4),
        ),
      ];
    }
    if (_error) {
      return [
        const SizedBox(height: 40),
        Text(
          "Couldn't load your invites",
          textAlign: TextAlign.center,
          style: PixelText.title(
            size: 18,
            color: AppColors.of(context).textLight,
          ).copyWith(shadows: _textShadows),
        ),
        const SizedBox(height: 8),
        Text(
          'Check your connection and try again.',
          textAlign: TextAlign.center,
          style: PixelText.body(
            size: 14,
            color: AppColors.of(context).textLight.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: PillButton(
            label: 'RETRY',
            variant: PillButtonVariant.secondary,
            onPressed: _load,
          ),
        ),
      ];
    }

    return [
      StaggerIn(index: 0, child: _buildStatsCard()),
      const SizedBox(height: 16),
      StaggerIn(
        index: 1,
        child: PulseGlow(
          child: PillButton(
            label: 'SHARE YOUR INVITE',
            icon: Icons.ios_share_rounded,
            // Gold — the primary green pill vanishes on the green checker.
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            onPressed: (_code != null && _url != null) ? _share : null,
          ),
        ),
      ),
      if (_code != null) ...[
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Your code: $_code',
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textLight.withValues(alpha: 0.92),
            ).copyWith(shadows: _textShadows),
          ),
        ),
      ],
      const SizedBox(height: 20),
      StaggerIn(
        index: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader('YOUR INVITES'),
            const SizedBox(height: 8),
            Container(
              decoration: _referralCardDecoration(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _friends.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        "No invites yet — share your link to get started.",
                        textAlign: TextAlign.center,
                        style: PixelText.body(
                          size: 14,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    )
                  : Column(children: _friends.map(_buildFriendRow).toList()),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Center(
        child: TextButton(
          onPressed: _enterCode,
          child: Text(
            'Have an invite code?',
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textLight.withValues(alpha: 0.92),
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
      Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReferralRulesScreen()),
            );
          },
          child: Text(
            'Program rules',
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textLight.withValues(alpha: 0.75),
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
    ];
  }

  /// Parchment game-piece card — same language as the redesigned tabs.
  BoxDecoration _referralCardDecoration() {
    return BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: _referralCardDecoration(),
      child: Row(
        children: [
          Expanded(child: _buildStat('$_referredCount', 'Invited')),
          _divider(),
          Expanded(child: _buildStat('$_completedCount', 'Completed')),
          _divider(),
          Expanded(child: _buildCoinStat()),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 36,
    color: AppColors.of(context).parchmentBorder.withValues(alpha: 0.6),
  );

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: PixelText.title(
            size: 22,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
      ],
    );
  }

  Widget _buildCoinStat() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SpinningCoin(size: 18),
            const SizedBox(width: 4),
            Text(
              '$_coinsEarned',
              style: PixelText.title(
                size: 22,
                color: AppColors.of(context).textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Earned',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.of(context).pillGold,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppColors.of(context).pillGoldDark),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: PixelText.title(
            size: 16,
            color: AppColors.of(context).textLight,
          ).copyWith(shadows: _textShadows),
        ),
      ],
    );
  }

  Widget _buildFriendRow(Map<String, dynamic> friend) {
    final name = friend['displayName'] as String?;
    final photo = friend['profilePhotoUrl'] as String?;
    final completed = friend['stage'] == 'completed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AppAvatar(name: name ?? 'Friend', imageUrl: photo, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name != null ? atName(name) : 'A friend',
              style: PixelText.body(
                size: 15,
                color: AppColors.of(context).textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _StageBadge(completed: completed),
        ],
      ),
    );
  }
}

/// Challenge-framed share copy: a personal taunt with today's live step count
/// beats a generic referral blurb for open rates. Embeds both the raw code and
/// the link so a friend who lands on the App Store can still type the code
/// manually if the deferred match misses. Public so other entry points (home
/// empty-state) reuse it.
Future<void> shareReferral(
  BuildContext context, {
  required String code,
  required String url,
}) async {
  // Best-effort live step count for the taunt; ~2s budget, silent fallback to
  // the countless copy (share must never hang or fail on a Health hiccup).
  int? steps;
  try {
    final data = await HealthService().getStepsToday().timeout(
      const Duration(seconds: 2),
    );
    steps = data.steps;
  } catch (_) {}
  if (!context.mounted) return;

  final text = steps != null && steps > 0
      ? "I'm at ${formatStepsWithCommas(steps)} steps today — think you can "
            "beat me? Race me on Bara with code $code and we'll both earn "
            "coins when you finish your first race: $url"
      : "Bet you can't out-step me. Race me on Bara with code $code and "
            "we'll both earn coins when you finish your first race: $url";
  return shareText(context, text);
}

/// 8432 -> "8,432". Local helper (shared with the race-detail share copy).
String formatStepsWithCommas(int steps) {
  final digits = steps.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final label = completed ? 'COMPLETED' : 'JOINED';
    final color = completed
        ? AppColors.of(context).pillGreenDark
        : AppColors.of(context).textMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            (completed
                    ? AppColors.of(context).pillGreen
                    : AppColors.of(context).parchmentDark)
                .withValues(alpha: completed ? 0.25 : 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: PixelText.body(size: 11, color: color)),
    );
  }
}

class _EnterCodeSheet extends StatefulWidget {
  const _EnterCodeSheet();

  @override
  State<_EnterCodeSheet> createState() => _EnterCodeSheetState();
}

class _EnterCodeSheetState extends State<_EnterCodeSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ENTER INVITE CODE',
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'BARA-XXXX',
              filled: true,
              fillColor: AppColors.of(context).parchmentLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.of(context).parchmentBorder,
                ),
              ),
            ),
            style: PixelText.body(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 16),
          PillButton(
            label: 'APPLY',
            variant: PillButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          ),
        ],
      ),
    );
  }
}
