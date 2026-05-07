import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import '../providers/document_details_controller.dart';
import '../providers/documents_list_controller.dart';
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

  // ── Approve / Reject ─────────────────────────────────────────────────────
  // Defined as State methods (not build-scope closures) so they aren't
  // recreated on every rebuild and don't capture stale ref/context.

  Future<void> _approve(String? note) async {
    final controller = ref.read(documentDetailsProvider(documentId).notifier);
    final updated = await controller.approve(note: note);
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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

    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المستند')),
      body: _DetailsBody(
        state: state,
        onRefresh: controller.load,
      ),
      bottomNavigationBar: _ActionBar(
        document: state.document,
        currentUser: user,
        isActing: state.isActing,
        onApprove: _approve,
        onReject: _reject,
      ),
    );
    return scaffold;
  }
}

// ---------------------------------------------------------------------------
// Body — extracted so loading/error/data branches each return the SAME root
// widget type (so element identity is preserved across rebuilds where
// possible).
// ---------------------------------------------------------------------------

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.state, required this.onRefresh});

  final DocumentDetailsState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.document == null) {
      return ErrorStateView(failure: state.error!, onRetry: onRefresh);
    }
    final doc = state.document;
    if (doc == null) {
      return const SizedBox.shrink();
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(document: doc),
          const SizedBox(height: 16),
          _FilePreviewCard(document: doc),
          const SizedBox(height: 16),
          _SectionTitle(
            icon: doc.workflowMode == WorkflowMode.sequential
                ? Icons.format_list_numbered
                : Icons.groups_outlined,
            title: doc.workflowMode == WorkflowMode.sequential
                ? 'سير الموافقة (تسلسلي)'
                : 'المعتمدون (متوازي)',
          ),
          const SizedBox(height: 12),
          _WorkflowSection(document: doc),
          const SizedBox(height: 16),
          const _SectionTitle(
            icon: Icons.history,
            title: 'سجل النشاط',
          ),
          const SizedBox(height: 12),
          _LogsSection(logs: doc.logs),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF2D507F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  document.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(status: document.status),
            ],
          ),
          if (document.description != null &&
              document.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              document.description!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.white.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
              Text(
                document.creator.name,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('yyyy/MM/dd · HH:mm').format(document.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.white.withValues(alpha: 0.9),
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
// File preview
// ---------------------------------------------------------------------------
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

  // Detect type from mime first, then fall back to extension
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
      // Get auth token for PDF viewer
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.read();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _PdfPreviewDialog(
          url: url,
          fileName: widget.document.fileName ??
              url.split('/').last,
          token: token,
        ),
      );
    } else if (_isImage) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _ImagePreviewDialog(
          url: url,
          fileName: widget.document.fileName ??
              url.split('/').last,
        ),
      );
    } else {
      // Unsupported type
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('معاينة هذا النوع من الملفات غير مدعومة.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final url = _fileUrl;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Tappable thumbnail for images
          if (_isImage && url != null)
            GestureDetector(
              onTap: _openPreview,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppColors.background,
                          child: const Center(
                              child: CircularProgressIndicator()),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.background,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      // Zoom hint overlay
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isPdf
                        ? Icons.picture_as_pdf_outlined
                        : _isImage
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
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
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSize(doc.fileSize),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (url != null)
                  IconButton(
                    tooltip: 'معاينة الملف',
                    onPressed: _openPreview,
                    icon: const Icon(
                      Icons.visibility_outlined,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
// Image preview — full-screen, pinch-to-zoom, tap background to dismiss
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
          // Tap outside image to dismiss
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black87),
          ),
          // Pinch-to-zoom image
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
          // Top bar
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
// PDF preview — full-screen SfPdfViewer with auth header
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
            // Top bar
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
            // PDF viewer
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
// Section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
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
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workflow (sequential = stepper, parallel = list)
// ---------------------------------------------------------------------------

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: document.workflowMode == WorkflowMode.sequential
          ? WorkflowStepper(steps: document.workflows)
          : Column(
              children: [
                for (var i = 0; i < document.workflows.length; i++) ...[
                  _ParallelStepRow(
                    key: ValueKey(document.workflows[i].id),
                    step: document.workflows[i],
                  ),
                  if (i < document.workflows.length - 1)
                    const Divider(height: 16),
                ],
              ],
            ),
    );
  }
}

class _ParallelStepRow extends StatelessWidget {
  const _ParallelStepRow({super.key, required this.step});
  final WorkflowStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            _initials(step.user.name),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.user.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step.user.email ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        StatusChip.fromStep(stepStatus: step.status, dense: true),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first;
    return '${parts.first.characters.first}${parts[1].characters.first}';
  }
}

