import 'package:flutter/material.dart';

/// Písma se dodávají v balíčku (assets/fonts, viz pubspec) — appka nikdy
/// nestahuje fonty za běhu, aby nevznikl síťový požadavek na cizí CDN.
const String kFontSans = 'Inter';
const String kFontMono = 'JetBrains Mono';

/// Barevná paleta Šepot — „Nokturno".
/// Noc + žhavý korál (ember) + chladný šum (mist). Dramaturgie: teplé konce,
/// studený střed — lidé jsou teplí (ember), síť je chladná (mist).
class SepotColors {
  SepotColors._();

  // Pozadí — noc
  static const Color background = Color(0xFF0B0C12);
  static const Color surface = Color(0xFF12141D);
  static const Color surfaceVariant = Color(0xFF191C28);

  // Text
  static const Color textPrimary = Color(0xFFF0EEE8); // mléko
  static const Color textSecondary = Color(0xFF9AA0B5); // mlha
  static const Color textMuted = Color(0xFF626880);

  // Akcentní barvy
  static const Color ember = Color(0xFFF0795A); // žhavý korál — lidé, CTA
  static const Color emberInk = Color(0xFF2B120A); // text na ember ploše
  static const Color mist = Color(0xFF7D8BA6); // chladný šum — šifra, síť
  static const Color sage = Color(0xFF7FAE8C); // šalvěj — ověřeno/doručeno

  // Funkční barvy
  static const Color error = Color(0xFFCF6B6B); // cihla
  static const Color warning = Color(0xFFD9A441);
  static const Color success = Color(0xFF7FAE8C);

  // Okraje a oddělovače
  static const Color border = Color(0xFF262A3A);
  static const Color divider = Color(0xFF171A26);

  // Bubliny zpráv — odeslaná teplá (ember), přijatá chladná (povrch)
  static const Color bubbleSent = Color(0xFFF0795A);
  static const Color bubbleReceived = Color(0xFF191C28);
}

/// Témata aplikace
class SepotTheme {
  SepotTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SepotColors.background,
      colorScheme: const ColorScheme.dark(
        primary: SepotColors.ember,
        secondary: SepotColors.mist,
        tertiary: SepotColors.sage,
        surface: SepotColors.surface,
        error: SepotColors.error,
        onPrimary: SepotColors.emberInk,
        onSecondary: SepotColors.emberInk,
        onSurface: SepotColors.textPrimary,
        onError: Colors.white,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: kFontSans,
            bodyColor: SepotColors.textPrimary,
            displayColor: SepotColors.textPrimary,
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SepotColors.background,
        foregroundColor: SepotColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: SepotColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: SepotColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SepotColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SepotColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SepotColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SepotColors.ember, width: 2),
        ),
        hintStyle: const TextStyle(color: SepotColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SepotColors.ember,
          foregroundColor: SepotColors.emberInk,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: kFontSans,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SepotColors.ember,
          side: const BorderSide(color: SepotColors.ember),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: SepotColors.ember,
        foregroundColor: SepotColors.emberInk,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(
        color: SepotColors.divider,
        thickness: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SepotColors.surface,
        selectedItemColor: SepotColors.ember,
        unselectedItemColor: SepotColors.textMuted,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SepotColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: SepotColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SepotColors.surfaceVariant,
        contentTextStyle: const TextStyle(color: SepotColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Styl pro kryptografické texty (monospace)
  static const TextStyle cryptoText = TextStyle(
    fontFamily: kFontMono,
    color: SepotColors.mist,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// Styl pro Šepot ID
  static const TextStyle idText = TextStyle(
    fontFamily: kFontMono,
    color: SepotColors.ember,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
}
