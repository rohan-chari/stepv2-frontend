import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { automatic, light, dark }

typedef AppClock = DateTime Function();

/// Owns the user's appearance preference and the fixed 10 PM–7 AM US-Eastern
/// schedule (the same real-world moment for every user, whatever their device
/// time zone says).
/// This is deliberately device-only: theme selection never depends on the API.
class AppThemeController extends ChangeNotifier with WidgetsBindingObserver {
  AppThemeController({
    AppThemePreference preference = AppThemePreference.automatic,
    AppClock? clock,
  }) : _preference = preference,
       _clock = clock ?? DateTime.now,
       _resolvedMode = resolve(preference, (clock ?? DateTime.now)()) {
    WidgetsBinding.instance.addObserver(this);
    _scheduleBoundary();
  }

  static const preferenceKey = 'app_theme_preference';
  static const nightStartHour = 22;
  static const dayStartHour = 7;

  final AppClock _clock;
  AppThemePreference _preference;
  ThemeMode _resolvedMode;
  Timer? _boundaryTimer;

  AppThemePreference get preference => _preference;
  ThemeMode get resolvedMode => _resolvedMode;
  bool get isNight => _resolvedMode == ThemeMode.dark;

  static Future<AppThemePreference> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(preferenceKey);
    return AppThemePreference.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => AppThemePreference.automatic,
    );
  }

  /// The US-Eastern UTC offset at [instant] (which is read as a UTC instant).
  ///
  /// Hardcodes current US federal DST law (Energy Policy Act of 2005, in force
  /// since 2007): DST starts the 2nd Sunday in March at 07:00 UTC and ends the
  /// 1st Sunday in November at 06:00 UTC — two deliberately different UTC
  /// hours. If that law changes (e.g. a "permanent DST" act) this needs a new
  /// binary; accepted tradeoff versus bundling the IANA database for one
  /// fixed-rule zone, and it keeps theme selection device-only with no init
  /// step and no data-load failure mode.
  static Duration easternOffset(DateTime instant) {
    final utc = instant.toUtc();
    final dstStart = _nthSundayUtc(utc.year, DateTime.march, 2, 7);
    final dstEnd = _nthSundayUtc(utc.year, DateTime.november, 1, 6);
    final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
    return Duration(hours: isDst ? -4 : -5);
  }

  static DateTime _nthSundayUtc(int year, int month, int n, int hourUtc) {
    // DateTime.weekday is Monday=1 ... Sunday=7.
    final firstOfMonth = DateTime.utc(year, month, 1);
    final firstSunday = 1 + (7 - firstOfMonth.weekday) % 7;
    return DateTime.utc(year, month, firstSunday + 7 * (n - 1), hourUtc);
  }

  /// Eastern wall-clock hour (0-23) at the UTC instant [instant].
  static int easternHour(DateTime instant) {
    final utc = instant.toUtc();
    return utc.add(easternOffset(utc)).hour;
  }

  static ThemeMode resolve(AppThemePreference preference, DateTime now) {
    return switch (preference) {
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.automatic =>
        easternHour(now) >= nightStartHour || easternHour(now) < dayStartHour
            ? ThemeMode.dark
            : ThemeMode.light,
    };
  }

  /// The next 07:00 / 22:00 Eastern flip strictly after [instant], as UTC.
  @visibleForTesting
  static DateTime nextBoundaryUtc(DateTime instant) {
    final nowUtc = instant.toUtc();
    final easternNow = nowUtc.add(easternOffset(nowUtc));

    // Build an Eastern wall-clock time (carried in a UTC DateTime so the host
    // zone can never leak in) and convert it back to a real UTC instant using
    // the offset in force *at that candidate instant* — the candidate can sit
    // on the far side of a DST transition from `now`.
    DateTime candidate(int dayOffset, int hour) {
      final wall = DateTime.utc(
        easternNow.year,
        easternNow.month,
        easternNow.day + dayOffset,
        hour,
      );
      final firstGuess = wall.subtract(easternOffset(nowUtc));
      return wall.subtract(easternOffset(firstGuess));
    }

    final candidates = <DateTime>[
      candidate(0, dayStartHour),
      candidate(0, nightStartHour),
      candidate(1, dayStartHour),
      candidate(1, nightStartHour),
    ]..sort();
    return candidates.firstWhere(
      (value) => value.isAfter(nowUtc),
      orElse: () => candidates.last,
    );
  }

  Future<void> setPreference(AppThemePreference value) async {
    if (_preference == value) return;
    _preference = value;
    _recalculate();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, value.name);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recalculate();
  }

  void _recalculate() {
    final next = resolve(_preference, _clock());
    _resolvedMode = next;
    _scheduleBoundary();
    // A preference change can keep the same resolved brightness (for example,
    // Automatic -> Dark at night) but settings still needs to update its mark.
    notifyListeners();
  }

  void _scheduleBoundary() {
    _boundaryTimer?.cancel();
    if (_preference != AppThemePreference.automatic) return;
    final now = _clock().toUtc();
    final next = nextBoundaryUtc(now);
    _boundaryTimer = Timer(next.difference(now), _recalculate);
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'AppThemeScope is missing above this context.');
    return controller!;
  }

  static AppThemeController? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.notifier;
  }
}
