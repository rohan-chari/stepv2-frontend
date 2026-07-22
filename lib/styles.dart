import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  /// Runtime palette. New UI must resolve colors through this accessor so a
  /// theme change invalidates the widget through Flutter's inherited theme.
  static AppPalette of(BuildContext context) {
    // Async sheets can briefly rebuild while their launching route is being
    // removed. Never perform an inherited lookup through a deactivated
    // context; the light fallback keeps teardown safe and matches legacy UI.
    if (!context.mounted) return AppPalette.light;
    try {
      return Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    } on FlutterError {
      return AppPalette.light;
    }
  }

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

enum _AppColorToken {
  woodLight,
  woodMid,
  woodDark,
  woodDarker,
  woodShadow,
  woodHighlight,
  woodGrain,
  parchment,
  parchmentLight,
  parchmentDark,
  parchmentBorder,
  roofLight,
  roofMid,
  roofDark,
  roofRidge,
  roofEdge,
  skyBand1,
  skyBand2,
  skyBand3,
  skyBand4,
  skyBand5,
  skyBand6,
  skyBand7,
  grassBright,
  grassMid,
  grassDark,
  dirtLight,
  dirtMid,
  dirtDark,
  pineLight,
  pineMid,
  pineDark,
  pineTrunk,
  cloudWhite,
  cloudShadow,
  sunYellow,
  sunOrange,
  sunGlow,
  pinMetal,
  pinHighlight,
  pinShadow,
  textDark,
  textMid,
  textLight,
  textAccent,
  successText,
  buttonFace,
  buttonLight,
  buttonDark,
  buttonShadow,
  buttonText,
  accent,
  accentLight,
  error,
  errorLight,
  medalGold,
  medalSilver,
  medalBronze,
  feedAttack,
  feedShield,
  feedGold,
  feedBoost,
  fireflyGlow,
  coinLight,
  coinMid,
  coinDark,
  coinEdge,
  felt,
  feltLine,
  pillGreen,
  pillGreenDark,
  pillGreenShadow,
  pillGold,
  pillGoldDark,
  pillGoldShadow,
  pillTerra,
  pillTerraDark,
  pillTerraShadow,
  emptySlotFace,
  emptySlotBorder,
  emptySlotMark,
  emptySlotLabel,
  sceneSkyTop,
}

