import 'package:flutter/material.dart';

import 'app_services.dart';
import 'ui/search_screen.dart';

class TransactionSearchApp extends StatelessWidget {
  const TransactionSearchApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transaction search',
    theme: _theme(),
    home: SearchScreen(services: services),
  );
}

ThemeData _theme() {
  const ink = Color(0xFF14312F);
  const paper = Color(0xFFF3F6F6);
  const card = Color(0xFFFFFFFF);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0E7490),
    primary: const Color(0xFF0F6E6B),
    onPrimary: Colors.white,
    secondary: const Color(0xFFB45309),
    surface: card,
    onSurface: ink,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    appBarTheme: AppBarTheme(
      backgroundColor: card,
      foregroundColor: ink,
      elevation: 3,
      shadowColor: ink.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 3,
      shadowColor: const Color(0x3314312F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFE6F3F2),
      selectedColor: const Color(0xFFD3EBE9),
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Color(0xFF0F6E6B)),
      side: BorderSide.none,
      elevation: 1,
      shadowColor: ink.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      hintStyle: TextStyle(color: ink.withValues(alpha: 0.45)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF0F6E6B)),
    dividerColor: const Color(0xFFD5E0DF),
  );
}
