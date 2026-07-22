import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { automatic, light, dark }

typedef AppClock = DateTime Function();

/// Owns the user's appearance preference and the local 7 PM–7 AM schedule.
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
  static const nightStartHour = 19;
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

  static ThemeMode resolve(AppThemePreference preference, DateTime localNow) {
    return switch (preference) {
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.automatic =>
        localNow.hour >= nightStartHour || localNow.hour < dayStartHour
            ? ThemeMode.dark
            : ThemeMode.light,
    };
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
    final now = _clock();
    final todayAtSeven = DateTime(now.year, now.month, now.day, dayStartHour);
    final todayAtNineteen = DateTime(
      now.year,
      now.month,
      now.day,
      nightStartHour,
    );
    final next = now.isBefore(todayAtSeven)
        ? todayAtSeven
        : now.isBefore(todayAtNineteen)
        ? todayAtNineteen
        : DateTime(now.year, now.month, now.day + 1, dayStartHour);
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