/// Complete app palette carried by [ThemeData]. The legacy token names are
/// intentionally retained during the migration so every existing screen can
/// become adaptive without introducing a second visual vocabulary.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette._(this._colors, {required this.isDark});

  final Map<_AppColorToken, Color> _colors;
  final bool isDark;

  Color _get(_AppColorToken token) => _colors[token]!;

  static final AppPalette light = AppPalette._(_lightColors, isDark: false);
  static final AppPalette night = AppPalette._(_nightColors, isDark: true);

  static const Map<_AppColorToken, Color> _lightColors = {
    _AppColorToken.woodLight: AppColors.woodLight,
    _AppColorToken.woodMid: AppColors.woodMid,
    _AppColorToken.woodDark: AppColors.woodDark,
    _AppColorToken.woodDarker: AppColors.woodDarker,
    _AppColorToken.woodShadow: AppColors.woodShadow,
    _AppColorToken.woodHighlight: AppColors.woodHighlight,
    _AppColorToken.woodGrain: AppColors.woodGrain,
    _AppColorToken.parchment: AppColors.parchment,
    _AppColorToken.parchmentLight: AppColors.parchmentLight,
    _AppColorToken.parchmentDark: AppColors.parchmentDark,
    _AppColorToken.parchmentBorder: AppColors.parchmentBorder,
    _AppColorToken.roofLight: AppColors.roofLight,
    _AppColorToken.roofMid: AppColors.roofMid,
    _AppColorToken.roofDark: AppColors.roofDark,
    _AppColorToken.roofRidge: AppColors.roofRidge,
    _AppColorToken.roofEdge: AppColors.roofEdge,
    _AppColorToken.skyBand1: AppColors.skyBand1,
    _AppColorToken.skyBand2: AppColors.skyBand2,
    _AppColorToken.skyBand3: AppColors.skyBand3,
    _AppColorToken.skyBand4: AppColors.skyBand4,
    _AppColorToken.skyBand5: AppColors.skyBand5,
    _AppColorToken.skyBand6: AppColors.skyBand6,
    _AppColorToken.skyBand7: AppColors.skyBand7,
    _AppColorToken.grassBright: AppColors.grassBright,
    _AppColorToken.grassMid: AppColors.grassMid,
    _AppColorToken.grassDark: AppColors.grassDark,
    _AppColorToken.dirtLight: AppColors.dirtLight,
    _AppColorToken.dirtMid: AppColors.dirtMid,
    _AppColorToken.dirtDark: AppColors.dirtDark,
    _AppColorToken.pineLight: AppColors.pineLight,
    _AppColorToken.pineMid: AppColors.pineMid,
    _AppColorToken.pineDark: AppColors.pineDark,
    _AppColorToken.pineTrunk: AppColors.pineTrunk,
    _AppColorToken.cloudWhite: AppColors.cloudWhite,
    _AppColorToken.cloudShadow: AppColors.cloudShadow,
    _AppColorToken.sunYellow: AppColors.sunYellow,
    _AppColorToken.sunOrange: AppColors.sunOrange,
    _AppColorToken.sunGlow: AppColors.sunGlow,
    _AppColorToken.pinMetal: AppColors.pinMetal,
    _AppColorToken.pinHighlight: AppColors.pinHighlight,
    _AppColorToken.pinShadow: AppColors.pinShadow,
    _AppColorToken.textDark: AppColors.textDark,
    _AppColorToken.textMid: AppColors.textMid,
    _AppColorToken.textLight: AppColors.textLight,
    _AppColorToken.textAccent: AppColors.textAccent,
    _AppColorToken.successText: AppColors.roofMid,
    _AppColorToken.buttonFace: AppColors.buttonFace,
    _AppColorToken.buttonLight: AppColors.buttonLight,
    _AppColorToken.buttonDark: AppColors.buttonDark,
    _AppColorToken.buttonShadow: AppColors.buttonShadow,
    _AppColorToken.buttonText: AppColors.buttonText,
    _AppColorToken.accent: AppColors.accent,
    _AppColorToken.accentLight: AppColors.accentLight,
    _AppColorToken.error: AppColors.error,
    _AppColorToken.errorLight: AppColors.errorLight,
    _AppColorToken.medalGold: AppColors.medalGold,
    _AppColorToken.medalSilver: AppColors.medalSilver,
    _AppColorToken.medalBronze: AppColors.medalBronze,
    _AppColorToken.feedAttack: AppColors.feedAttack,
    _AppColorToken.feedShield: AppColors.feedShield,
    _AppColorToken.feedGold: AppColors.feedGold,
    _AppColorToken.feedBoost: AppColors.feedBoost,
    _AppColorToken.fireflyGlow: AppColors.fireflyGlow,
    _AppColorToken.coinLight: AppColors.coinLight,
    _AppColorToken.coinMid: AppColors.coinMid,
    _AppColorToken.coinDark: AppColors.coinDark,
    _AppColorToken.coinEdge: AppColors.coinEdge,
    _AppColorToken.felt: AppColors.felt,
    _AppColorToken.feltLine: AppColors.feltLine,
    _AppColorToken.pillGreen: AppColors.pillGreen,
    _AppColorToken.pillGreenDark: AppColors.pillGreenDark,
    _AppColorToken.pillGreenShadow: AppColors.pillGreenShadow,
    _AppColorToken.pillGold: AppColors.pillGold,
    _AppColorToken.pillGoldDark: AppColors.pillGoldDark,
    _AppColorToken.pillGoldShadow: AppColors.pillGoldShadow,
    _AppColorToken.pillTerra: AppColors.pillTerra,
    _AppColorToken.pillTerraDark: AppColors.pillTerraDark,
    _AppColorToken.pillTerraShadow: AppColors.pillTerraShadow,
    _AppColorToken.emptySlotFace: Color(0xFFC48C3C),
    _AppColorToken.emptySlotBorder: Color(0xFF6B4420),
    _AppColorToken.emptySlotMark: Color(0xFFFFD740),
    _AppColorToken.emptySlotLabel: Color(0x8066796F),
    _AppColorToken.sceneSkyTop: Color(0xFF0089FB),
  };

  static final Map<_AppColorToken, Color> _nightColors = {
    ..._lightColors,
    _AppColorToken.woodLight: const Color(0xFF253944),
    _AppColorToken.woodMid: const Color(0xFF3F735C),
    _AppColorToken.woodDark: const Color(0xFF142A25),
    _AppColorToken.woodDarker: const Color(0xFF0B181A),
    _AppColorToken.woodShadow: const Color(0xFF081315),
    _AppColorToken.woodHighlight: const Color(0xFFBFD3CF),
    _AppColorToken.woodGrain: const Color(0xFF425A60),
    _AppColorToken.parchment: const Color(0xFF1B2A34),
    _AppColorToken.parchmentLight: const Color(0xFF111D27),
    _AppColorToken.parchmentDark: const Color(0xFF243743),
    _AppColorToken.parchmentBorder: const Color(0xFF48616A),
    _AppColorToken.roofLight: const Color(0xFF315F4D),
    _AppColorToken.roofMid: const Color(0xFF214637),
    _AppColorToken.roofDark: const Color(0xFF142A25),
    _AppColorToken.roofRidge: const Color(0xFF73A58B),
    _AppColorToken.roofEdge: const Color(0xFF091817),
    _AppColorToken.skyBand1: const Color(0xFF06173E),
    _AppColorToken.skyBand2: const Color(0xFF0A2254),
    _AppColorToken.skyBand3: const Color(0xFF102F6A),
    _AppColorToken.skyBand4: const Color(0xFF193D78),
    _AppColorToken.skyBand5: const Color(0xFF244C86),
    _AppColorToken.skyBand6: const Color(0xFF315D91),
    _AppColorToken.skyBand7: const Color(0xFF476D91),
    _AppColorToken.grassBright: const Color(0xFF617052),
    _AppColorToken.grassMid: const Color(0xFF435B45),
    _AppColorToken.grassDark: const Color(0xFF29483B),
    _AppColorToken.dirtLight: const Color(0xFF69483F),
    _AppColorToken.dirtMid: const Color(0xFF523B38),
    _AppColorToken.dirtDark: const Color(0xFF34282C),
    _AppColorToken.cloudWhite: const Color(0xFFC8D4EC),
    _AppColorToken.cloudShadow: const Color(0xFF7085A8),
    _AppColorToken.textDark: const Color(0xFFF7F1E7),
    _AppColorToken.textMid: const Color(0xFFB8C6C8),
    _AppColorToken.textLight: const Color(0xFFF7F1E7),
    _AppColorToken.textAccent: const Color(0xFF8CC6A8),
    _AppColorToken.successText: const Color(0xFF8CC6A8),
    _AppColorToken.buttonFace: const Color(0xFF3F735B),
    _AppColorToken.buttonLight: const Color(0xFF72A88B),
    _AppColorToken.buttonDark: const Color(0xFF28503F),
    _AppColorToken.buttonShadow: const Color(0xFF0C1C19),
    _AppColorToken.buttonText: const Color(0xFFFDF7ED),
    _AppColorToken.accent: const Color(0xFF3F735B),
    _AppColorToken.accentLight: const Color(0xFF72A88B),
    _AppColorToken.error: const Color(0xFFE48670),
    _AppColorToken.errorLight: const Color(0xFF713E3A),
    _AppColorToken.feedAttack: const Color(0xFFF08B76),
    _AppColorToken.feedShield: const Color(0xFF78AEE8),
    _AppColorToken.feedGold: const Color(0xFFD6AD55),
    _AppColorToken.feedBoost: const Color(0xFF8FC5A5),
    // Night medals follow the twilight violet / slate-blue migration (see the
    // pillGold note below) instead of the muddy daytime golds and bronzes,
    // which read as illegible browns on the dark parchment.
    _AppColorToken.medalGold: const Color(0xFF6F58AE),
    _AppColorToken.medalSilver: const Color(0xFF5E6C7A),
    _AppColorToken.medalBronze: const Color(0xFF4C6C7E),
    _AppColorToken.felt: const Color(0xFF091713),
    _AppColorToken.pillGreen: const Color(0xFF3F735B),
    _AppColorToken.pillGreenDark: const Color(0xFF2C5B47),
    _AppColorToken.pillGreenShadow: const Color(0xFF0C1C19),
    // Twilight violet keeps secondary actions distinct from the slate-blue
    // accent without bringing the daytime ochre into the night palette.
    _AppColorToken.pillGold: const Color(0xFF6C5A8F),
    _AppColorToken.pillGoldDark: const Color(0xFF4B3D6B),
    _AppColorToken.pillGoldShadow: const Color(0xFF241D38),
    _AppColorToken.pillTerra: const Color(0xFF527486),
    _AppColorToken.pillTerraDark: const Color(0xFF385665),
    _AppColorToken.pillTerraShadow: const Color(0xFF1B303A),
    // Empty powerup slots follow the twilight violet migration too — the old
    // brown crate face was near-invisible against the dark race board.
    _AppColorToken.emptySlotFace: const Color(0xFF3A3158),
    _AppColorToken.emptySlotBorder: const Color(0xFF241D38),
    _AppColorToken.emptySlotMark: const Color(0xFFD6AD55),
    _AppColorToken.emptySlotLabel: const Color(0xFFD8CBC1),
    _AppColorToken.sceneSkyTop: const Color(0xFF061437),
  };

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette._({
      for (final token in _AppColorToken.values)
        token: Color.lerp(_get(token), other._get(token), t)!,
    }, isDark: t < 0.5 ? isDark : other.isDark);
  }

  Color get woodLight => _get(_AppColorToken.woodLight);
  Color get woodMid => _get(_AppColorToken.woodMid);
  Color get woodDark => _get(_AppColorToken.woodDark);
  Color get woodDarker => _get(_AppColorToken.woodDarker);
  Color get woodShadow => _get(_AppColorToken.woodShadow);
  Color get woodHighlight => _get(_AppColorToken.woodHighlight);
  Color get woodGrain => _get(_AppColorToken.woodGrain);
  Color get parchment => _get(_AppColorToken.parchment);
  Color get parchmentLight => _get(_AppColorToken.parchmentLight);
  Color get parchmentDark => _get(_AppColorToken.parchmentDark);
  Color get parchmentBorder => _get(_AppColorToken.parchmentBorder);
  Color get roofLight => _get(_AppColorToken.roofLight);
  Color get roofMid => _get(_AppColorToken.roofMid);
  Color get roofDark => _get(_AppColorToken.roofDark);
  Color get roofRidge => _get(_AppColorToken.roofRidge);
  Color get roofEdge => _get(_AppColorToken.roofEdge);
  Color get skyBand1 => _get(_AppColorToken.skyBand1);
  Color get skyBand2 => _get(_AppColorToken.skyBand2);
  Color get skyBand3 => _get(_AppColorToken.skyBand3);
  Color get skyBand4 => _get(_AppColorToken.skyBand4);
  Color get skyBand5 => _get(_AppColorToken.skyBand5);
  Color get skyBand6 => _get(_AppColorToken.skyBand6);
  Color get skyBand7 => _get(_AppColorToken.skyBand7);
  Color get grassBright => _get(_AppColorToken.grassBright);
  Color get grassMid => _get(_AppColorToken.grassMid);
  Color get grassDark => _get(_AppColorToken.grassDark);
  Color get dirtLight => _get(_AppColorToken.dirtLight);
  Color get dirtMid => _get(_AppColorToken.dirtMid);
  Color get dirtDark => _get(_AppColorToken.dirtDark);
  Color get pineLight => _get(_AppColorToken.pineLight);
  Color get pineMid => _get(_AppColorToken.pineMid);
  Color get pineDark => _get(_AppColorToken.pineDark);
  Color get pineTrunk => _get(_AppColorToken.pineTrunk);
  Color get cloudWhite => _get(_AppColorToken.cloudWhite);
  Color get cloudShadow => _get(_AppColorToken.cloudShadow);
  Color get sunYellow => _get(_AppColorToken.sunYellow);
  Color get sunOrange => _get(_AppColorToken.sunOrange);
  Color get sunGlow => _get(_AppColorToken.sunGlow);
  Color get pinMetal => _get(_AppColorToken.pinMetal);
  Color get pinHighlight => _get(_AppColorToken.pinHighlight);
  Color get pinShadow => _get(_AppColorToken.pinShadow);
  Color get textDark => _get(_AppColorToken.textDark);
  Color get textMid => _get(_AppColorToken.textMid);
  Color get textLight => _get(_AppColorToken.textLight);
  Color get textAccent => _get(_AppColorToken.textAccent);
  Color get successText => _get(_AppColorToken.successText);
  Color get buttonFace => _get(_AppColorToken.buttonFace);
  Color get buttonLight => _get(_AppColorToken.buttonLight);
  Color get buttonDark => _get(_AppColorToken.buttonDark);
  Color get buttonShadow => _get(_AppColorToken.buttonShadow);
  Color get buttonText => _get(_AppColorToken.buttonText);
  Color get accent => _get(_AppColorToken.accent);
  Color get accentLight => _get(_AppColorToken.accentLight);
  Color get error => _get(_AppColorToken.error);
  Color get errorLight => _get(_AppColorToken.errorLight);
  Color get medalGold => _get(_AppColorToken.medalGold);
  Color get medalSilver => _get(_AppColorToken.medalSilver);
  Color get medalBronze => _get(_AppColorToken.medalBronze);
  Color get feedAttack => _get(_AppColorToken.feedAttack);
  Color get feedShield => _get(_AppColorToken.feedShield);
  Color get feedGold => _get(_AppColorToken.feedGold);
  Color get feedBoost => _get(_AppColorToken.feedBoost);
  Color get fireflyGlow => _get(_AppColorToken.fireflyGlow);
  Color get coinLight => _get(_AppColorToken.coinLight);
  Color get coinMid => _get(_AppColorToken.coinMid);
  Color get coinDark => _get(_AppColorToken.coinDark);
  Color get coinEdge => _get(_AppColorToken.coinEdge);
  Color get felt => _get(_AppColorToken.felt);
  Color get feltLine => _get(_AppColorToken.feltLine);
  Color get pillGreen => _get(_AppColorToken.pillGreen);
  Color get pillGreenDark => _get(_AppColorToken.pillGreenDark);
  Color get pillGreenShadow => _get(_AppColorToken.pillGreenShadow);
  Color get pillGold => _get(_AppColorToken.pillGold);
  Color get pillGoldDark => _get(_AppColorToken.pillGoldDark);
  Color get pillGoldShadow => _get(_AppColorToken.pillGoldShadow);
  Color get pillTerra => _get(_AppColorToken.pillTerra);
  Color get pillTerraDark => _get(_AppColorToken.pillTerraDark);
  Color get pillTerraShadow => _get(_AppColorToken.pillTerraShadow);
  Color get emptySlotFace => _get(_AppColorToken.emptySlotFace);
  Color get emptySlotBorder => _get(_AppColorToken.emptySlotBorder);
  Color get emptySlotMark => _get(_AppColorToken.emptySlotMark);
  Color get emptySlotLabel => _get(_AppColorToken.emptySlotLabel);
  Color get sceneSkyTop => _get(_AppColorToken.sceneSkyTop);

  // Home chrome aliases. Keeping them on the same palette removes the former
  // second source of truth while allowing the home components to retain their
  // concise design-language names.
  Color get ink => textDark;
  Color get inkSoft => roofRidge;
  Color get surface => parchment;
  Color get surfaceMuted => parchmentDark;
  Color get line => textDark;
  Color get lineSoft => parchmentBorder;
  Color get sage => roofLight;
  Color get sageDeep => roofMid;
  Color get clay => pillTerra;
  Color get gold => pillGold;
  Color get cream => parchmentLight;
  Color get muted => textMid;
  Color get success => grassDark;
}

