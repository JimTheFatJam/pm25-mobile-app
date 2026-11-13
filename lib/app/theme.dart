import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Design tokens. Every colour, radius and spacing the screen uses comes from
// here (or from the backend's own category colour, routed through
// [categoryPalette]) -- widgets never carry literal colours.
//
// Identity: clean off-white canvas, deep navy text, a cobalt accent used
// sparingly (icons, links, buttons), and the EPA category colour reserved
// for the reading itself. Cards are low-profile: 1 px hairline border, a
// barely-there shadow in light mode, modest 12 dp corners.
// ---------------------------------------------------------------------------

/// Corner radii shared by every card and inset.
const double kCardRadius = 12;
const double kInsetRadius = 8;

/// Spacing scale.
const double kGap = 12;
const double kCardPad = 16;

/// Semantic colours that Material's ColorScheme does not model, exposed as
/// a ThemeExtension so widgets read them from Theme.of(context).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.border,
    required this.subtleSurface,
    required this.higher,
    required this.lower,
    required this.iconTint,
    required this.shadow,
  });

  /// Secondary text (captions, notes, eyebrows).
  final Color muted;

  /// Card borders / dividers / chart axis.
  final Color border;

  /// Inset surfaces inside cards.
  final Color subtleSurface;

  /// "Pushed the estimate higher" accent (warm).
  final Color higher;

  /// "Pushed the estimate lower" accent (cool, distinct from the app blue).
  final Color lower;

  /// Tinted square behind section icons.
  final Color iconTint;

  /// Card shadow colour (transparent in dark mode).
  final Color shadow;

  static const light = AppColors(
    muted: Color(0xFF5B6473),
    border: Color(0xFFE3E8EF),
    subtleSurface: Color(0xFFF4F6FA),
    higher: Color(0xFFB4530A),
    lower: Color(0xFF0E7C86),
    iconTint: Color(0xFFE6EEFC),
    shadow: Color(0x0F1B2C4A),
  );

  static const dark = AppColors(
    muted: Color(0xFF9AA4B5),
    border: Color(0xFF283245),
    subtleSurface: Color(0xFF1B2433),
    higher: Color(0xFFF5B27A),
    lower: Color(0xFF6ED3DB),
    iconTint: Color(0xFF1E2F4D),
    shadow: Color(0x00000000),
  );

  @override
  AppColors copyWith({Color? muted, Color? border, Color? subtleSurface, Color? higher, Color? lower, Color? iconTint, Color? shadow}) {
    return AppColors(
      muted: muted ?? this.muted,
      border: border ?? this.border,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      higher: higher ?? this.higher,
      lower: lower ?? this.lower,
      iconTint: iconTint ?? this.iconTint,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      higher: Color.lerp(higher, other.higher, t)!,
      lower: Color.lerp(lower, other.lower, t)!,
      iconTint: Color.lerp(iconTint, other.iconTint, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppColorsX on ThemeData {
  AppColors get app => extension<AppColors>() ?? AppColors.light;
}

/// Material 3 theme for either brightness.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? AppColors.dark : AppColors.light;
  final surface = dark ? const Color(0xFF141C2B) : Colors.white;
  final onSurface = dark ? const Color(0xFFE7EBF3) : const Color(0xFF0F1B2D);
  final primary = dark ? const Color(0xFF8DB4FF) : const Color(0xFF1E56D6);
  final background = dark ? const Color(0xFF0B1220) : const Color(0xFFF5F7FB);

  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: colors.muted,
    outlineVariant: colors.border,
    primary: primary,
    onPrimary: dark ? const Color(0xFF0B1220) : Colors.white,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      bodySmall: text.bodySmall?.copyWith(height: 1.35, color: colors.muted),
      labelSmall: text.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700, color: colors.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: onSurface, letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      elevation: dark ? 0 : 1.5,
      shadowColor: colors.shadow,
      color: surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kCardRadius), side: BorderSide(color: colors.border)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: colors.border, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kInsetRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kInsetRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: colors.border),
        foregroundColor: primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: onSurface)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    extensions: [colors],
  );
}

/// Parses "#rrggbb" from the classification scheme; grey if malformed.
Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return const Color(0xFF9CA3AF);
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF9CA3AF) : Color(0xFF000000 | v);
}

double _relativeLuminance(Color c) {
  double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a), lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Category colours such as EPA yellow are unreadable as text on a light
/// surface; darken them (same hue) until they reach WCAG AA 4.5:1 -- the
/// same rule the web app applies. On dark surfaces, lighten instead (dark
/// categories such as EPA "Hazardous" maroon would otherwise vanish).
Color readableOn(Color text, Color surface) {
  final lightSurface = _relativeLuminance(surface) > 0.3;
  var hsl = HSLColor.fromColor(text);
  var out = text;
  for (var i = 0; i < 40 && contrastRatio(out, surface) < 4.5; i++) {
    hsl = hsl.withLightness((hsl.lightness + (lightSurface ? -0.02 : 0.02)).clamp(0.0, 1.0));
    out = hsl.toColor();
  }
  return out;
}

/// The category-aware treatment of the hero: the backend's raw category
/// colour is used as-is only for the accent stripe and dot; text gets the
/// contrast-corrected [accent]; backgrounds get a faint [tint] (restrained
/// gold for Moderate on white, not a block of yellow).
@immutable
class CategoryPalette {
  const CategoryPalette({
    required this.raw,
    required this.accent,
    required this.tint,
    required this.outline,
    required this.onRaw,
  });

  /// The scheme's own colour, exactly as the backend sent it. Safe as a
  /// FILL (stripe, chip background, dot) because nothing has to be read
  /// through it.
  final Color raw;

  /// [raw] forced to >=4.5:1 against the card. Fine for small accents;
  /// no longer used for the large value -- see categoryPalette.
  final Color accent;

  /// [raw] blended into the card at low alpha, for inset backgrounds.
  final Color tint;

  final Color outline;

  /// Black or white, whichever is readable ON [raw]. Lets the chip be a
  /// solid block of the category colour with legible text.
  final Color onRaw;
}

/// Picks black or white text for a filled swatch, by measured contrast
/// rather than a luminance rule of thumb -- EPA yellow and EPA maroon sit
/// on opposite sides of any fixed threshold.
Color onColor(Color background) =>
    contrastRatio(Colors.black, background) >= contrastRatio(Colors.white, background)
        ? Colors.black
        : Colors.white;

CategoryPalette categoryPalette(Color raw, ThemeData theme) {
  final surface = theme.colorScheme.surface;
  final dark = theme.brightness == Brightness.dark;
  return CategoryPalette(
    raw: raw,
    accent: readableOn(raw, surface),
    tint: Color.alphaBlend(raw.withValues(alpha: dark ? 0.16 : 0.12), surface),
    outline: raw.withValues(alpha: dark ? 0.55 : 0.40),
    onRaw: onColor(raw),
  );
}
