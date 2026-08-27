import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';

/// Leave-balance summary card shown on the attendance screen: allocated,
/// used, and remaining days for the current year. Handles its own
/// loading / error states off [leaveBalanceProvider].
class LeaveBalanceCard extends ConsumerWidget {
  const LeaveBalanceCard({super.key, this.onTap});

  /// Optional tap target (e.g. open the leave hub).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(leaveBalanceProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.r2xl),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: balanceAsync.when(
              data: (balance) => _Content(balance: balance, showChevron: onTap != null),
              loading: () => const _LoadingState(),
              error: (e, _) => _ErrorState(
                message: e is ApiFailure
                    ? arabicMessageFor(e.code, fallback: 'تعذّر تحميل رصيد الإجازات.')
                    : 'تعذّر تحميل رصيد الإجازات.',
                onRetry: () => ref.invalidate(leaveBalanceProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.balance, required this.showChevron});

  final LeaveBalance balance;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.beach_access_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text('رصيد الإجازات', style: AppTheme.title()),
            const SizedBox(width: 6),
            Text(
              '${balance.year}',
              style: AppTheme.captionS(color: AppColors.text3),
            ),
            const Spacer(),
            if (showChevron)
              const Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: AppColors.text3,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(
              label: 'المخصص',
              value: balance.allocatedDays,
              color: AppColors.primary,
            ),
            _divider(),
            _Stat(
              label: 'المستخدم',
              value: balance.usedDays,
              color: AppColors.pendingText,
            ),
            _divider(),
            _Stat(
              label: 'المتبقي',
              value: balance.remainingDays,
              color: AppColors.approved,
            ),
          ],
        ),

        // Days taken under a non-deducting type (sick, unpaid, bereavement…).
        // A SEPARATE line, never folded into the three stats above: it is not
        // part of "المستخدم" and does not reduce "المتبقي", so no arithmetic
        // relates it to them. Rendered only when there are any — a permanent
        // "0" would be noise on the home screen for most employees.
        //
        // This is NOT the attendance reports' `excused_days`, which counts
        // HR-filed excuses whether or not they deduct. Different sets.
        if (balance.nonDeductingDays > 0) ...[
          const SizedBox(height: 12),
          _FootNote(
            icon: Icons.verified_outlined,
            color: AppColors.approved,
            text: 'أيام لم تُخصم من الرصيد: ${balance.nonDeductingDays}',
          ),
        ],

        // Non-zero only when HR force-recorded an excuse past the allocation;
        // "المتبقي" stays clamped at 0, so without this the overdraft would be
        // invisible.
        if (balance.overBalanceDays > 0) ...[
          const SizedBox(height: 8),
          _FootNote(
            icon: Icons.warning_amber_rounded,
            color: AppColors.pendingText,
            text: 'أيام تجاوزت الرصيد: ${balance.overBalanceDays}',
          ),
        ],
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: AppColors.border,
      );
}

/// A single figure that stands apart from the three headline stats — it
/// neither adds to nor subtracts from them.
class _FootNote extends StatelessWidget {
  const _FootNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTheme.captionS(color: color)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.captionS(color: AppColors.text2)),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 86,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 20, color: AppColors.rejected),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: AppTheme.bodyS(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text('إعادة'),
        ),
      ],
    );
  }
}
