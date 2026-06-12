import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_constants.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';
import '../providers/document_comments_controller.dart';
import '../providers/document_details_controller.dart';
import '../providers/documents_list_controller.dart';
import '../widgets/document_comments_section.dart';
import '../widgets/workflow_stepper.dart';
import '../../../../core/storage/token_storage.dart';

// ============================================================================
// ROOT-CAUSE FIX for: '_dependents.isEmpty': is not true (framework.dart:6268)
//
// The previous version did this inside onApprove/onReject:
//
//   final updated = await controller.approve(note: note);
//   if (!context.mounted) return;
//   if (updated != null) {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       for (final type in DocumentListType.values) {
//         if (ref.exists(documentsListProvider(type))) {
//           ref.read(documentsListProvider(type).notifier)
//              .replaceDocument(updated);
//         }
//       }
//     });
//     ScaffoldMessenger.of(context).showSnackBar(...);   // <-- and this
//   }
//
// Why that triggered '_dependents.isEmpty':
//   1. `controller.approve()` finishes and synchronously sets
//      `state = DocumentDetailsState(document: updated)` — Riverpod marks
//      every widget that watches this provider dirty for the NEXT frame.
//   2. We are now back in the await-completion microtask. The widget tree
//      hasn't rebuilt yet, but it WILL during the next frame.
//   3. addPostFrameCallback queues a callback for AFTER that next frame
//      finishes drawing — i.e. during the _InactiveElements processing
//      pass at the tail of the frame.
//   4. Inside that post-frame callback we then mutate documentsListProvider
//      for BOTH tabs. Those tabs are kept alive (AutomaticKeepAliveClient
//      Mixin) underneath the navigator, so their state notifier listeners
//      fire and they get marked dirty MID-DEACTIVATION.
//   5. ScaffoldMessenger.showSnackBar inserts an OverlayEntry into the
//      MaterialApp's Overlay — also at exactly this fragile moment.
//   6. Result: an InheritedElement (Scaffold's own, ScaffoldMessenger's,
//      or Overlay's) gets deactivated while widgets are still registered
//      against it as dependents. That's the exact precondition for
//      InheritedElement.debugDeactivated's `assert(_dependents.isEmpty)`.
//
// What this rewrite changes:
//   * Approve/reject are State methods, not build-scope closures.
//   * After the await, the cross-provider replaceDocument call runs
//     SYNCHRONOUSLY in the await-completion microtask — i.e. BEFORE the
//     next frame, not after. All affected providers are mutated together,
//     and the next frame's rebuild pass processes them coherently.
//   * The SnackBar is the ONLY thing deferred to addPostFrameCallback —
//     it's safe there because by then the rebuild has already run, and
//     showing a SnackBar after a settled frame is a normal pattern.
//   * _ActionBar always returns a Visibility-wrapped widget of the same
//     shape regardless of state, instead of flipping between
//     SizedBox.shrink and a full SafeArea>Container subtree. This kills
//     the most common element-deactivation race.
//   * The nested ListView.separated inside _LogsSection is replaced with
//     a plain Column, removing one source of nested-scrollable surprises.
// ============================================================================

class DocumentDetailsScreen extends ConsumerStatefulWidget {
  const DocumentDetailsScreen({super.key, required this.documentId});

  final int documentId;

