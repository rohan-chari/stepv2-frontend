import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/share_helper.dart';
import 'referral_rules_screen.dart';
import '../widgets/app_avatar.dart';
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
      backgroundColor: AppColors.parchment,
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
      backgroundColor: AppColors.parchment,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.roofLight,
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
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.accent,
                    backgroundColor: AppColors.parchment,
                    child: ColoredBox(
                      color: AppColors.parchment,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                        children: _buildBody(),
                      ),
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
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
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
                  icon: const Icon(Icons.arrow_back, color: AppColors.parchment),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'INVITE FRIENDS',
                style: PixelText.title(
                  size: 28,
                  color: AppColors.parchment,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'Share your link. When a friend finishes their first race, '
                'you BOTH earn coins.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.parchment.withValues(alpha: 0.92),
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
      return const [
        Padding(padding: EdgeInsets.all(12), child: ListSkeleton(itemCount: 4)),
      ];
    }
    if (_error) {
      return [
        const SizedBox(height: 40),
        Text(
          "Couldn't load your invites",
          textAlign: TextAlign.center,
          style: PixelText.title(size: 18, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Check your connection and try again.',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 14, color: AppColors.textMid),
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
      _buildStatsCard(),
      const SizedBox(height: 16),
      PillButton(
        label: 'SHARE YOUR INVITE',
        icon: Icons.ios_share_rounded,
        variant: PillButtonVariant.primary,
        fullWidth: true,
        onPressed: (_code != null && _url != null) ? _share : null,
      ),
      if (_code != null) ...[
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Your code: $_code',
            style: PixelText.body(size: 14, color: AppColors.textMid),
          ),
        ),
      ],
      const SizedBox(height: 24),
      _buildSectionHeader('YOUR INVITES'),
      const SizedBox(height: 8),
      if (_friends.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            "No invites yet — share your link to get started.",
            textAlign: TextAlign.center,
            style: PixelText.body(size: 14, color: AppColors.textMid),
          ),
        )
      else
        ..._friends.map(_buildFriendRow),
      const SizedBox(height: 24),
      Center(
        child: TextButton(
          onPressed: _enterCode,
          child: Text(
            'Have an invite code?',
            style: PixelText.body(
              size: 14,
              color: AppColors.textMid,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
      Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ReferralRulesScreen(),
              ),
            );
          },
          child: Text(
            'Program rules',
            style: PixelText.body(
              size: 13,
              color: AppColors.textMid.withValues(alpha: 0.8),
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
    ];
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStat('$_referredCount', 'Invited'),
          ),
          _divider(),
          Expanded(
            child: _buildStat('$_completedCount', 'Completed'),
          ),
          _divider(),
          Expanded(child: _buildCoinStat()),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 36,
    color: AppColors.parchmentBorder.withValues(alpha: 0.6),
  );

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: PixelText.title(size: 22, color: AppColors.textDark)),
        const SizedBox(height: 4),
        Text(label, style: PixelText.body(size: 12, color: AppColors.textMid)),
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
              style: PixelText.title(size: 22, color: AppColors.textDark),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Earned', style: PixelText.body(size: 12, color: AppColors.textMid)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: PixelText.title(size: 16, color: AppColors.textDark),
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
              style: PixelText.body(size: 15, color: AppColors.textDark),
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

/// Benefit-framed share copy. Embeds both the raw code and the link so a friend
/// who lands on the App Store can still type the code manually if the deferred
/// match misses. Public so other entry points (home empty-state) reuse it.
Future<void> shareReferral(
  BuildContext context, {
  required String code,
  required String url,
}) {
  final text =
      "I'm racing on Bara — bet you can't out-step me. Use my code $code "
      "and we'll both earn coins when you finish your first race: $url";
  return shareText(context, text);
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final label = completed ? 'COMPLETED' : 'JOINED';
    final color = completed ? AppColors.pillGreenDark : AppColors.textMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (completed ? AppColors.pillGreen : AppColors.parchmentDark)
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
            style: PixelText.title(size: 16, color: AppColors.textDark),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'BARA-XXXX',
              filled: true,
              fillColor: AppColors.parchmentLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.parchmentBorder),
              ),
            ),
            style: PixelText.body(size: 16, color: AppColors.textDark),
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
