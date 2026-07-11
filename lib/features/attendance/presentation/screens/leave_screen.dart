import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/leave_request_tile.dart';

/// Leave hub: the authenticated user's own requests plus, for managers, the
/// requests assigned to them for approval. Reached from the attendance
/// screen and from leave notifications.
class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key, this.initialTab = 0});

  /// 0 = my requests, 1 = approvals.
  final int initialTab;

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final user = ref.read(currentUserProvider);
    final isManager = user?.isManager ?? false;
    if (isManager && widget.initialTab == 1) {
      _tabController.index = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isManager = user?.isManager ?? false;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _Header(
            topPadding: topPadding,
            tabController: isManager ? _tabController : null,
          ),
          Expanded(
            child: isManager
                ? TabBarView(
                    controller: _tabController,
                    children: const [
                      _MyRequestsTab(),
                      _ApprovalsTab(),
                    ],
                  )
                : const _MyRequestsTab(),
          ),
        ],
      ),
      // Anyone may submit a leave request; the backend authorizes by role.
      // (The approvals tab above stays manager-only.)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/attendance/leave/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('طلب إجازة'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  HEADER
// ═══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({required this.topPadding, this.tabController});

  final double topPadding;
  final TabController? tabController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.primary),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, topPadding + 10, 12, 12),
            child: Row(
              children: [
                const Spacer(),
                const Text(
                  'إدارة الإجازات',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chevron_right,
                        color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
          if (tabController != null)
            TabBar(
              controller: tabController,
              tabs: const [
                Tab(text: 'طلباتي'),
                Tab(text: 'بانتظار موافقتي'),
              ],
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  MY REQUESTS TAB
// ═══════════════════════════════════════════════════════════════════════

class _MyRequestsTab extends ConsumerWidget {
  const _MyRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myLeaveRequestsProvider);
    final notifier = ref.read(myLeaveRequestsProvider.notifier);

    return Column(
      children: [
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LeaveBalanceCard(),
        ),
        _FilterChips(
          selected: state.statusFilter,
          onChanged: notifier.setStatusFilter,
        ),
        Expanded(
          child: _LeaveListBody(
            state: state,
            showRequester: false,
            emptyText: 'لا توجد طلبات إجازة.',
            onRefresh: notifier.refresh,
            onRetry: notifier.load,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  APPROVALS TAB
// ═══════════════════════════════════════════════════════════════════════

class _ApprovalsTab extends ConsumerWidget {
  const _ApprovalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leaveApprovalsProvider);
    final notifier = ref.read(leaveApprovalsProvider.notifier);

    return Column(
      children: [
        _FilterChips(
          selected: state.statusFilter,
          onChanged: notifier.setStatusFilter,
        ),
        Expanded(
          child: _LeaveListBody(
            state: state,
            showRequester: true,
            emptyText: 'لا توجد طلبات بانتظار موافقتك.',
            onRefresh: notifier.refresh,
            onRetry: notifier.load,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SHARED — filter chips + list body
// ═══════════════════════════════════════════════════════════════════════

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});

  final LeaveStatusFilter selected;
  final ValueChanged<LeaveStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final filter in LeaveStatusFilter.values) ...[
            _Chip(
              label: filter.arabicLabel,
              isSelected: filter == selected,
              onTap: () => onChanged(filter),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.pill),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ).copyWith(
              color: isSelected ? Colors.white : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaveListBody extends StatelessWidget {
  const _LeaveListBody({
    required this.state,
    required this.showRequester,
    required this.emptyText,
    required this.onRefresh,
    required this.onRetry,
  });

  final LeaveListState state;
  final bool showRequester;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.requests.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (state.error != null && state.requests.isEmpty) {
      return _ErrorBody(failure: state.error!, onRetry: onRetry);
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: state.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                _EmptyBody(text: emptyText),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
              itemCount: state.requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final r = state.requests[index];
                return LeaveRequestTile(
                  request: r,
                  showRequester: showRequester,
                  onTap: () =>
                      context.push('/attendance/leave/requests/${r.id}'),
                );
              },
            ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.beach_access_outlined,
                size: 34, color: AppColors.text3),
          ),
          const SizedBox(height: 14),
          Text(text, style: AppTheme.label(color: AppColors.text2)),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.failure, required this.onRetry});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              arabicMessageFor(failure.code, fallback: failure.message),
              textAlign: TextAlign.center,
              style: AppTheme.body(color: AppColors.text2),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
