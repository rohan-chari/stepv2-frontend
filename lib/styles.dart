import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  // === Arcade UI palette ===

  // Legacy names are kept so older screens inherit the new visual system.
  static const woodLight = Color(0xFFF8F2E7);
  static const woodMid = Color(0xFF4F8A6A);
  static const woodDark = Color(0xFF213128);
  static const woodDarker = Color(0xFF17231C);
  static const woodShadow = Color(0xFF213128);
  static const woodHighlight = Color(0xFFFFFFFF);
  static const woodGrain = Color(0xFFD0C5B4);

  // Main surfaces
  static const parchment = Color(0xFFFFFBF5);
  static const parchmentLight = Color(0xFFF8F2E7);
  static const parchmentDark = Color(0xFFF3EBDD);
  static const parchmentBorder = Color(0xFFD0C5B4);

  // Primary green
  static const roofLight = Color(0xFF4F8A6A);
  static const roofMid = Color(0xFF2E5D47);
  static const roofDark = Color(0xFF213128);
  static const roofRidge = Color(0xFF77A98B);
  static const roofEdge = Color(0xFF17231C);

  // Pixel sky bands (stepped gradient)
  static const skyBand1 = Color(0xFF1E9AE8);
  static const skyBand2 = Color(0xFF25A7ED);
  static const skyBand3 = Color(0xFF35B5F0);
  static const skyBand4 = Color(0xFF53C3F2);
  static const skyBand5 = Color(0xFF73CEF2);
  static const skyBand6 = Color(0xFFA5DEF0);
  static const skyBand7 = Color(0xFFDDF2F6);

  // Pixel nature – grass & dirt
  static const grassBright = Color(0xFF63C55B);
  static const grassMid = Color(0xFF2FA84A);
  static const grassDark = Color(0xFF23783D);
  static const dirtLight = Color(0xFFC68A4F);
  static const dirtMid = Color(0xFF9F693A);
  static const dirtDark = Color(0xFF6E4428);

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
  static const textDark = Color(0xFF213128);
  static const textMid = Color(0xFF66796F);
  static const textLight = Color(0xFFFFFBF5);
  static const textAccent = Color(0xFF2E5D47);

  // Buttons
  static const buttonFace = Color(0xFF4F8A6A);
  static const buttonLight = Color(0xFF77A98B);
  static const buttonDark = Color(0xFF213128);
  static const buttonShadow = Color(0xFF17231C);
  static const buttonText = Color(0xFFFFFBF5);

  // Accent
  static const accent = Color(0xFF2E5D47);
  static const accentLight = Color(0xFF4F8A6A);

  // Error
  static const error = Color(0xFFB8604C);
  static const errorLight = Color(0xFFD69A88);

  // Medals
  static const medalGold = Color(0xFFFFD700);
  static const medalSilver = Color(0xFFC0C0C0);
  static const medalBronze = Color(0xFFCD7F32);

  // Feed event tints
  static const feedAttack = error;
  static const feedShield = Color(0xFF4A90D9);
  static const feedGold = Color(0xFFC49A48);
  static const feedBoost = roofLight;

  // Firefly
  static const fireflyGlow = Color(0xFFFFE87C);

  // Coin (rich gold)
  static const coinLight = Color(0xFFE8C850);
  static const coinMid = Color(0xFFCDA434);
  static const coinDark = Color(0xFFB8860B);
  static const coinEdge = Color(0xFF8B6914);

  // Deep "game felt" panel surfaces (home below-the-fold; reusable by other
  // tabs adopting the arcade look). Light cards pop hard against these.
  static const felt = Color(0xFF1A2B20);
  static const feltLine = Color(0x1FFFFFFF);

  // Pill button palette (3 colors)
  // Primary – forest green
  static const pillGreen = roofLight;
  static const pillGreenDark = roofMid;
  static const pillGreenShadow = roofDark;
  // Secondary – trail ochre
  static const pillGold = Color(0xFFECC86A);
  static const pillGoldDark = Color(0xFFD8B54E);
  static const pillGoldShadow = Color(0xFF9A7A2D);
  // Accent – campfire clay
  static const pillTerra = Color(0xFFD47C52);
  static const pillTerraDark = Color(0xFFB76442);
  static const pillTerraShadow = Color(0xFF7F3E26);
}

/// Game-themed text styles — bold and clean, not arcade-pixel.
abstract final class PixelText {
  static TextStyle title({double size = 30, Color color = AppColors.textDark}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      color: color,
      height: 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  static TextStyle body({
    double size = 17.5,
    Color color = AppColors.textDark,
  }) {
    return GoogleFonts.dmSans(
      fontSize: size,
      color: color,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
  }

  static TextStyle number({
    double size = 45,
    Color color = AppColors.textAccent,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      color: color,
      height: 1.0,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  static TextStyle button({
    double size = 20,
    Color color = AppColors.buttonText,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }

  static TextStyle pill({double size = 19, Color color = Colors.white}) {
    return GoogleFonts.dmSans(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
  }
}

class ArcadeCheckerPainter extends CustomPainter {
  const ArcadeCheckerPainter({
    this.tileColor = const Color(0x09FFFFFF),
    this.stripeColor = const Color(0x14000000),
    this.tile = 18,
    this.drawBottomStripe = true,
  });

  final Color tileColor;
  final Color stripeColor;
  final double tile;
  final bool drawBottomStripe;

  @override
  void paint(Canvas canvas, Size size) {
    final tilePaint = Paint()..color = tileColor;

    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final row = (y / tile).floor();
        final col = (x / tile).floor();
        if ((row + col) % 3 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), tilePaint);
        }
      }
    }

    if (drawBottomStripe) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 8, size.width, 8),
        Paint()..color = stripeColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
