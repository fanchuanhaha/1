import 'package:flutter/material.dart';

/// 底部提示包装：调 showSnackBar 前先隐藏当前显示的提示，
/// 实现「不管现在显示的是什么，出现新的就覆盖在上面的」。
class AppMessenger {
  static ScaffoldMessengerState of(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    // 先关闭当前提示，避免堆积排队，新提示直接覆盖旧的
    messenger.hideCurrentSnackBar();
    return messenger;
  }
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color card;
  final Color cardLight;
  final Color accent;
  final Color accentDeep;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color green;
  final Color orange;
  final Color red;

  const AppColors({
    required this.bg,
    required this.card,
    required this.cardLight,
    required this.accent,
    required this.accentDeep,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.green,
    required this.orange,
    required this.red,
  });

  /// 深色配色
  static const AppColors dark = AppColors(
    bg: Color(0xFF0E0E12),
    card: Color(0xFF191921),
    cardLight: Color(0xFF22222C),
    accent: Color(0xFF3D7BFE),
    accentDeep: Color(0xFF1E3D75),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFF9A9AA6),
    divider: Color(0xFF2A2A34),
    green: Color(0xFF34C77B),
    orange: Color(0xFFFFA63D),
    red: Color(0xFFF34C4C),
  );

  /// 浅色配色
  static const AppColors light = AppColors(
    bg: Color(0xFFF4F5F7),
    card: Color(0xFFFFFFFF),
    cardLight: Color(0xFFEDEFF2),
    accent: Color(0xFF3D7BFE),
    accentDeep: Color(0xFFD8E3FF),
    textPrimary: Color(0xFF1A1D21),
    textSecondary: Color(0xFF7A7F87),
    divider: Color(0xFFE2E4E8),
    green: Color(0xFF34C77B),
    orange: Color(0xFFFFA63D),
    red: Color(0xFFF34C4C),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? cardLight,
    Color? accent,
    Color? accentDeep,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? green,
    Color? orange,
    Color? red,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      cardLight: cardLight ?? this.cardLight,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      green: green ?? this.green,
      orange: orange ?? this.orange,
      red: red ?? this.red,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardLight: Color.lerp(cardLight, other.cardLight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      green: Color.lerp(green, other.green, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      red: Color.lerp(red, other.red, t)!,
    );
  }
}

class AppTheme {
  static ThemeData dark() => _build(AppColors.dark);

  static ThemeData light() => _build(AppColors.light);

  static ThemeData _build(AppColors colors) {
    final isDark = identical(colors, AppColors.dark);
    final base = ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            primary: colors.accent,
            secondary: colors.accent,
            surface: colors.card,
            onSurface: colors.textPrimary,
            onPrimary: Colors.white,
          ),
      scaffoldBackgroundColor: colors.bg,
      extensions: [colors],
      fontFamily: 'MiSansPro',
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: colors.accent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: TextStyle(color: colors.textPrimary),
        bodyMedium: TextStyle(color: colors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.bg,
        hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent, width: 1.2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardLight,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(iconColor: colors.textSecondary),
      dividerTheme: DividerThemeData(color: colors.divider),
    );
  }
}