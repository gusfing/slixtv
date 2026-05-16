import 'package:flutter/material.dart';

/// Premium dark theme color palette inspired by Netflix/Prime Video.
class AppColors {
  AppColors._();

  // ─── Brand ───────────────────────────────────────────────
  static const Color primary = Color(0xFFE50914);
  static const Color primaryDark = Color(0xFFB20710);
  static const Color primaryLight = Color(0xFFFF3D47);
  static const Color accent = Color(0xFF00D4FF);
  static const Color accentGold = Color(0xFFFFD700);

  // ─── Background ──────────────────────────────────────────
  static const Color background = Color(0xFF0A0A0A);
  static const Color backgroundLight = Color(0xFF141414);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFF222240);
  static const Color card = Color(0xFF16213E);
  static const Color cardHover = Color(0xFF1C2A4A);

  // ─── Text ────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textTertiary = Color(0xFF757575);
  static const Color textHint = Color(0xFF555555);

  // ─── Borders & Dividers ──────────────────────────────────
  static const Color border = Color(0xFF2A2A2A);
  static const Color divider = Color(0xFF333333);

  // ─── Status ──────────────────────────────────────────────
  static const Color success = Color(0xFF46D369);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFE50914);
  static const Color info = Color(0xFF00D4FF);

  // ─── Overlay & Glass ─────────────────────────────────────
  static const Color overlayDark = Color(0xCC000000);
  static const Color overlayLight = Color(0x33FFFFFF);
  static const Color glassBg = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  // ─── Gradients ───────────────────────────────────────────
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC0A0A0A), Color(0xFF0A0A0A)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE50914), Color(0xFFB20710)],
  );

  static const LinearGradient shimmerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF1A1A2E),
      Color(0xFF222240),
      Color(0xFF1A1A2E),
    ],
  );
}
