import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class PetNoteThemeTokens extends ThemeExtension<PetNoteThemeTokens> {
  const PetNoteThemeTokens({
    required this.pageGradientTop,
    required this.pageGradientBottom,
    required this.pageGlow,
    required this.primaryText,
    required this.secondaryText,
    required this.panelBackground,
    required this.panelStrongBackground,
    required this.panelBorder,
    required this.panelShadow,
    required this.panelHighlightShadow,
    required this.secondarySurface,
    required this.segmentedIdleBackground,
    required this.segmentedSelectedBackground,
    required this.listRowBackground,
    required this.navBackground,
    required this.navBorder,
    required this.navIconInactive,
    required this.navLabelInactive,
    required this.navAddGradientStart,
    required this.navAddGradientEnd,
    required this.navAddShadow,
    required this.badgeBlueBackground,
    required this.badgeBlueForeground,
    required this.badgeGoldBackground,
    required this.badgeGoldForeground,
    required this.badgeRedBackground,
    required this.badgeRedForeground,
    required this.emptyStateBackground,
    required this.emptyStateForeground,
  });

  final Color pageGradientTop;
  final Color pageGradientBottom;
  final Color pageGlow;
  final Color primaryText;
  final Color secondaryText;
  final Color panelBackground;
  final Color panelStrongBackground;
  final Color panelBorder;
  final Color panelShadow;
  final Color panelHighlightShadow;
  final Color secondarySurface;
  final Color segmentedIdleBackground;
  final Color segmentedSelectedBackground;
  final Color listRowBackground;
  final Color navBackground;
  final Color navBorder;
  final Color navIconInactive;
  final Color navLabelInactive;
  final Color navAddGradientStart;
  final Color navAddGradientEnd;
  final Color navAddShadow;
  final Color badgeBlueBackground;
  final Color badgeBlueForeground;
  final Color badgeGoldBackground;
  final Color badgeGoldForeground;
  final Color badgeRedBackground;
  final Color badgeRedForeground;
  final Color emptyStateBackground;
  final Color emptyStateForeground;

  @override
  PetNoteThemeTokens copyWith({
    Color? pageGradientTop,
    Color? pageGradientBottom,
    Color? pageGlow,
    Color? primaryText,
    Color? secondaryText,
    Color? panelBackground,
    Color? panelStrongBackground,
    Color? panelBorder,
    Color? panelShadow,
    Color? panelHighlightShadow,
    Color? secondarySurface,
    Color? segmentedIdleBackground,
    Color? segmentedSelectedBackground,
    Color? listRowBackground,
    Color? navBackground,
    Color? navBorder,
    Color? navIconInactive,
    Color? navLabelInactive,
    Color? navAddGradientStart,
    Color? navAddGradientEnd,
    Color? navAddShadow,
    Color? badgeBlueBackground,
    Color? badgeBlueForeground,
    Color? badgeGoldBackground,
    Color? badgeGoldForeground,
    Color? badgeRedBackground,
    Color? badgeRedForeground,
    Color? emptyStateBackground,
    Color? emptyStateForeground,
  }) {
    return PetNoteThemeTokens(
      pageGradientTop: pageGradientTop ?? this.pageGradientTop,
      pageGradientBottom: pageGradientBottom ?? this.pageGradientBottom,
      pageGlow: pageGlow ?? this.pageGlow,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      panelBackground: panelBackground ?? this.panelBackground,
      panelStrongBackground:
          panelStrongBackground ?? this.panelStrongBackground,
      panelBorder: panelBorder ?? this.panelBorder,
      panelShadow: panelShadow ?? this.panelShadow,
      panelHighlightShadow: panelHighlightShadow ?? this.panelHighlightShadow,
      secondarySurface: secondarySurface ?? this.secondarySurface,
      segmentedIdleBackground:
          segmentedIdleBackground ?? this.segmentedIdleBackground,
      segmentedSelectedBackground:
          segmentedSelectedBackground ?? this.segmentedSelectedBackground,
      listRowBackground: listRowBackground ?? this.listRowBackground,
      navBackground: navBackground ?? this.navBackground,
      navBorder: navBorder ?? this.navBorder,
      navIconInactive: navIconInactive ?? this.navIconInactive,
      navLabelInactive: navLabelInactive ?? this.navLabelInactive,
      navAddGradientStart: navAddGradientStart ?? this.navAddGradientStart,
      navAddGradientEnd: navAddGradientEnd ?? this.navAddGradientEnd,
      navAddShadow: navAddShadow ?? this.navAddShadow,
      badgeBlueBackground: badgeBlueBackground ?? this.badgeBlueBackground,
      badgeBlueForeground: badgeBlueForeground ?? this.badgeBlueForeground,
      badgeGoldBackground: badgeGoldBackground ?? this.badgeGoldBackground,
      badgeGoldForeground: badgeGoldForeground ?? this.badgeGoldForeground,
      badgeRedBackground: badgeRedBackground ?? this.badgeRedBackground,
      badgeRedForeground: badgeRedForeground ?? this.badgeRedForeground,
      emptyStateBackground: emptyStateBackground ?? this.emptyStateBackground,
      emptyStateForeground: emptyStateForeground ?? this.emptyStateForeground,
    );
  }

  @override
  PetNoteThemeTokens lerp(
    covariant ThemeExtension<PetNoteThemeTokens>? other,
    double t,
  ) {
    if (other is! PetNoteThemeTokens) {
      return this;
    }
    return PetNoteThemeTokens(
      pageGradientTop: Color.lerp(pageGradientTop, other.pageGradientTop, t)!,
      pageGradientBottom:
          Color.lerp(pageGradientBottom, other.pageGradientBottom, t)!,
      pageGlow: Color.lerp(pageGlow, other.pageGlow, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      panelStrongBackground:
          Color.lerp(panelStrongBackground, other.panelStrongBackground, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      panelShadow: Color.lerp(panelShadow, other.panelShadow, t)!,
      panelHighlightShadow:
          Color.lerp(panelHighlightShadow, other.panelHighlightShadow, t)!,
      secondarySurface:
          Color.lerp(secondarySurface, other.secondarySurface, t)!,
      segmentedIdleBackground: Color.lerp(
          segmentedIdleBackground, other.segmentedIdleBackground, t)!,
      segmentedSelectedBackground: Color.lerp(
        segmentedSelectedBackground,
        other.segmentedSelectedBackground,
        t,
      )!,
      listRowBackground:
          Color.lerp(listRowBackground, other.listRowBackground, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      navBorder: Color.lerp(navBorder, other.navBorder, t)!,
      navIconInactive: Color.lerp(navIconInactive, other.navIconInactive, t)!,
      navLabelInactive:
          Color.lerp(navLabelInactive, other.navLabelInactive, t)!,
      navAddGradientStart:
          Color.lerp(navAddGradientStart, other.navAddGradientStart, t)!,
      navAddGradientEnd:
          Color.lerp(navAddGradientEnd, other.navAddGradientEnd, t)!,
      navAddShadow: Color.lerp(navAddShadow, other.navAddShadow, t)!,
      badgeBlueBackground:
          Color.lerp(badgeBlueBackground, other.badgeBlueBackground, t)!,
      badgeBlueForeground:
          Color.lerp(badgeBlueForeground, other.badgeBlueForeground, t)!,
      badgeGoldBackground:
          Color.lerp(badgeGoldBackground, other.badgeGoldBackground, t)!,
      badgeGoldForeground:
          Color.lerp(badgeGoldForeground, other.badgeGoldForeground, t)!,
      badgeRedBackground:
          Color.lerp(badgeRedBackground, other.badgeRedBackground, t)!,
      badgeRedForeground:
          Color.lerp(badgeRedForeground, other.badgeRedForeground, t)!,
      emptyStateBackground:
          Color.lerp(emptyStateBackground, other.emptyStateBackground, t)!,
      emptyStateForeground:
          Color.lerp(emptyStateForeground, other.emptyStateForeground, t)!,
    );
  }
}

const _accent = Color(0xFFF2A65A);
const _accentDeep = Color(0xFFD9822B);
const _accentSoft = Color(0xFFFDEBD6);

const lightPetNoteTokens = PetNoteThemeTokens(
  pageGradientTop: Color(0xFFF8F4EF),
  pageGradientBottom: Color(0xFFF3F4F8),
  pageGlow: Color(0x66FFFFFF),
  primaryText: Color(0xFF17181C),
  secondaryText: Color(0xFF6C7280),
  panelBackground: Color(0xF7FFFFFF),
  panelStrongBackground: Color(0xF2FFFFFF),
  panelBorder: Color(0xFFF7F8FB),
  panelShadow: Color(0x12000000),
  panelHighlightShadow: Color(0x08FFFFFF),
  secondarySurface: Color(0xFFF4F5F8),
  segmentedIdleBackground: Color(0xFFF4F5F8),
  segmentedSelectedBackground: _accent,
  listRowBackground: Color(0xFFF7F8FB),
  navBackground: Color(0xCCFFFFFF),
  navBorder: Color(0xD9FFFFFF),
  navIconInactive: Color(0xFF7E8492),
  navLabelInactive: Color(0xFF7E8492),
  navAddGradientStart: Color(0xFF90CE9B),
  navAddGradientEnd: Color(0xFF6AB57A),
  navAddShadow: Color(0x226AB57A),
  badgeBlueBackground: Color(0xFFEAF0FF),
  badgeBlueForeground: Color(0xFF335FCA),
  badgeGoldBackground: Color(0xFFFFF3D8),
  badgeGoldForeground: Color(0xFF976A00),
  badgeRedBackground: Color(0xFFFDEBE8),
  badgeRedForeground: Color(0xFFC7533E),
  emptyStateBackground: Color(0xFFE9F0FF),
  emptyStateForeground: Color(0xFF5B8CFF),
);

const darkPetNoteTokens = PetNoteThemeTokens(
  pageGradientTop: Color(0xFF060708),
  pageGradientBottom: Color(0xFF010102),
  pageGlow: Color(0x10FFFFFF),
  primaryText: Color(0xFFF4F4F6),
  secondaryText: Color(0xFFB3B8C2),
  panelBackground: Color(0xF20A0B0D),
  panelStrongBackground: Color(0xF5131519),
  panelBorder: Color(0xFF1C2026),
  panelShadow: Color(0x5A000000),
  panelHighlightShadow: Color(0x06000000),
  secondarySurface: Color(0xFF101217),
  segmentedIdleBackground: Color(0xFF101217),
  segmentedSelectedBackground: Color(0xFFD9822B),
  listRowBackground: Color(0xFF0C0E12),
  navBackground: Color(0xE6060709),
  navBorder: Color(0xFF181B20),
  navIconInactive: Color(0xFFA1A8B4),
  navLabelInactive: Color(0xFFA1A8B4),
  navAddGradientStart: Color(0xFF73B87F),
  navAddGradientEnd: Color(0xFF528F63),
  navAddShadow: Color(0x40192E1D),
  badgeBlueBackground: Color(0xFF1A2940),
  badgeBlueForeground: Color(0xFFA5C6FF),
  badgeGoldBackground: Color(0xFF3F3014),
  badgeGoldForeground: Color(0xFFF2CC79),
  badgeRedBackground: Color(0xFF402021),
  badgeRedForeground: Color(0xFFFFA79B),
  emptyStateBackground: Color(0xFF1B2A40),
  emptyStateForeground: Color(0xFF8FB4FF),
);

ThemeData buildPetNoteTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final tokens = isDark ? darkPetNoteTokens : lightPetNoteTokens;
  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: _accent,
          secondary: _accentDeep,
          tertiary: _accentDeep,
          surface: Color(0xFF15171C),
          surfaceContainerHighest: Color(0xFF232831),
          primaryContainer: Color(0xFF4A2D14),
          secondaryContainer: Color(0xFF322114),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFFF3F3F5),
        ).copyWith(surfaceContainerHighest: const Color(0xFF232831))
      : const ColorScheme.light(
          primary: _accent,
          secondary: _accentDeep,
          tertiary: _accentDeep,
          surface: Color(0xFFF8F5F0),
          surfaceContainerHighest: Color(0xFFF3F4F8),
          primaryContainer: _accentSoft,
          secondaryContainer: Color(0xFFFFF5E8),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF17181C),
        ).copyWith(surfaceContainerHighest: const Color(0xFFF3F4F8));

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF020304) : const Color(0xFFF5F2EC),
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontSize: 34, height: 1.04),
      headlineSmall: TextStyle(fontSize: 27, height: 1.1),
      titleLarge: TextStyle(fontSize: 22, height: 1.2),
      titleMedium: TextStyle(fontSize: 18, height: 1.25),
      bodyLarge: TextStyle(fontSize: 16, height: 1.35),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      bodySmall: TextStyle(fontSize: 12, height: 1.45),
      labelLarge: TextStyle(fontSize: 14, height: 1.1),
      labelMedium: TextStyle(fontSize: 12, height: 1.1),
    ).apply(
      bodyColor: tokens.primaryText,
      displayColor: tokens.primaryText,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.secondaryText,
        minimumSize: const Size(0, 46),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _accent;
        }
        return tokens.secondaryText;
      }),
    ),
    dividerColor: tokens.panelBorder,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1C2027) : const Color(0xFFF6F7FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF818896) : const Color(0xFF9AA0AC),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: _accentDeep, width: 1.3),
      ),
    ),
    extensions: [tokens],
  );
}

SystemUiOverlayStyle petNoteOverlayStyleForTheme(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarDividerColor: const Color(0x00000000),
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}

extension PetNoteThemeX on BuildContext {
  ThemeData get appTheme => Theme.of(this);

  PetNoteThemeTokens get petNoteTokens =>
      appTheme.extension<PetNoteThemeTokens>()!;
}
