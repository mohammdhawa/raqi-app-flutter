import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/format.dart';
import '../../../../shared/widgets/card_kit.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../../attendance/domain/leave.dart';
import '../../../attendance/presentation/providers/leave_providers.dart';
import '../../domain/request_item.dart';
import '../providers/requests_providers.dart';

enum _Filter {
  all('الكل', null),
  pending('قيد الانتظار', RequestStatus.pending),
  approved('مقبولة', RequestStatus.approved),
  rejected('مرفوضة', RequestStatus.rejected);

  const _Filter(this.label, this.status);
  final String label;

  /// `null` keeps every status, cancelled included.
  final RequestStatus? status;
}

IconData _statusIcon(RequestStatus s) => switch (s) {
      RequestStatus.pending => Icons.schedule_rounded,
      RequestStatus.approved => Icons.check_rounded,
      RequestStatus.rejected => Icons.close_rounded,
      RequestStatus.cancelled => Icons.remove_rounded,
    };

/// The الطلبات tab: what I filed, and (for approvers) what waits on my
/// decision, with one gold action to file something new.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key, this.openInbox = false});

  /// Start on the «بانتظار قراري» segment. Ignored without approver rights.
  final bool openInbox;

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  late bool _inbox = widget.openInbox;
  _Filter _filter = _Filter.all;

  /// The tab branch keeps this state alive, so `/requests?seg=inbox` reached
  /// after the tab was first opened arrives here, not in a fresh state.
  @override
  void didUpdateWidget(covariant RequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openInbox && !oldWidget.openInbox) _inbox = true;
  }

  /// Leave controllers are refreshed here only; the approvals one is skipped
  /// for users who cannot review so they never trigger an approver request.
  Future<void> _refresh() async {
    final canReview = ref.read(canReviewRequestsProvider);
    ref.invalidate(sentDocumentsProvider);
    ref.invalidate(documentsAwaitingMeProvider);
    await Future.wait([
      ref.read(myLeaveRequestsProvider.notifier).refresh(),
      if (canReview) ref.read(leaveApprovalsProvider.notifier).refresh(),
    ]);
  }

  void _openNewRequestSheet(bool canReview) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppColors.rSheet)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('طلب جديد',
                  style: AppTheme.heading2(color: AppColors.text)),
              const SizedBox(height: 8),
              _SheetOption(
                icon: Icons.beach_access_rounded,
                label: 'إجازة',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/attendance/leave/new');
                },
              ),
              if (canReview)
                _SheetOption(
                  icon: Icons.description_rounded,
                  label: 'مستند من قالب',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/documents/new');
                  },
                ),
              const SizedBox(height: 8),
              Text('أنواع أخرى من الطلبات الإدارية ستتوفر قريباً.',
                  style: AppTheme.caption(color: AppColors.text2)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canReview = ref.watch(canReviewRequestsProvider);
    final showInbox = canReview && _inbox;
    final inboxCount = canReview ? ref.watch(pendingDecisionsCountProvider) : 0;
    final feed = ref.watch(showInbox ? inboxFeedProvider : myRequestsFeedProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewRequestSheet(canReview),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: Text('طلب جديد', style: AppTheme.labelL(color: AppColors.primary)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom room so the FAB never covers the last card.
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('الطلبات', style: AppTheme.heading1(color: AppColors.text)),
              const SizedBox(height: 12),
              if (canReview) ...[
                _SegmentedControl(
                  inbox: showInbox,
                  inboxCount: inboxCount,
                  onChanged: (v) => setState(() => _inbox = v),
                ),
                const SizedBox(height: 12),
              ],
              if (showInbox)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('طلبات تنتظر قرارك.',
                      style: AppTheme.bodyS(color: AppColors.text2)),
                )
              else ...[
                const _BalanceStrip(),
                const SizedBox(height: 12),
                _FilterChips(
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 12),
              ],
              CardSlot<List<RequestItem>>(
                value: feed,
                subject: 'الطلبات',
                onRetry: _refresh,
                builder: (items) {
                  final shown = showInbox || _filter.status == null
                      ? items
                      : [
                          for (final i in items)
                            if (i.status == _filter.status) i,
                        ];
                  if (shown.isEmpty) {
                    return _EmptyState(
                      message: showInbox
                          ? 'لا يوجد ما ينتظر قرارك'
                          : 'لا توجد طلبات بعد',
                    );
                  }
                  return Column(
                    children: [
                      for (final item in shown) ...[
                        _RequestCard(
                          item: item,
                          showRequester: showInbox,
                          onTap: () => context.push(item.route),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.inbox,
    required this.inboxCount,
    required this.onChanged,
  });

  final bool inbox;
  final int inboxCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              selected: !inbox,
              onTap: () => onChanged(false),
              children: const [Text('طلباتي')],
            ),
          ),
          Expanded(
            child: _Segment(
              selected: inbox,
              onTap: () => onChanged(true),
              children: [
                const Text('بانتظار قراري'),
                if (inboxCount > 0) Text(' (${isolateLtr('$inboxCount')})'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.onTap,
    required this.children,
  });

  final bool selected;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.label(
        color: selected ? AppColors.primary : AppColors.text2);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(AppColors.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.rMd),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: DefaultTextStyle(
                style: style,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceStrip extends ConsumerWidget {
  const _BalanceStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardSlot<LeaveBalance>(
      value: ref.watch(leaveBalanceProvider),
      subject: 'رصيد الإجازات',
      skeletonHeight: 48,
      onRetry: () => ref.invalidate(leaveBalanceProvider),
      builder: (b) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppColors.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('سنوية', style: AppTheme.caption(color: AppColors.text2)),
              const SizedBox(width: 8),
              Text('${isolateLtr('${b.remainingDays}')} يوماً',
                  style: AppTheme.label(color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final _Filter selected;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _Filter.values) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: f == selected,
                  onSelected: (_) => onChanged(f),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  labelStyle: AppTheme.caption(
                      color: f == selected ? Colors.white : AppColors.text),
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.showRequester,
    required this.onTap,
  });

  final RequestItem item;
  final bool showRequester;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final requester = showRequester ? item.requesterName : null;
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
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title,
                          style: AppTheme.label(color: AppColors.text)),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: item.status.label,
                      icon: _statusIcon(item.status),
                      fg: item.status.fg,
                      bg: item.status.bg,
                    ),
                  ],
                ),
                if (requester != null && requester.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(requester,
                      style: AppTheme.bodyS(color: AppColors.text)),
                ],
                const SizedBox(height: 4),
                Text(item.subtitle,
                    style: AppTheme.bodyS(color: AppColors.text2)),
                if (item.stepLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(item.stepLabel!,
                      style: AppTheme.caption(color: AppColors.text2)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(message, style: AppTheme.body(color: AppColors.text2)),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.rMd),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppTheme.label(color: AppColors.text)),
            ),
            const Icon(Icons.chevron_left_rounded,
                size: 22, color: AppColors.text2),
          ],
        ),
      ),
    );
  }
}
