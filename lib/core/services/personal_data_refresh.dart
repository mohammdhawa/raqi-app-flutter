import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/attendance/presentation/providers/leave_providers.dart';
import '../../features/attendance/presentation/providers/month_attendance_providers.dart';
import '../../features/home/domain/attention_items.dart';
import '../../features/requests/presentation/providers/requests_providers.dart';

/// Refetches everything personal the tabs show — leave, the month's
/// attendance, recent records and the document feeds — in one place, so a
/// resume, a pull-to-refresh on الرئيسية or a document decision cannot forget
/// one of them.
///
/// Invalidating a provider nobody holds is a no-op, so the invalidations need
/// no guard. The leave list controllers load themselves on creation, so they
/// are only refreshed when they already exist; the approvals one additionally
/// only for a user who may review, so a role-less user never sends an
/// approver request.
///
/// The attendance controller and the offline queue are not touched: callers
/// reload those themselves, as each already did before this existed.
Future<void> refreshPersonalData(WidgetRef ref) async {
  ref.invalidate(approvedLeaveTodayProvider);
  ref.invalidate(leaveBalanceProvider);
  ref.invalidate(recentRecordsProvider);
  ref.invalidate(monthRecordsProvider);
  refreshDocumentFeeds(ref);
  await Future.wait([
    if (ref.exists(myLeaveRequestsProvider))
      ref.read(myLeaveRequestsProvider.notifier).refresh(),
    if (ref.read(canReviewRequestsProvider) &&
        ref.exists(leaveApprovalsProvider))
      ref.read(leaveApprovalsProvider.notifier).refresh(),
  ]);
}

/// The document half of [refreshPersonalData], for a document mutation
/// (decision, deletion, creation) that leaves the leave data as it was.
void refreshDocumentFeeds(WidgetRef ref) {
  ref.invalidate(documentsAwaitingMeProvider);
  ref.invalidate(sentDocumentsProvider);
}
