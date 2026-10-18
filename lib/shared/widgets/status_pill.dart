import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'day_state.dart';

/// Rounded label with an optional leading icon. Pairs text with an icon so
/// status is never conveyed by colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon,
    required this.fg,
    required this.bg,
  });

  StatusPill.day(DayState state, {super.key})
      : label = state.label,
        icon = state.icon,
        fg = state.fg,
        bg = state.bg;

  final String label;
  final IconData? icon;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