@immutable
class AppThemeAssets extends ThemeExtension<AppThemeAssets> {
  const AppThemeAssets({
    required this.homeHeroSky,
    required this.homeHeroGround,
    required this.homeClouds,
    required this.homeCourse,
    required this.raceDayCourse,
  });

  static const light = AppThemeAssets(
    homeHeroSky: 'assets/images/home_hero_sky.png',
    homeHeroGround: 'assets/images/home_hero_ground.png',
    homeClouds: 'assets/images/home_clouds_day.png',
    homeCourse: 'assets/images/home_race_course_platformer.png',
    raceDayCourse: 'assets/images/race_day_course.png',
  );
  static const night = AppThemeAssets(
    homeHeroSky: 'assets/images/home_hero_sky_night.png',
    homeHeroGround: 'assets/images/home_hero_ground_night.png',
    homeClouds: 'assets/images/home_clouds_night.png',
    homeCourse: 'assets/images/home_race_course_platformer_night.png',
    raceDayCourse: 'assets/images/race_day_course_night.png',
  );

  final String homeHeroSky;
  final String homeHeroGround;
  final String homeClouds;
  final String homeCourse;
  final String raceDayCourse;

  static AppThemeAssets of(BuildContext context) {
    if (!context.mounted) return light;
    try {
      return Theme.of(context).extension<AppThemeAssets>() ?? light;
    } on FlutterError {
      return light;
    }
  }