// ---------------------------------------------------------------------------
// Logs
// ---------------------------------------------------------------------------

class _LogsSection extends StatelessWidget {
  const _LogsSection({required this.logs});
  final List<DocumentLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'لا توجد سجلات بعد.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final sorted = [...logs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      // Use a Column instead of a nested ListView.separated to avoid
      // nested-scrollable interactions with the parent ListView.
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            _LogTile(key: ValueKey(sorted[i].id), log: sorted[i]),
            if (i < sorted.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({super.key, required this.log});
  final DocumentLog log;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (log.action) {
      LogAction.created => (
        Icons.note_add_outlined,
        AppColors.primary,
        'تم إنشاء المستند',
      ),
      LogAction.sent => (
        Icons.send_outlined,
        AppColors.accent,
        'تم إرسال المستند للاعتماد',
      ),
      LogAction.approved => (
        Icons.check_circle_outline,
        AppColors.statusApproved,
        'اعتمد المستند',
      ),
      LogAction.rejected => (
        Icons.cancel_outlined,
        AppColors.statusRejected,
        'رفض المستند',
      ),
      _ => (Icons.info_outline, AppColors.textSecondary, 'حدث'),
    };

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
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
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('yyyy/MM/dd · HH:mm').format(log.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (log.note != null && log.note!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log.note!,
                      style: const TextStyle(fontSize: 12),
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
// Action bar — ALWAYS returns the same widget shape across all states.
// We toggle visibility via Visibility(maintainState/maintainSize). This is
// the most defensive shape: the bottomNavigationBar slot always contains
// the same SafeArea > Container > Row > [Buttons] tree, regardless of
// whether it's the user's turn or whether an action is in flight.
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

    final result = Visibility(
      visible: canAct,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.statusRejected,
                    side: const BorderSide(
                      color: AppColors.statusRejected,
                      width: 1.4,
                    ),
                  ),
                  onPressed: widget.isActing
                      ? null
                      : () => _promptForNote(
                            context,
                            title: 'رفض المستند',
                            confirmLabel: 'رفض',
                            confirmColor: AppColors.statusRejected,
                            isNoteRequired: true,
                            onConfirm: widget.onReject,
                          ),
                  icon: const Icon(Icons.close),
                  label: const Text('رفض'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusApproved,
                  ),
                  onPressed: widget.isActing
                      ? null
                      : () => _promptForNote(
                            context,
                            title: 'اعتماد المستند',
                            confirmLabel: 'اعتماد',
                            confirmColor: AppColors.statusApproved,
                            isNoteRequired: false,
                            onConfirm: widget.onApprove,
                          ),
                  icon: SizedBox(
                    width: 18,
                    height: 18,
                    child: widget.isActing
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          )
                        : const Icon(Icons.check, size: 18),
                  ),
                  label: const Text('اعتماد'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  Future<void> _promptForNote(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Color confirmColor,
    required bool isNoteRequired,
    required Future<void> Function(String? note) onConfirm,
  }) async {
    // FIX (root cause of '_dependents.isEmpty'):
    // Previously the TextEditingController was created in this method's
    // scope and disposed immediately after `await showDialog`. Disposing
    // a TextEditingController synchronously after the dialog returns
    // races against Flutter's overlay-deactivation pass — the EditableText
    // for the dialog's TextField is still being deactivated and still
    // depends on the controller. That deactivation walk is exactly what
    // the stack trace showed (frames #21..#90 of _deactivateRecursively
    // through the Overlay's children).
    //
    // Fix: move the controller into a StatefulWidget that lives INSIDE
    // the dialog tree. Its dispose() is now called by Flutter as part
    // of the same deactivation pass that's tearing down the dialog —
    // strictly in the right order, no race.
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

/// Dialog body extracted into its own StatefulWidget so the
/// TextEditingController is owned by the dialog's element tree and
/// disposed as part of the dialog's normal deactivation pass — NOT
/// from the calling code immediately after `await showDialog`, which
/// races with the overlay tearing down the dialog and triggers
/// '_dependents.isEmpty' on the EditableText's InheritedWidgets.
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
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // Runs as part of the dialog's deactivation pass, AFTER Flutter has
    // unregistered the EditableText's dependents. No race.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText:
                widget.isNoteRequired ? 'سبب الرفض' : 'ملاحظة (اختياري)',
            alignLabelWithHint: true,
          ),
          validator: (value) {
            if (widget.isNoteRequired &&
                (value == null || value.trim().isEmpty)) {
              return 'الرجاء إدخال سبب الرفض';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: Text(
            widget.confirmLabel,
            style: TextStyle(color: widget.confirmColor),
          ),
        ),
      ],
    );
  }
}