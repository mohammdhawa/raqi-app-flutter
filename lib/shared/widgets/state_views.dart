import 'package:flutter/material.dart';

import '../../core/errors/api_failure.dart';
import '../../core/theme/app_colors.dart';

/// Centered loading indicator — 32 dp navy spinner, stroke 3.
class AlraqiLoading extends StatelessWidget {
  const AlraqiLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 3,
        ),
      ),
    );
  }
}

/// Empty state with icon card, title, subtitle, and a decorative gold rule.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 88×88 rounded-24 surface card with icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 40, color: AppColors.text3),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 240,
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Decorative gold rule
            Container(
              width: 40,
              height: 2,
              color: AppColors.accent,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.failure, this.onRetry});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 88×88 rounded-24 surface card with error icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.rejectedBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.rejected,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              arabicMessageFor(failure.code, fallback: failure.message),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            // Decorative gold rule
            Container(
              width: 40,
              height: 2,
              color: AppColors.accent,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}