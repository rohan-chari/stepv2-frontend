import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary accent — warm amber/orange for step counts, icons, highlights
  static const accent = Color(0xFFFF8C42);
  static const accentLight = Color(0xFFFFAB70);
  static const accentDark = Color(0xFFE06D20);

  // Gold / 3D button palette
  static const gold = Color(0xFFF5C842);
  static const goldMid = Color(0xFFEBB030);
  static const goldDark = Color(0xFFD4991E);
  static const goldBorder = Color(0xFFB8860B);
  static const goldShadow = Color(0xFF8B6508);
  static const goldText = Color(0xFF7A5A00);
  static const goldHighlight = Color(0xFFFFE082);

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gold, goldMid, goldDark],
  );

  // Sky
  static const skyTop = Color(0xFF87CEEB);
  static const skyMid = Color(0xFFB0E0F0);
  static const skyBottom = Color(0xFFD4F1F9);

  static const skyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [skyTop, skyMid, skyBottom],
  );

  // Earth / ground
  static const earthLight = Color(0xFF8D6E4C);
  static const earthMid = Color(0xFF6D4C2A);
  static const earthDark = Color(0xFF5D4037);

  // Grass
  static const grassLight = Color(0xFF66BB6A);
  static const grassMid = Color(0xFF43A047);
  static const grassDark = Color(0xFF2E7D32);
  static const grassHighlight = Color(0xFFA5D6A7);
  static const grassTuft = Color(0xFF388E3C);

  // Text / UI
  static const titleShadow = Color(0xFF1565C0);
  static const error = Color(0xFFFF8A80);
}
