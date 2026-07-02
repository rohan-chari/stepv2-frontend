import 'package:flutter/material.dart';

import '../screens/daily_reward_screen.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import 'pill_button.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Full-width daily-reward button shown inside the home hero. Fed by the home
/// race-card batch via [initialData] (so it renders with the rest of the
/// page); self-fetches the daily-reward status only as a fallback for old
/// backends. Pulses gently while unclaimed and opens [DailyRewardScreen] on
/// tap. Public [refresh] lets the parent (pull-to-refresh) re-sync.
class StreakChip extends StatefulWidget {
  const StreakChip({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.compact = false,
    this.initialData,
    this.awaitingBatch = false,
    this.onClaimedToday,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final bool compact;

  /// Daily-reward payload from the home race-card batch (`dailyReward`:
  /// `{claimedToday, localDate}`). When present and fresh, no extra request
  /// is made — the button renders in the same frame as the rest of home.
  final Map<String, dynamic>? initialData;

  /// True while the home batch is still in flight. Holds off the fallback
  /// self-fetch; it runs only if the batch lands without the field (old
  /// backend) or fails.
  final bool awaitingBatch;

  /// Called when the user claims today's reward, so the parent can patch its
  /// cached batch payload and a later remount doesn't show a stale CLAIM.
  final VoidCallback? onClaimedToday;

  @override
  State<StreakChip> createState() => StreakChipState();
}

class StreakChipState extends State<StreakChip> with WidgetsBindingObserver {
  Future<void> refresh() => _refresh();

  bool _unclaimed = false;
  bool _loaded = false;
  String _lastFetchedDate = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consumeBatchOrFetch();
  }

  @override
  void didUpdateWidget(covariant StreakChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Batch landed (or its payload changed): consume it, or fall back to the
    // standalone fetch when the batch came back without the field.
    if (!identical(oldWidget.initialData, widget.initialData) ||
        (oldWidget.awaitingBatch && !widget.awaitingBatch)) {
      _consumeBatchOrFetch();
    }
  }

  void _consumeBatchOrFetch() {
    final data = widget.initialData;
    final today = _todayLocalDate();
    // Only trust a batch payload computed for today's local date — a cached
    // batch from before midnight would resurrect yesterday's claim state.
    if (data != null && data['localDate'] == today) {
      setState(() {
        _unclaimed = data['claimedToday'] != true;
        _loaded = true;
        _lastFetchedDate = today;
      });
    } else if (!widget.awaitingBatch) {
      // Old backend (no embedded dailyReward), stale batch, or batch failure:
      // standalone fetch, same as before the batching change.
      _refresh();
    }
    // else: batch still in flight — didUpdateWidget consumes it when it lands.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastFetchedDate != _todayLocalDate()) {
        _refresh();
      }
    }
  }

  Future<void> _refresh() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final localDate = _todayLocalDate();
    try {
      final res = await widget.backendApiService.fetchDailyRewardStatus(
        identityToken: token,
        localDate: localDate,
      );
      if (!mounted) return;
      setState(() {
        _unclaimed = res['claimedToday'] != true;
        _loaded = true;
        _lastFetchedDate = localDate;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _open() async {
    final claimed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => DailyRewardScreen(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    if (claimed == true && mounted) {
      setState(() => _unclaimed = false);
      widget.onClaimedToday?.call();
    } else {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(height: 48);
    }
    final label = _unclaimed ? 'CLAIM' : 'CLAIMED';
    return PillButton(
      label: label,
      icon: _unclaimed ? Icons.card_giftcard_rounded : Icons.check_box_rounded,
      variant: PillButtonVariant.secondary,
      fullWidth: true,
      onPressed: _open,
    );
  }
}
