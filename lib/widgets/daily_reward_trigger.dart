import 'package:flutter/material.dart';

import '../screens/daily_reward_screen.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import 'daily_reward_button.dart';
import 'loading_skeleton.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Stateful wrapper around [DailyRewardButton] that fetches its own status,
/// triggers the modal, and refreshes after a claim.
class DailyRewardTrigger extends StatefulWidget {
  const DailyRewardTrigger({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  @override
  State<DailyRewardTrigger> createState() => _DailyRewardTriggerState();
}

class _DailyRewardTriggerState extends State<DailyRewardTrigger>
    with WidgetsBindingObserver {
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
      // Catch midnight rollover or returning users.
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
      // Silent: fall back to the non-pulsing button if the status check fails.
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
      return const LoadingSkeleton(
        child: SkeletonBox(width: double.infinity, height: 62, radius: 8),
      );
    }
    return DailyRewardButton(unclaimed: _unclaimed, onPressed: _open);
  }
}