  @override
  ConsumerState<DocumentDetailsScreen> createState() =>
      _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState
    extends ConsumerState<DocumentDetailsScreen> {
  int get documentId => widget.documentId;

  // ── Delete ────────────────────────────────────────────────────────────────

  bool _canDelete(Document? doc, dynamic user) {
    if (doc == null || user == null) return false;
    if (doc.status != DocumentStatus.pending) return false;
    if (doc.creator.id != user.id) return false;
    return doc.workflows.every((s) => s.status == WorkflowStepStatus.pending);
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'حذف المستند',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'هل تريد حذف هذا المستند؟ لا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(fontSize: 13, color: AppColors.text2),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.rSm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rejected,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.rSm),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = ref.read(documentDetailsProvider(documentId).notifier);
    final success = await controller.delete();
    if (!mounted) return;

    if (success) {
      _removeFromLists(documentId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الوثيقة بنجاح.')),
      );
      Navigator.maybePop(context);
    } else {
      _scheduleErrorSnack();
    }
  }

  void _removeFromLists(int id) {
    for (final type in DocumentListType.values) {
      if (ref.exists(documentsListProvider(type))) {
        ref.read(documentsListProvider(type).notifier).removeDocument(id);
      }
    }
  }

  // ── Approve / Reject ─────────────────────────────────────────────────────

  Future<void> _approve(String? note) async {
    final controller = ref.read(documentDetailsProvider(documentId).notifier);
    final updated = await controller.approve(note: note);
    if (!mounted) return;
    if (updated != null) {
      _propagateToLists(updated);
      _scheduleSnack('تم اعتماد المستند.');
    } else {
      _scheduleErrorSnack();
    }
  }

  Future<void> _reject(String? note) async {
    final controller = ref.read(documentDetailsProvider(documentId).notifier);
    final updated = await controller.reject(note: note);
    if (!mounted) return;
    if (updated != null) {
      _propagateToLists(updated);
      _scheduleSnack('تم رفض المستند.');
    } else {
      _scheduleErrorSnack();
    }
  }

  void _propagateToLists(Document updated) {
    for (final type in DocumentListType.values) {
      final exists = ref.exists(documentsListProvider(type));
      if (exists) {
        ref
            .read(documentsListProvider(type).notifier)
            .replaceDocument(updated);
      }
    }
  }

  void _scheduleSnack(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  void _scheduleErrorSnack() {
    final failure = ref.read(documentDetailsProvider(documentId)).error;
    if (failure == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.statusRejected,
          content: Text(
            arabicMessageFor(failure.code, fallback: failure.message),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentDetailsProvider(documentId));
    final user = ref.watch(currentUserProvider);
    final controller =
        ref.read(documentDetailsProvider(documentId).notifier);

    final doc = state.document;
    final statusLabel = doc != null ? _statusLabel(doc.status) : '';
    final canDelete = _canDelete(doc, user);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: AppColors.textOnDark,
                size: 22,
              ),
            ),
          ),
        ),
        title: Column(
          children: [
            const Text(
              'تفاصيل المستند',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnDark,
              ),
            ),
            if (doc != null)
              Text(
                '${doc.documentNumber ?? "DOC-${doc.id}"} · $statusLabel',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
          ],
        ),
        actions: [
          if (state.isDeleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'حذف المستند',
              onPressed: _confirmAndDelete,
            ),
        ],
      ),
      body: _DetailsBody(
        state: state,
        onRefresh: controller.load,
        documentId: documentId,
      ),
      bottomNavigationBar: _ActionBar(
        document: state.document,
        currentUser: user,
        isActing: state.isActing,
        onApprove: _approve,
        onReject: _reject,
      ),
    );
  }

  String _statusLabel(DocumentStatus status) {
    return switch (status) {
      DocumentStatus.pending => 'قيد الانتظار',
      DocumentStatus.approved => 'معتمد',
      DocumentStatus.rejected => 'مرفوض',
      _ => '',
    };
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _DetailsBody extends StatefulWidget {
  const _DetailsBody({
    required this.state,
    required this.onRefresh,
    required this.documentId,
  });

  final DocumentDetailsState state;
  final Future<void> Function() onRefresh;
  final int documentId;

  @override
  State<_DetailsBody> createState() => _DetailsBodyState();
}

class _DetailsBodyState extends State<_DetailsBody> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.isLoading && widget.state.document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.state.error != null && widget.state.document == null) {
      return ErrorStateView(
          failure: widget.state.error!, onRetry: widget.onRefresh);
    }
    final doc = widget.state.document;
    if (doc == null) {
      return const SizedBox.shrink();
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: widget.onRefresh,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(document: doc),
          const SizedBox(height: 16),
          _FilePreviewCard(document: doc),
          if (doc.stampedFilePath != null) ...[
            const SizedBox(height: 12),
            _StampedPdfCard(document: doc),
          ],
          const SizedBox(height: 16),
          _WorkflowCard(document: doc),
          const SizedBox(height: 16),
          _LogsCard(logs: doc.logs),
          const SizedBox(height: 16),
          DocumentCommentsSection(
            documentId: widget.documentId,
            onScrollToBottom: _scrollToBottom,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context) {
    final modeLabel = document.workflowMode == WorkflowMode.sequential
        ? 'اعتماد تسلسلي'
        : 'اعتماد متوازي';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryGrad],
          begin: Alignment(-0.7, -0.4),
          end: Alignment(0.9, 0.6),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Decorative radial glow bottom-right
          Positioned(
            bottom: -30,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFC8A36B).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Decorative ring top-left
          Positioned(
            top: -20,
            left: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFC8A36B).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: code + mode + status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${document.documentNumber ?? "DOC-${document.id}"}  $modeLabel',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.70),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  StatusChip(status: document.status),
                ],
              ),
              const SizedBox(height: 10),
              // Title
              Text(
                document.title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textOnDark,
                  height: 1.4,
                ),
              ),
              // Description
              if (document.description != null &&
                  document.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  document.description!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.90),
                    height: 1.7,
                  ),
                ),
              ],
              // Divider
              const SizedBox(height: 10),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 10),
              // Meta row
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    document.creator.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('yyyy/MM/dd · HH:mm').format(document.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                ],
              ),
              // Numbers row — export always, import only when non-null
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.outbox_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'الصادر: ${document.exportNumber?.toString() ?? '-'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  if (document.importNumber != null) ...[
                    const SizedBox(width: 14),
                    Icon(
                      Icons.move_to_inbox_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'الوارد: ${document.importNumber}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.90),
                      ),
                    ),
                  ],
                ],
              ),
              // Origin badge — shown for generated documents
              if (document.isGenerated) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppColors.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_outlined,
                          size: 12, color: AppColors.accent),
                      const SizedBox(width: 5),
                      Text(
                        'إنشاء من قالب: ${document.templateName ?? "غير معروف"}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File preview card
// ---------------------------------------------------------------------------

class _FilePreviewCard extends ConsumerStatefulWidget {
  const _FilePreviewCard({required this.document});
  final Document document;

  @override
  ConsumerState<_FilePreviewCard> createState() => _FilePreviewCardState();
}

class _FilePreviewCardState extends ConsumerState<_FilePreviewCard> {
  String? get _fileUrl {
    final path = widget.document.filePath;
    if (path == null) return null;
    return '${AppConstants.storageBase}/storage/$path';
  }

  bool get _isPdf {
    final mime = widget.document.fileMime ?? '';
    if (mime.isNotEmpty) return mime == 'application/pdf';
    return (widget.document.filePath ?? '').toLowerCase().endsWith('.pdf');
  }

  bool get _isImage {
    final mime = widget.document.fileMime ?? '';
    if (mime.isNotEmpty) return mime.startsWith('image/');
    final ext = (widget.document.filePath ?? '').toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  Future<void> _openPreview() async {
    final url = _fileUrl;
    if (url == null) return;

    if (_isPdf) {
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.read();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _PdfPreviewDialog(
          url: url,
          fileName: widget.document.fileName ?? url.split('/').last,
          token: token,
        ),
      );
    } else if (_isImage) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _ImagePreviewDialog(
          url: url,
          fileName: widget.document.fileName ?? url.split('/').last,
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('معاينة هذا النوع من الملفات غير مدعومة.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final url = _fileUrl;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Image thumbnail
          if (_isImage && url != null)
            GestureDetector(
              onTap: _openPreview,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-0.6, -0.6),
                            end: Alignment(0.8, 0.8),
                            colors: [
                              Color(0xFFF4EFE3),
                              Color(0xFFE7DDC5),
                              Color(0xFFD7C7A1),
                            ],
                          ),
                        ),
                      ),
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: AppColors.text3,
                          ),
                        ),
                      ),
                      // Preview badge bottom-left
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1828)
                                .withValues(alpha: 0.75),
                            borderRadius:
                                BorderRadius.circular(AppColors.pill),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('معاينة',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Footer row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // File type icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isPdf
                        ? AppColors.rejectedBg
                        : AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: _isPdf
                      ? const Text(
                          'PDF',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.rejected,
                            letterSpacing: 0.5,
                          ),
                        )
                      : Icon(
                          _isImage
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.fileName ?? 'ملف مرفق',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatMeta(doc),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                // Eye button
                if (url != null)
                  GestureDetector(
                    onTap: _openPreview,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.visibility_outlined,
                        color: AppColors.text2,
                        size: 18,
                      ),
                    ),
                  ),
                if (url != null)
                  _FileActionButtons(
                    url: url,
                    fileName: doc.fileName ?? url.split('/').last,
                    requiresAuth: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMeta(Document doc) {
    return _formatSize(doc.fileSize);
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ---------------------------------------------------------------------------
// Image preview
// ---------------------------------------------------------------------------

class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({required this.url, required this.fileName});
  final String url;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black87),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDF preview
// ---------------------------------------------------------------------------

class _PdfPreviewDialog extends StatelessWidget {
  const _PdfPreviewDialog({
    required this.url,
    required this.fileName,
    this.token,
  });
  final String url;
  final String fileName;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final headers = <String, String>{
      'Accept': 'application/pdf',
      if (token != null && token!.isNotEmpty)
        'Authorization': 'Bearer $token',
    };

    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.black87,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SfPdfViewer.network(
                url,
                headers: headers,
                canShowScrollHead: true,
                canShowScrollStatus: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stamped PDF card
// ---------------------------------------------------------------------------

class _StampedPdfCard extends ConsumerWidget {
  const _StampedPdfCard({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFinal = document.status == DocumentStatus.approved;
    final url =
        '${AppConstants.storageBase}/api/documents/${document.id}/stamped-pdf';
    final fileName = isFinal
        ? '${document.title} (معتمد).pdf'
        : '${document.title} (قيد المراجعة).pdf';

    return GestureDetector(
      onTap: () async {
        final storage = ref.read(tokenStorageProvider);
        final token = await storage.read();
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          builder: (_) => _PdfPreviewDialog(
            url: url,
            fileName: fileName,
            token: token,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent, width: 1.5),
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.05),
              AppColors.accent.withValues(alpha: 0.02),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified,
                color: AppColors.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'النسخة المختومة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isFinal ? 'النسخة النهائية المعتمدة' : 'قيد المراجعة — نسخة مؤقتة',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                final storage = ref.read(tokenStorageProvider);
                final token = await storage.read();
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  barrierColor: Colors.black87,
                  builder: (_) => _PdfPreviewDialog(
                    url: url,
                    fileName: fileName,
                    token: token,
                  ),
                );
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
            ),
            _FileActionButtons(
              url: url,
              fileName: fileName,
              requiresAuth: true,
              accentColor: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Workflow card
// ---------------------------------------------------------------------------

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context) {
    final isSequential = document.workflowMode == WorkflowMode.sequential;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: isSequential
                ? Icons.format_list_numbered
                : Icons.group_outlined,
            title: isSequential
                ? 'سير الاعتماد التسلسلي'
                : 'سير الاعتماد المتوازي',
          ),
          const SizedBox(height: 14),
          WorkflowStepper(
            steps: document.workflows,
            isSequential: isSequential,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Logs card
// ---------------------------------------------------------------------------

class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.logs});
  final List<DocumentLog> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.history,
            title: 'سجل النشاط',
          ),
          const SizedBox(height: 14),
          if (logs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(
                child: Text(
                  'لا توجد سجلات بعد.',
                  style: TextStyle(color: AppColors.text2),
                ),
              ),
            )
          else
            _LogsList(logs: logs),
        ],
      ),
    );
  }
}

