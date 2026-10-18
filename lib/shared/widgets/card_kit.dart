import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

BoxDecoration _cardDecoration({Color border = AppColors.border}) =>
    BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppColors.rXl),
      border: Border.all(color: border),
    );

/// Renders one independently loading card. Each card owns its own loading,
/// error and stale state so one failing endpoint never blanks the screen.
class CardSlot<T> extends StatelessWidget {
  const CardSlot({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    required this.subject,
    this.skeletonHeight = 88,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  /// What failed to load, used in the error copy (e.g. `رصيد الإجازات`).
  final String subject;
  final double skeletonHeight;

  @override
  Widget build(BuildContext context) {
    // Data wins over error: a failed refresh keeps the last good value on
    // screen with a small retry row instead of replacing it with an error.
    if (value.hasValue) {
      final data = value.requireValue;
      if (!value.hasError) return builder(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          builder(data),
          _RetryRow(
            message: 'تعذّر التحديث',
            onRetry: onRetry,
            compact: true,
          ),
        ],
      );
    }
    if (value.hasError) {
      return _RetryRow(message: 'تعذّر تحميل $subject', onRetry: onRetry);
    }
    return SkeletonCard(height: skeletonHeight);
  }
}

class _RetryRow extends StatelessWidget {
  const _RetryRow({
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 18, color: AppColors.rejected),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: compact
                ? AppTheme.caption(color: AppColors.text2)
                : AppTheme.bodyS(color: AppColors.text),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('إعادة المحاولة'),
        ),
      ],
    );
    if (compact) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _cardDecoration(),
      child: row,
    );
  }
}

/// Placeholder for a loading card. Deliberately static (no shimmer) so it is
/// cheap and never keeps a test or the frame scheduler busy.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'جارٍ التحميل',
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.rXl),
          border: Border.all(color: AppColors.border),
        ),
      ),
    );
  }
}

/// A module whose API does not exist yet. Never shows a value, so unknown
/// data is never mistaken for zero.
class UnavailableCard extends StatelessWidget {
  const UnavailableCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.hourglass_empty_rounded,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(border: AppColors.borderStrong),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$title · ستتوفر قريباً',
                    style: AppTheme.label(color: AppColors.text)),
                const SizedBox(height: 4),
                Text(body, style: AppTheme.bodyS(color: AppColors.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact metric card: label, big value with optional unit, optional caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: iconColor ?? AppColors.text2),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption(color: AppColors.text2)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: AppTheme.heading1(color: AppColors.text)),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(unit!, style: AppTheme.bodyS(color: AppColors.text2)),
                  ],
                ],
              ),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!, style: AppTheme.caption(color: AppColors.text2)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable "needs your attention" row with a tinted icon badge.
class AttentionRow extends StatelessWidget {
  const AttentionRow({
    super.key,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color fg;
  final Color bg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(AppColors.rMd),
                  ),
                  child: Icon(icon, size: 20, color: fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppTheme.label(color: AppColors.text)),
                      Text(subtitle,
                          style: AppTheme.caption(color: AppColors.text2)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded,
                    size: 22, color: AppColors.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
