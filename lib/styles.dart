import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  // === Pixel Art Hiking Trail Palette ===

  // Wood (posts, board frame)
  static const woodLight = Color(0xFFD4A574);
  static const woodMid = Color(0xFFB8834A);
  static const woodDark = Color(0xFF8B5E34);
  static const woodDarker = Color(0xFF6B4423);
  static const woodShadow = Color(0xFF4A2F17);
  static const woodHighlight = Color(0xFFE8C49A);
  static const woodGrain = Color(0xFFA07040);

  // Parchment (board inner surface)
  static const parchment = Color(0xFFF5E6C8);
  static const parchmentLight = Color(0xFFFAF0DC);
  static const parchmentDark = Color(0xFFE0D0B0);
  static const parchmentBorder = Color(0xFFC0A878);

  // Roof (corrugated green metal)
  static const roofLight = Color(0xFF7A9E68);
  static const roofMid = Color(0xFF5A7E48);
  static const roofDark = Color(0xFF3D5830);
  static const roofRidge = Color(0xFF8BAF78);
  static const roofEdge = Color(0xFF2D4220);

  // Pixel sky bands (stepped gradient)
  static const skyBand1 = Color(0xFF4A7FB5);
  static const skyBand2 = Color(0xFF5B90C2);
  static const skyBand3 = Color(0xFF6FA4D0);
  static const skyBand4 = Color(0xFF82B8DE);
  static const skyBand5 = Color(0xFF97CCE8);
  static const skyBand6 = Color(0xFFADD8EE);
  static const skyBand7 = Color(0xFFC0E4F4);

  // Pixel nature – grass & dirt
  static const grassBright = Color(0xFF5DBE4D);
  static const grassMid = Color(0xFF3DA83D);
  static const grassDark = Color(0xFF2D8830);
  static const dirtLight = Color(0xFFA07850);
  static const dirtMid = Color(0xFF886840);
  static const dirtDark = Color(0xFF685030);

  // Pine trees
  static const pineLight = Color(0xFF4A8848);
  static const pineMid = Color(0xFF366A34);
  static const pineDark = Color(0xFF254D24);
  static const pineTrunk = Color(0xFF6B4423);

  // Clouds
  static const cloudWhite = Color(0xFFF0F4F8);
  static const cloudShadow = Color(0xFFD0DEE8);

  // Sun
  static const sunYellow = Color(0xFFFFE040);
  static const sunOrange = Color(0xFFFFB830);
  static const sunGlow = Color(0x30FFE040);

  // Pin tacks / nails
  static const pinMetal = Color(0xFF8C8C8C);
  static const pinHighlight = Color(0xFFBBBBBB);
  static const pinShadow = Color(0xFF555555);

  // Text
  static const textDark = Color(0xFF3B2816);
  static const textMid = Color(0xFF6B5030);
  static const textLight = Color(0xFFF5E6C8);
  static const textAccent = Color(0xFFD4691E);

  // Button (wooden plaque)
  static const buttonFace = Color(0xFFCB9860);
  static const buttonLight = Color(0xFFDEB47A);
  static const buttonDark = Color(0xFF8B5E34);
  static const buttonShadow = Color(0xFF5A3820);
  static const buttonText = Color(0xFF3B2816);

  // Accent
  static const accent = Color(0xFFD4691E);
  static const accentLight = Color(0xFFE8944A);

  // Error
  static const error = Color(0xFFE05040);
  static const errorLight = Color(0xFFFF8A80);

  // Medals
  static const medalGold = Color(0xFFFFD700);
  static const medalSilver = Color(0xFFC0C0C0);
  static const medalBronze = Color(0xFFCD7F32);

  // Feed event tints
  static const feedAttack = Color(0xFFE05040);
  static const feedShield = Color(0xFF4A90D9);
  static const feedGold = Color(0xFFD4A017);
  static const feedBoost = Color(0xFF58CC02);

  // Firefly
  static const fireflyGlow = Color(0xFFFFE87C);

  // Coin (rich gold)
  static const coinLight = Color(0xFFE8C850);
  static const coinMid = Color(0xFFCDA434);
  static const coinDark = Color(0xFFB8860B);
  static const coinEdge = Color(0xFF8B6914);

  // Pill button palette (3 colors)
  // Primary – green
  static const pillGreen = Color(0xFF58CC02);
  static const pillGreenDark = Color(0xFF46A302);
  static const pillGreenShadow = Color(0xFF3A8A01);
  // Secondary – arcade gold
  static const pillGold = Color(0xFFF5C842);
  static const pillGoldDark = Color(0xFFD4991E);
  static const pillGoldShadow = Color(0xFFB8860B);
  // Accent – warm terracotta
  static const pillTerra = Color(0xFFD4573B);
  static const pillTerraDark = Color(0xFFA8442F);
  static const pillTerraShadow = Color(0xFF7D3322);
}

/// Game-themed text styles — bold and clean, not arcade-pixel.
abstract final class PixelText {
  static TextStyle title({double size = 30, Color color = AppColors.textDark}) {
    return GoogleFonts.russoOne(
      fontSize: size,
      color: color,
      height: 1.3,
    );
  }

  static TextStyle body({double size = 17.5, Color color = AppColors.textDark}) {
    return GoogleFonts.chakraPetch(
      fontSize: size,
      color: color,
      height: 1.5,
    );
  }

  static TextStyle number({double size = 45, Color color = AppColors.textAccent}) {
    return GoogleFonts.russoOne(
      fontSize: size,
      color: color,
      height: 1.2,
    );
  }

  static TextStyle button({double size = 20, Color color = AppColors.buttonText}) {
    return GoogleFonts.russoOne(
      fontSize: size,
      color: color,
      letterSpacing: 2,
    );
  }

  static TextStyle pill({double size = 19, Color color = Colors.white}) {
    return GoogleFonts.russoOne(
      fontSize: size,
      color: color,
      letterSpacing: 1.5,
    );
  }
}