class _LogsList extends StatelessWidget {
  const _LogsList({required this.logs});
  final List<DocumentLog> logs;

  @override
  Widget build(BuildContext context) {
    final sorted = [...logs]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          _LogTile(key: ValueKey(sorted[i].id), log: sorted[i]),
          if (i < sorted.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const dashWidth = 4.0;
                  const dashSpace = 3.0;
                  final count =
                      (constraints.maxWidth / (dashWidth + dashSpace)).floor();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(count, (_) {
                      return SizedBox(
                        width: dashWidth + dashSpace,
                        height: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.border,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: dashSpace),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({super.key, required this.log});
  final DocumentLog log;

  @override
  Widget build(BuildContext context) {
    final (icon, bgColor, fgColor, label) = switch (log.action) {
      LogAction.created => (
        Icons.note_add_outlined,
        AppColors.primary.withValues(alpha: 0.10),
        AppColors.primary,
        'تم إنشاء المستند',
      ),
      LogAction.sent => (
        Icons.send_outlined,
        AppColors.accent.withValues(alpha: 0.12),
        AppColors.pendingText,
        'تم إرسال المستند للاعتماد',
      ),
      LogAction.approved => (
        Icons.check_circle_outline,
        AppColors.approvedBg,
        AppColors.approved,
        'اعتمد المستند',
      ),
      LogAction.rejected => (
        Icons.cancel_outlined,
        AppColors.rejectedBg,
        AppColors.rejected,
        'رفض المستند',
      ),
      _ => (
        Icons.info_outline,
        AppColors.primary.withValues(alpha: 0.10),
        AppColors.text2,
        'حدث',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fgColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.user.name} — $label',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('yyyy/MM/dd · HH:mm').format(log.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                ),
                if (log.note != null && log.note!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        right: BorderSide(
                          color: AppColors.accent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      log.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File action buttons (download + share)
// ---------------------------------------------------------------------------

class _FileActionButtons extends ConsumerStatefulWidget {
  const _FileActionButtons({
    required this.url,
    required this.fileName,
    this.requiresAuth = false,
    this.accentColor,
  });

  final String url;
  final String fileName;
  final bool requiresAuth;
  final Color? accentColor;

  @override
  ConsumerState<_FileActionButtons> createState() => _FileActionButtonsState();
}

class _FileActionButtonsState extends ConsumerState<_FileActionButtons> {
  bool _isDownloading = false;
  bool _isSharing = false;

  bool get _busy => _isDownloading || _isSharing;

  Future<String?> _fetchToTemp() async {
    String? token;
    if (widget.requiresAuth) {
      token = await ref.read(tokenStorageProvider).read();
    }
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${widget.fileName}';
      await Dio().download(
        widget.url,
        filePath,
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );
      return filePath;
    } catch (_) {
      return null;
    }
  }

  void _showError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('فشل التنزيل. حاول مرة أخرى.')),
    );
  }

  Future<void> _onDownload() async {
    if (_busy) return;
    setState(() => _isDownloading = true);
    final path = await _fetchToTemp();
    if (!mounted) return;
    setState(() => _isDownloading = false);
    if (path != null) {
      OpenFilex.open(path);
    } else {
      _showError();
    }
  }

  Future<void> _onShare() async {
    if (_busy) return;
    setState(() => _isSharing = true);
    final path = await _fetchToTemp();
    if (!mounted) return;
    setState(() => _isSharing = false);
    if (path != null) {
      await Share.shareXFiles([XFile(path)]);
    } else {
      _showError();
    }
  }

  Widget _btn({
    required IconData icon,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final color = widget.accentColor ?? AppColors.text2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: widget.accentColor != null
              ? Border.all(color: widget.accentColor!)
              : null,
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            : Icon(icon, color: color, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 6),
        _btn(
          icon: Icons.download_outlined,
          onTap: _busy ? null : _onDownload,
          loading: _isDownloading,
        ),
        const SizedBox(width: 6),
        _btn(
          icon: Icons.share_outlined,
          onTap: _busy ? null : _onShare,
          loading: _isSharing,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

class _ActionBar extends StatefulWidget {
  const _ActionBar({
    required this.document,
    required this.currentUser,
    required this.isActing,
    required this.onApprove,
    required this.onReject,
  });

  final Document? document;
  final dynamic currentUser;
  final bool isActing;
  final Future<void> Function(String? note) onApprove;
  final Future<void> Function(String? note) onReject;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  @override
  Widget build(BuildContext context) {
    final canAct = widget.document != null &&
        widget.document!.isTurnOf(widget.currentUser);

    return Visibility(
      visible: canAct,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.border)),
            boxShadow: AppColors.shActionBar,
          ),
          child: Row(
            children: [
              // Reject button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rejected,
                      side: const BorderSide(
                        color: AppColors.rejected,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.rMd),
                      ),
                    ),
                    onPressed: widget.isActing
                        ? null
                        : () => _promptForNote(
                              context,
                              title: 'تأكيد الرفض',
                              confirmLabel: 'رفض',
                              confirmColor: AppColors.rejected,
                              isNoteRequired: true,
                              onConfirm: widget.onReject,
                            ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('رفض'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Approve button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.approved,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.rMd),
                      ),
                      elevation: 0,
                    ),
                    onPressed: widget.isActing
                        ? null
                        : () => _promptForNote(
                              context,
                              title: 'تأكيد الاعتماد',
                              confirmLabel: 'اعتماد',
                              confirmColor: AppColors.approved,
                              isNoteRequired: false,
                              onConfirm: widget.onApprove,
                            ),
                    icon: SizedBox(
                      width: 18,
                      height: 18,
                      child: widget.isActing
                          ? const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textOnDark,
                            )
                          : const Icon(Icons.check, size: 18),
                    ),
                    label: const Text('اعتماد'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptForNote(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Color confirmColor,
    required bool isNoteRequired,
    required Future<void> Function(String? note) onConfirm,
  }) async {
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) => _NotePromptDialog(
        title: title,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        isNoteRequired: isNoteRequired,
      ),
    );

    if (note == null) return;
    await onConfirm(note.isEmpty ? null : note);
  }
}

// ---------------------------------------------------------------------------
// Note prompt dialog
// ---------------------------------------------------------------------------

class _NotePromptDialog extends StatefulWidget {
  const _NotePromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.confirmColor,
    required this.isNoteRequired,
  });

  final String title;
  final String confirmLabel;
  final Color confirmColor;
  final bool isNoteRequired;

  @override
  State<_NotePromptDialog> createState() => _NotePromptDialogState();
}

class _NotePromptDialogState extends State<_NotePromptDialog> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final now = _controller.text.trim().isNotEmpty;
      if (now != _hasText) setState(() => _hasText = now);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = !widget.isNoteRequired || _hasText;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.all(20),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: widget.isNoteRequired
                  ? 'سبب الرفض — مطلوب'
                  : 'أضف ملاحظة (اختياري)',
              hintStyle: const TextStyle(
                color: AppColors.text3,
                fontSize: 13,
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppColors.rMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppColors.rMd),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppColors.rMd),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
      actions: [
        // Cancel
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text2,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.rSm),
            ),
          ),
          onPressed: () => Navigator.pop(context, null),
          child: const Text('إلغاء'),
        ),
        // Confirm
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.rSm),
            ),
            elevation: 0,
          ),
          onPressed: canConfirm
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Comments card
// ---------------------------------------------------------------------------

