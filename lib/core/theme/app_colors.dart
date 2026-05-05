import 'package:flutter/material.dart';

/// Brand palette for the Document Approval app.
///
/// Primary navy is the dominant brand color — used for app bars, primary
/// buttons, and active states. The mauve/lavender pair handles accents and
/// status chips. Neutral grays fill backgrounds and dividers.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF224067); // deep navy
  static const Color accent = Color(0xFFB36A8C); // mauve
  static const Color accentSoft = Color(0xFFBC8CCC); // lavender

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  static const Color neutralLight = Color(0xFFD3D3D3);
  static const Color background = Color(0xFFF6F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE4E6EE);

  // Text
  static const Color textPrimary = Color(0xFF1B2A41);
  static const Color textSecondary = Color(0xFF6B7591);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status (semantic — kept tasteful, not loud)
  static const Color statusPending = Color(0xFFB36A8C); // mauve = waiting
  static const Color statusApproved = Color(0xFF2E7D5B); // muted green
  static const Color statusRejected = Color(0xFFB3261E); // muted red

  // Soft backgrounds for status chips
  static const Color statusPendingBg = Color(0xFFF5E7EE);
  static const Color statusApprovedBg = Color(0xFFE3F1EA);
  static const Color statusRejectedBg = Color(0xFFFAE4E2);
}
