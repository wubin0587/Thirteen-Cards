import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const appBg = Color(0xFF07120D);
  static const felt = Color(0xFF0F6A43);
  static const feltDark = Color(0xFF08452F);
  static const feltLight = Color(0xFF1A6B49);
  static const rail = Color(0xFF3A2519);
  static const panel = Color(0xDD0F1815);
  static const panelStrong = Color(0xF00B1210);
  static const line = Color(0x24FFFFFF);
  static const lineStrong = Color(0x42FFFFFF);
  static const paper = Color(0xFFFFF9ED);
  static const paperEdge = Color(0xFFDDCCB2);
  static const ink = Color(0xFF17110D);
  static const text = Color(0xFFFFF6E8);
  static const muted = Color(0xFFC9D4CA);
  static const dim = Color(0xFF829087);
  static const suitRed = Color(0xFFC72E27);
  static const suitBlack = Color(0xFF171717);
  static const gold = Color(0xFFE5B654);
  static const blue = Color(0xFF5AA8FF);
  static const green = Color(0xFF52C783);
  static const danger = Color(0xFFE45D52);
}

class AppTextTokens {
  const AppTextTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.cardRank,
    required this.cardSuit,
    required this.cardCenter,
    required this.score,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double cardRank;
  final double cardSuit;
  final double cardCenter;
  final double score;

  static AppTextTokens of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    if (width > size.height && size.height < 520) {
      return const AppTextTokens(
        xs: 10,
        sm: 11,
        md: 12,
        lg: 14,
        cardRank: 16,
        cardSuit: 13,
        cardCenter: 24,
        score: 16,
      );
    }
    if (width < 760) {
      return const AppTextTokens(
        xs: 15,
        sm: 17,
        md: 19,
        lg: 23,
        cardRank: 25,
        cardSuit: 21,
        cardCenter: 34,
        score: 25,
      );
    }
    if (width < 1080) {
      return const AppTextTokens(
        xs: 13,
        sm: 15,
        md: 17,
        lg: 20,
        cardRank: 22,
        cardSuit: 18,
        cardCenter: 30,
        score: 23,
      );
    }
    return const AppTextTokens(
      xs: 13,
      sm: 15,
      md: 17,
      lg: 22,
      cardRank: 24,
      cardSuit: 20,
      cardCenter: 34,
      score: 26,
    );
  }
}

ThemeData buildCardsTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.felt,
      brightness: Brightness.dark,
      surface: AppColors.panelStrong,
    ),
    scaffoldBackgroundColor: AppColors.appBg,
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'Segoe UI',
      'Roboto',
      'Arial',
    ],
  );
}
