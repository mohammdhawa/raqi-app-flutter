import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/documents_repository.dart';
import '../providers/documents_list_controller.dart';
import '../widgets/document_list_item.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../notifications/presentation/providers/notifications_controller.dart';

// All filter values in display order.
const _kStatusFilters = DocumentStatusFilter.values;

/// Visual metadata (icon + accent color) for each status filter chip.
extension _StatusFilterStyle on DocumentStatusFilter {
  IconData get icon => switch (this) {
    DocumentStatusFilter.all => Icons.apps_rounded,
    DocumentStatusFilter.pending => Icons.schedule_rounded,
    DocumentStatusFilter.approved => Icons.check_circle_rounded,
    DocumentStatusFilter.rejected => Icons.cancel_rounded,
  };

  Color get accent => switch (this) {
    DocumentStatusFilter.all => AppColors.primary,
    DocumentStatusFilter.pending => AppColors.pending,
    DocumentStatusFilter.approved => AppColors.approved,
    DocumentStatusFilter.rejected => AppColors.rejected,
  };

  Color get accentBg => switch (this) {
    DocumentStatusFilter.all => AppColors.surface2,
    DocumentStatusFilter.pending => AppColors.pendingBg,
    DocumentStatusFilter.approved => AppColors.approvedBg,
    DocumentStatusFilter.rejected => AppColors.rejectedBg,
  };
}

class DocumentsHomeScreen extends ConsumerStatefulWidget {
  const DocumentsHomeScreen({super.key});

  @override
  ConsumerState<DocumentsHomeScreen> createState() =>
      _DocumentsHomeScreenState();
}

