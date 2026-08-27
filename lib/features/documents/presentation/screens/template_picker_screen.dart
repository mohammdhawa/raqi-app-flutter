import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/documents_repository.dart';
import '../../domain/document_template.dart';
import 'generated_document_form_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
//  TEMPLATE PICKER SCREEN
// ═══════════════════════════════════════════════════════════════════════

class TemplatePickerScreen extends ConsumerStatefulWidget {
  const TemplatePickerScreen({super.key});

  @override
  ConsumerState<TemplatePickerScreen> createState() =>
      _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends ConsumerState<TemplatePickerScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  List<DocumentTemplate> _templates = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _lastPage = 1;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadTemplates(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value != _searchQuery) {
        setState(() => _searchQuery = value);
        _loadTemplates(reset: true);
      }
    });
  }

  Future<void> _loadTemplates({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _templates = [];
        _currentPage = 1;
        _lastPage = 1;
      });
    }
    try {
      final repo = ref.read(documentsRepositoryProvider);
      final result = await repo.fetchTemplates(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: _currentPage,
      );
      if (!mounted) return;
      setState(() {
        _templates =
            reset ? result.templates : [..._templates, ...result.templates];
        _currentPage = result.currentPage;
        _lastPage = result.lastPage;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل القوالب. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || _currentPage >= _lastPage) return;
    setState(() => _isLoadingMore = true);
    try {
      final repo = ref.read(documentsRepositoryProvider);
      final result = await repo.fetchTemplates(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: _currentPage + 1,
      );
      if (!mounted) return;
      setState(() {
        _templates = [..._templates, ...result.templates];
        _currentPage = result.currentPage;
        _lastPage = result.lastPage;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onTemplateTap(DocumentTemplate template) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GeneratedDocumentFormScreen(template: template),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildAppBar(context),
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: const BoxDecoration(color: AppColors.primary),
      child: Stack(
        children: [
          Positioned(
            bottom: -20,
            right: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x2EC8A36B), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'اختر قالب المستند',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ابدأ بتحديد نوع المستند المطلوب',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
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
                    child: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'ابحث عن قالب...',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.text3),
            prefixIcon:
                const Icon(Icons.search, size: 20, color: AppColors.text3),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.text3,
                    ),
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 48, color: AppColors.text3),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text2, fontSize: 14),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _loadTemplates(reset: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _searchQuery.isNotEmpty
                    ? Icons.search_off_outlined
                    : Icons.description_outlined,
                size: 48,
                color: AppColors.text3,
              ),
              const SizedBox(height: 12),
              // An empty list is NOT necessarily "no templates exist". With
              // `generation_enabled` off the backend serves an empty template
              // listing on purpose, so the feature being unavailable and the
              // department having no templates look identical from here —
              // say both rather than implying someone forgot to add one.
              Text(
                _searchQuery.isNotEmpty
                    ? 'لا توجد نتائج لـ "$_searchQuery"'
                    : 'لا توجد قوالب متاحة حالياً، أو أن إنشاء المستندات من '
                        'القوالب متوقف مؤقتاً.\nيمكنك إنشاء مستند برفع ملف.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text2,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadTemplates(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        itemCount: _templates.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _templates.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _TemplateCard(
            template: _templates[index],
            onTap: () => _onTemplateTap(_templates[index]),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TEMPLATE CARD
// ═══════════════════════════════════════════════════════════════════════

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final DocumentTemplate template;
  final VoidCallback onTap;

  IconData get _icon => switch (template.type) {
        'purchase_request' => Icons.shopping_cart_outlined,
        'leave_request' => Icons.beach_access_outlined,
        'internal_memo' => Icons.mail_outlined,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A1B2A41),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (template.description != null &&
                        template.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        template.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.widgets_outlined,
                            size: 12, color: AppColors.text3),
                        const SizedBox(width: 4),
                        Text(
                          '${template.fieldsSchema.length} حقل',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: AppColors.text3,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
