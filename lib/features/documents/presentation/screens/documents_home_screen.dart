import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/documents_repository.dart';
import '../providers/documents_list_controller.dart';
import '../widgets/document_list_item.dart';
import '../../../../shared/widgets/state_views.dart';

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
              style: TextStyle(color: AppColors.statusRejected),
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('المستندات'),
            if (user != null)
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: _confirmAndLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الواردة'),
            Tab(text: 'الصادرة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _DocumentsTab(type: DocumentListType.inbox),
          _DocumentsTab(type: DocumentListType.sent),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/documents/new'),
        icon: const Icon(Icons.add),
        label: const Text('مستند جديد'),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(documentsListProvider(widget.type));
    final user = ref.watch(currentUserProvider);
    final controller = ref.read(documentsListProvider(widget.type).notifier);

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
      return EmptyStateView(
        icon: widget.type == DocumentListType.inbox
            ? Icons.inbox_outlined
            : Icons.send_outlined,
        title: widget.type == DocumentListType.inbox
            ? 'لا توجد مستندات واردة'
            : 'لم ترسل أي مستندات بعد',
        subtitle: widget.type == DocumentListType.inbox
            ? 'ستظهر هنا المستندات التي تحتاج إلى اعتمادك.'
            : 'استخدم زر "مستند جديد" لإنشاء أول مستند.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: state.documents.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= state.documents.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final doc = state.documents[index];
          return DocumentListItem(
            document: doc,
            currentUser: user,
            onTap: () => context.push('/documents/${doc.id}'),
          );
        },
      ),
    );
  }
}