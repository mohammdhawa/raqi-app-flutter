import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/attendance_queue_controller.dart';

class PendingSyncBanner extends ConsumerWidget {
  const PendingSyncBanner({super.key, required this.count});
  final int count;

  /// Escape hatch for a queue the server never accepts: confirm, then drop
  /// every pending record. Guarded by a dialog because it's irreversible —
  /// these records can't reach the server anymore either way.
  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف السجلات المعلّقة'),
          content: Text(
            'سيتم حذف $count سجلًا لم يتمكن التطبيق من مزامنتها مع الخادم. '
            'لا يمكن التراجع عن هذا الإجراء. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'حذف',
                style: TextStyle(color: AppColors.rejected),
              ),
            ),
          ],
        ),
      ),
    );
    if (shouldDiscard == true) {
      await ref.read(attendanceQueueProvider.notifier).discardPending();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            color: AppColors.pendingText,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'يوجد سجل واحد بانتظار المزامنة — سيُرفع تلقائيًا عند توفر الاتصال.'
                  : 'يوجد $count سجلات بانتظار المزامنة — ستُرفع تلقائيًا عند توفر الاتصال.',
              style: AppTheme.bodyS(color: AppColors.pendingText),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _confirmDiscard(context, ref),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'حذف',
                style: AppTheme.bodyS(color: AppColors.pendingText).copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
