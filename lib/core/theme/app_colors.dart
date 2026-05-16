import 'package:flutter/material.dart';

/// Brand palette for the Al-Raqi Document Approval app.
///
/// Primary navy is the dominant brand color — used for app bars, primary
/// buttons, and active states. The gold accent handles highlights, badges,
/// and decorative elements. Neutral grays fill backgrounds and dividers.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF224167); // deep navy
  static const Color primary700 = Color(0xFF1A3554); // hover / pressed
  static const Color primaryGrad = Color(0xFF2D507F); // gradient end-stop
  static const Color accent = Color(0xFFC8A36B); // gold
  static const Color accentSoft = Color(0xFFF2E4CC); // soft gold bg
  static const Color accentTint = Color(0x1FC8A36B); // 12 % gold

  // ── Surfaces ───────────────────────────────────────────────────────
  static const Color bg = Color(0xFFFFFFFF); // scaffold background
  static const Color surface = Color(0xFFF6F7FB); // cards, inputs
  static const Color surface2 = Color(0xFFEEF0F6); // deeper surface
  static const Color border = Color(0xFFE4E6EE);
  static const Color borderStrong = Color(0xFFD2D6E0);

  // ── Text ───────────────────────────────────────────────────────────
  static const Color text = Color(0xFF1B2A41);
  static const Color text2 = Color(0xFF6B7591);
  static const Color text3 = Color(0xFF9099AD);
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDark2 = Color(0xC7FFFFFF); // 78 % white

  // ── Status (semantic) ──────────────────────────────────────────────
  static const Color pending = Color(0xFFC8A36B);
  static const Color pendingBg = Color(0xFFFAF2E1);
  static const Color pendingText = Color(0xFF8A6A23);

  static const Color approved = Color(0xFF2E7D5B);
  static const Color approvedBg = Color(0xFFE4F2EC);
  static const Color approvedText = Color(0xFF1E5A3F);

  static const Color rejected = Color(0xFFB3261E);
  static const Color rejectedBg = Color(0xFFFBE7E5);
  static const Color rejectedText = Color(0xFF8A1B17);

  // ── Shadows ────────────────────────────────────────────────────────
  static const List<BoxShadow> shCard = [
    BoxShadow(
      color: Color(0x0A1B2A41),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0F1B2A41),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> shCardLg = [
    BoxShadow(
      color: Color(0x1A1B2A41),
      blurRadius: 30,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0F1B2A41),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shGold = [
    BoxShadow(
      color: Color(0x4DC8A36B),
      blurRadius: 22,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x2EC8A36B),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> shActionBar = [
    BoxShadow(
      color: Color(0x0D1B2A41),
      blurRadius: 20,
      offset: Offset(0, -6),
    ),
  ];

  // ── Radii ──────────────────────────────────────────────────────────
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rXl = 16;
  static const double r2xl = 18;
  static const double r3xl = 22;
  static const double pill = 999;

  // ── Legacy aliases ────────────────────────────────────────────────
  // Keep existing call-sites compiling while the codebase migrates to
  // the new token names above.
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = surface; // was #F6F7FB
  static const Color textPrimary = text;
  static const Color textSecondary = text2;
  static const Color textOnPrimary = textOnDark;
  static const Color neutralLight = border;
  static const Color statusPending = pending;
  static const Color statusApproved = approved;
  static const Color statusRejected = rejected;
  static const Color statusPendingBg = pendingBg;
  static const Color statusApprovedBg = approvedBg;
  static const Color statusRejectedBg = rejectedBg;
}