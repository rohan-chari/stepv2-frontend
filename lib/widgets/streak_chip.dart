import 'package:flutter/material.dart';

import '../screens/daily_reward_screen.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Compact streak indicator with a flame icon and the current streak day count.
/// Lives in the home hero (next to the coin badge). Pulses gently when today's
/// reward has not been claimed yet. Tapping opens [DailyRewardScreen].
class StreakChip extends StatefulWidget {
  const StreakChip({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  @override
  State<StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<StreakChip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _unclaimed = false;
  int _currentDay = 0;
  bool _loaded = false;
  String _lastFetchedDate = '';

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
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
        _currentDay = (res['currentDay'] as num?)?.toInt() ?? 0;
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
      return const SizedBox(width: 60, height: 30);
    }

    final displayDay = _currentDay > 0 ? _currentDay : 1;
    final chip = GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _unclaimed
              ? const Color(0xFFFF7A2E).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _unclaimed
                ? const Color(0xFFFFB37A)
                : Colors.white.withValues(alpha: 0.35),
            width: 1.25,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🔥',
              style: TextStyle(
                fontSize: 14,
                color: _unclaimed
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$displayDay',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(
                  alpha: _unclaimed ? 1.0 : 0.85,
                ),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );

    if (!_unclaimed) return chip;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final scale = 1.0 + (_pulse.value * 0.06);
        return Transform.scale(scale: scale, child: child);
      },
      child: chip,
    );
  }
}