class _CommentsCard extends ConsumerStatefulWidget {
  const _CommentsCard({required this.documentId});
  final int documentId;

  @override
  ConsumerState<_CommentsCard> createState() => _CommentsCardState();
}

class _CommentsCardState extends ConsumerState<_CommentsCard> {
  final _textController = TextEditingController();
  String _visibility = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(documentCommentsProvider(widget.documentId).notifier)
          .load();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final result = await ref
        .read(documentCommentsProvider(widget.documentId).notifier)
        .addComment(comment: text, visibility: _visibility);
    if (!mounted) return;
    if (result != null) {
      _textController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء إرسال التعليق.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentCommentsProvider(widget.documentId));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.chat_bubble_outline,
            title: 'التعليقات',
          ),
          const SizedBox(height: 14),
          // List
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد تعليقات بعد.',
                  style: TextStyle(color: AppColors.text2),
                ),
              ),
            )
          else
            ...state.comments.map((c) => _CommentTile(comment: c)),
          const Divider(color: AppColors.border, height: 24),
          // Visibility selector
          Row(
            children: [
              const Text(
                'الظهور:',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
              const SizedBox(width: 8),
              _VisibilityDropdown(
                value: _visibility,
                onChanged: (v) => setState(() => _visibility = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  maxLines: 4,
                  minLines: 1,
                  enabled: !state.isPosting,
                  decoration: InputDecoration(
                    hintText: 'أضف تعليقاً...',
                    hintStyle: const TextStyle(
                      color: AppColors.text3,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.rMd),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.rMd),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppColors.rMd),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppColors.rMd),
                    ),
                    padding: EdgeInsets.zero,
                    elevation: 0,
                  ),
                  onPressed: state.isPosting ? null : _submit,
                  child: state.isPosting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comment tile
// ---------------------------------------------------------------------------

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final DocumentComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              _initials(comment.user.name),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.user.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.comment,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
                if (comment.visibility == 'approvers') ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppColors.pill),
                    ),
                    child: const Text(
                      'للمعتمدين فقط',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.pendingText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final buf = StringBuffer();
    for (final p in parts.take(2)) {
      if (p.isNotEmpty) buf.write(p[0]);
    }
    final s = buf.toString();
    return s.isEmpty ? '؟' : s;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'منذ لحظات';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'منذ $m ${m == 1 ? "دقيقة" : "دقائق"}';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'منذ $h ${h == 1 ? "ساعة" : "ساعات"}';
    }
    if (diff.inDays < 30) {
      final d = diff.inDays;
      return 'منذ $d ${d == 1 ? "يوم" : "أيام"}';
    }
    return DateFormat('yyyy/MM/dd').format(dt);
  }
}

// ---------------------------------------------------------------------------
// Visibility dropdown
// ---------------------------------------------------------------------------

class _VisibilityDropdown extends StatelessWidget {
  const _VisibilityDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.rSm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.text,
            fontFamily: 'Cairo',
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('الكل')),
            DropdownMenuItem(
                value: 'approvers', child: Text('المعتمدون فقط')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}