  @override
  AppThemeAssets copyWith({
    String? homeHeroSky,
    String? homeHeroGround,
    String? homeClouds,
    String? homeCourse,
    String? raceDayCourse,
  }) => AppThemeAssets(
    homeHeroSky: homeHeroSky ?? this.homeHeroSky,
    homeHeroGround: homeHeroGround ?? this.homeHeroGround,
    homeClouds: homeClouds ?? this.homeClouds,
    homeCourse: homeCourse ?? this.homeCourse,
    raceDayCourse: raceDayCourse ?? this.raceDayCourse,
  );

  @override
  AppThemeAssets lerp(covariant AppThemeAssets? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

abstract final class AppThemeData {
  static ThemeData light() => _build(AppPalette.light, AppThemeAssets.light);
  static ThemeData night() => _build(AppPalette.night, AppThemeAssets.night);

  static ThemeData _build(AppPalette palette, AppThemeAssets assets) {
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: brightness,
          surface: palette.parchment,
          error: palette.error,
        ).copyWith(
          primary: palette.accent,
          onPrimary: palette.buttonText,
          secondary: palette.pillGold,
          onSecondary: palette.textDark,
          surface: palette.parchment,
          onSurface: palette.textDark,
          outline: palette.parchmentBorder,
        );
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.parchmentLight,
      canvasColor: palette.parchment,
      dialogTheme: DialogThemeData(backgroundColor: palette.parchment),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.parchment,
      ),
      dividerColor: palette.parchmentBorder,
      disabledColor: palette.textMid.withValues(alpha: 0.5),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.parchmentDark,
        circularTrackColor: palette.parchmentDark,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.woodDarker,
        contentTextStyle: GoogleFonts.dmSans(color: palette.textLight),
        actionTextColor: palette.pillGold,
      ),
      useMaterial3: true,
      extensions: [palette, assets],
    );
  }
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
