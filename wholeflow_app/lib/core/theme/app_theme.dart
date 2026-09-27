import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Brand seed used when the device offers no dynamic (Material You) colours.
const brandSeed = Color(0xFF00796B);

// Hues for the semantic colours; tones come from each scheme so they keep AA
// contrast on the app's surfaces in both brightnesses.
const _owedSeed = Color(0xFFB3261E);
const _creditSeed = Color(0xFF2E7D32);
const _warningSeed = Color(0xFFB26A00);

/// Spacing scale. Widgets use these instead of literal numbers.
abstract final class Insets {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Width at which the shell switches from NavigationBar to NavigationRail.
  static const double railBreakpoint = 600;

  /// Maximum width of reading content on tablets.
  static const double maxContentWidth = 840;
}

/// Colours with a business meaning: amount owed (Dr), in credit (Cr), and
/// sync warnings. Always paired with a text label, never colour alone.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.owed,
    required this.owedContainer,
    required this.onOwedContainer,
    required this.credit,
    required this.creditContainer,
    required this.onCreditContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  factory SemanticColors.from(ColorScheme scheme) {
    ColorScheme tone(Color seed) {
      // Harmonise with the active primary so dynamic colour still looks coherent.
      return ColorScheme.fromSeed(seedColor: seed.harmonizeWith(scheme.primary), brightness: scheme.brightness);
    }

    final owed = tone(_owedSeed);
    final credit = tone(_creditSeed);
    final warning = tone(_warningSeed);
    return SemanticColors(
      owed: owed.primary,
      owedContainer: owed.primaryContainer,
      onOwedContainer: owed.onPrimaryContainer,
      credit: credit.primary,
      creditContainer: credit.primaryContainer,
      onCreditContainer: credit.onPrimaryContainer,
      warning: warning.primary,
      warningContainer: warning.primaryContainer,
      onWarningContainer: warning.onPrimaryContainer,
    );
  }

  final Color owed;
  final Color owedContainer;
  final Color onOwedContainer;
  final Color credit;
  final Color creditContainer;
  final Color onCreditContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  SemanticColors copyWith({
    Color? owed,
    Color? owedContainer,
    Color? onOwedContainer,
    Color? credit,
    Color? creditContainer,
    Color? onCreditContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) => SemanticColors(
    owed: owed ?? this.owed,
    owedContainer: owedContainer ?? this.owedContainer,
    onOwedContainer: onOwedContainer ?? this.onOwedContainer,
    credit: credit ?? this.credit,
    creditContainer: creditContainer ?? this.creditContainer,
    onCreditContainer: onCreditContainer ?? this.onCreditContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
  );

  @override
  SemanticColors lerp(SemanticColors? other, double t) {
    if (other == null) return this;
    return SemanticColors(
      owed: Color.lerp(owed, other.owed, t)!,
      owedContainer: Color.lerp(owedContainer, other.owedContainer, t)!,
      onOwedContainer: Color.lerp(onOwedContainer, other.onOwedContainer, t)!,
      credit: Color.lerp(credit, other.credit, t)!,
      creditContainer: Color.lerp(creditContainer, other.creditContainer, t)!,
      onCreditContainer: Color.lerp(onCreditContainer, other.onCreditContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  SemanticColors get semantic => Theme.of(this).extension<SemanticColors>()!;
}

abstract final class AppTheme {
  static ThemeData light([ColorScheme? dynamicScheme]) =>
      _build(_harmonized(dynamicScheme) ?? ColorScheme.fromSeed(seedColor: brandSeed));

  static ThemeData dark([ColorScheme? dynamicScheme]) =>
      _build(_harmonized(dynamicScheme) ?? ColorScheme.fromSeed(seedColor: brandSeed, brightness: Brightness.dark));

  /// Shifts the error colours of a device (Material You) scheme towards its primary.
  static ColorScheme? _harmonized(ColorScheme? s) => s?.copyWith(
    error: s.error.harmonizeWith(s.primary),
    onError: s.onError.harmonizeWith(s.primary),
    errorContainer: s.errorContainer.harmonizeWith(s.primary),
    onErrorContainer: s.onErrorContainer.harmonizeWith(s.primary),
  );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      extensions: [SemanticColors.from(scheme)],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        scrolledUnderElevation: 3,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: Insets.l)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      chipTheme: const ChipThemeData(showCheckmark: true),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