class _DocumentsHomeScreenState extends ConsumerState<DocumentsHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'خروج',
              style: TextStyle(color: AppColors.rejected),
            ),
          ),
        ],
      ),
    );
    if (shouldLogout == true && mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final inboxState =
        ref.watch(documentsListProvider(DocumentListType.inbox));
    final sentState =
        ref.watch(documentsListProvider(DocumentListType.sent));
    final topPadding = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            // ── Custom AppBar ────────────────────────────────────────
            _AppBarSection(
              topPadding: topPadding,
              tabController: _tabController,
              user: user,
              inboxCount: inboxState.documents.length,
              sentCount: sentState.documents.length,
              onLogout: _confirmAndLogout,
            ),

            // ── Tab Content ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _DocumentsTab(type: DocumentListType.inbox),
                  _DocumentsTab(type: DocumentListType.sent),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/documents/new'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          icon: const Icon(Icons.add, color: AppColors.accent, size: 20),
          label: const Text(
            'مستند جديد',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  APP BAR
// ═══════════════════════════════════════════════════════════════════════

class _AppBarSection extends StatelessWidget {
  const _AppBarSection({
    required this.topPadding,
    required this.tabController,
    required this.user,
    required this.inboxCount,
    required this.sentCount,
    required this.onLogout,
  });

  final double topPadding;
  final TabController tabController;
  final dynamic user;
  final int inboxCount;
  final int sentCount;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Stack(
        children: [
          // Radial gold gradient highlight — bottom-right
          Positioned(
            bottom: 0,
            right: 0,
            width: 90,
            height: 90,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.7,
                  colors: [Color(0x2EC8A36B), Colors.transparent],
                ),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Top row: logo · title · icons ────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      // Trailing (left in RTL): icon buttons
                      _HeaderIconBtn(
                        icon: Icons.logout,
                        onTap: onLogout,
                      ),
                      const SizedBox(width: 8),
                      const _NotificationHeaderBtn(),
                      if (user != null && user.attendanceCheck) ...[
                        const SizedBox(width: 8),
                        _HeaderIconBtn(
                          icon: Icons.fingerprint_rounded,
                          onTap: () => context.push('/attendance'),
                        ),
                      ],

                      const Spacer(),

                      // Title (center)
                      Column(
                        children: [
                          const Text(
                            'المستندات',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (user != null)
                            Text(
                              '${user.name} · ${user.role}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textOnDark2,
                              ),
                            ),
                        ],
                      ),

                      const Spacer(),

                      // Leading (right in RTL): logo → tap to open About
                      GestureDetector(
                        onTap: () => context.push('/about'),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/logo-symbol-gold.png',
                              width: 26,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.assured_workload_outlined,
                                color: AppColors.accent,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Tab Bar ──────────────────────────────────────────
                _BadgeTabBar(
                  controller: tabController,
                  tabs: [
                    _BadgeTabData(label: 'الواردة', count: inboxCount),
                    _BadgeTabData(label: 'الصادرة', count: sentCount),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Notification bell button with an unread-count badge.
/// Uses [Consumer] so only this widget rebuilds when the count changes.
class _NotificationHeaderBtn extends ConsumerWidget {
  const _NotificationHeaderBtn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);

    return GestureDetector(
      onTap: () => context.push('/notifications'),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.rejected,
                    borderRadius: BorderRadius.circular(AppColors.pill),
                    border: Border.all(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TAB BAR WITH COUNT BADGES
// ═══════════════════════════════════════════════════════════════════════

class _BadgeTabData {
  const _BadgeTabData({required this.label, required this.count});
  final String label;
  final int count;
}

class _BadgeTabBar extends StatelessWidget {
  const _BadgeTabBar({required this.controller, required this.tabs});
  final TabController controller;
  final List<_BadgeTabData> tabs;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      indicator: UnderlineTabIndicator(
        borderSide: const BorderSide(width: 3, color: AppColors.accent),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(3),
        ),
        insets: const EdgeInsets.symmetric(horizontal: 6),
      ),
      tabs: List.generate(tabs.length, (i) {
        final data = tabs[i];
        final active = controller.index == i;
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.65),
                ),
              ),
              if (data.count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF2A2010)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppColors.pill),
                  ),
                  child: Text(
                    '${data.count}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.accent : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DOCUMENTS TAB (per-tab list)
// ═══════════════════════════════════════════════════════════════════════

class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.type});
  final DocumentListType type;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(documentsListProvider(widget.type).notifier).loadMore();
    }
  }

  void _onFilterChanged(DocumentStatusFilter filter) {
    ref
        .read(documentsListProvider(widget.type).notifier)
        .setStatusFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(documentsListProvider(widget.type));
    final user = ref.watch(currentUserProvider);
    final controller = ref.read(documentsListProvider(widget.type).notifier);

    return Column(
      children: [
        // ── Status filter chips ──────────────────────────────────────
        _StatusFilterBar(
          selected: state.statusFilter,
          onChanged: _onFilterChanged,
        ),

        // ── List ─────────────────────────────────────────────────────
        Expanded(
          child: _buildList(state, user, controller),
        ),
      ],
    );
  }

  Widget _buildList(
    DocumentsListState state,
    dynamic user,
    DocumentsListController controller,
  ) {
    if (state.isRefreshing && state.documents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.documents.isEmpty) {
      return ErrorStateView(
        failure: state.error!,
        onRetry: controller.refresh,
      );
    }

    if (state.isEmpty) {
      return _AlraqiEmptyState(
        icon: widget.type == DocumentListType.inbox
            ? Icons.inbox_outlined
            : Icons.send_outlined,
        title: widget.type == DocumentListType.inbox
            ? 'لا توجد مستندات واردة'
            : 'لم ترسل أي مستندات بعد',
        subtitle: widget.type == DocumentListType.inbox
            ? 'ستظهر هنا المستندات التي تنتظر مراجعتك أو اعتمادك.'
            : 'استخدم زر "مستند جديد" لإنشاء أول مستند.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: state.documents.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.documents.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final doc = state.documents[index];
          return AlraqiDocCard(
            document: doc,
            currentUser: user,
            onTap: () => context.push('/documents/${doc.id}'),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  STATUS FILTER BAR
// ═══════════════════════════════════════════════════════════════════════

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final DocumentStatusFilter selected;
  final ValueChanged<DocumentStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _kStatusFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final filter = _kStatusFilters[i];
          final isSelected = filter == selected;
          final accent = filter.accent;
          return GestureDetector(
            onTap: () => onChanged(filter),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? accent : filter.accentBg,
                borderRadius: BorderRadius.circular(AppColors.rMd),
                border: Border.all(
                  color: isSelected
                      ? accent
                      : accent.withValues(alpha: 0.20),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    filter.icon,
                    size: 16,
                    color: isSelected ? Colors.white : accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : accent,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════

class _AlraqiEmptyState extends StatelessWidget {
  const _AlraqiEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon circle
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: AppColors.text3, size: 30),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // Decorative gold bar
            Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}