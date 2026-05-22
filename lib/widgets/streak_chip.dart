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

/// Full-width daily-reward button shown inside the home hero. Fetches its own
/// claim status, pulses gently while unclaimed, and opens [DailyRewardScreen]
/// on tap. Public [refresh] lets the parent (pull-to-refresh) re-sync.
class StreakChip extends StatefulWidget {
  const StreakChip({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

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
    _refresh();
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
    } else {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(height: 48);
    }
    return PillButton(
      label: _unclaimed ? 'CLAIM YOUR DAILY REWARD' : 'DAILY REWARD CLAIMED',
      icon: _unclaimed
          ? Icons.card_giftcard_rounded
          : Icons.check_box_rounded,
      variant: PillButtonVariant.secondary,
      fullWidth: true,
      onPressed: _open,
    );
  }
}
