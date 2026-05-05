import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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

// ============================================================================
// FIX: Changed from ConsumerWidget to ConsumerStatefulWidget.
//
// ConsumerWidget's ref is only valid for a single build() invocation.
// The onApprove / onReject callbacks captured ref in a closure, but after
// the first state emission (isActing: true) build() re-runs and the OLD
// ref becomes invalid — any subsequent use of it (ref.read, ref.exists)
// during the same async callback hits the '_dependents.isEmpty' assertion.
//
// ConsumerStatefulWidget's ref is tied to the State object's lifecycle,
// so it stays valid across rebuilds and across async gaps.
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentDetailsProvider(documentId));
    final user = ref.watch(currentUserProvider);
    final controller =
        ref.read(documentDetailsProvider(documentId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المستند'),
      ),
      body: Builder(
        builder: (_) {
          if (state.isLoading && state.document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.document == null) {
            return ErrorStateView(
              failure: state.error!,
              onRetry: controller.load,
            );
          }
          final doc = state.document!;
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: controller.load,
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
        },
      ),
      bottomNavigationBar: state.document != null
          ? _ActionBar(
              document: state.document!,
              currentUser: user,
              isActing: state.isActing,
              onApprove: (note) async {
                final updated = await controller.approve(note: note);
                if (!context.mounted) return;
                if (updated != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    for (final type in DocumentListType.values) {
                      if (ref.exists(documentsListProvider(type))) {
                        ref
                            .read(documentsListProvider(type).notifier)
                            .replaceDocument(updated);
                      }
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم اعتماد المستند.')),
                  );
                } else {
                  _showErrorSnack(context);
                }
              },
              onReject: (note) async {
                final updated = await controller.reject(note: note);
                if (!context.mounted) return;
                if (updated != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    for (final type in DocumentListType.values) {
                      if (ref.exists(documentsListProvider(type))) {
                        ref
                            .read(documentsListProvider(type).notifier)
                            .replaceDocument(updated);
                      }
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم رفض المستند.')),
                  );
                } else {
                  _showErrorSnack(context);
                }
              },
            )
          : null,
    );
  }

  void _showErrorSnack(BuildContext context) {
    final failure = ref.read(documentDetailsProvider(documentId)).error;
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.statusRejected,
        content: Text(
          arabicMessageFor(failure.code, fallback: failure.message),
        ),
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

class _FilePreviewCard extends ConsumerStatefulWidget {
  const _FilePreviewCard({required this.document});
  final Document document;

  @override
  ConsumerState<_FilePreviewCard> createState() => _FilePreviewCardState();
}

class _FilePreviewCardState extends ConsumerState<_FilePreviewCard> {
  bool _isOpening = false;

  String? get _fileUrl {
    final path = widget.document.filePath;
    if (path == null) return null;
    return '${AppConstants.storageBase}/storage/$path';
  }

  Future<void> _openExternally() async {
    final url = _fileUrl;
    if (url == null) return;
    setState(() => _isOpening = true);
    try {
      final dir = await getTemporaryDirectory();
      final filename =
          widget.document.fileName ?? url.split('/').last;
      final savePath = '${dir.path}/$filename';
      final dio = ref.read(apiClientProvider).dio;
      await dio.download(url, savePath);
      await OpenFilex.open(savePath);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الملف.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
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
          if (doc.isImage() && url != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppColors.background,
                    child: const Center(child: CircularProgressIndicator()),
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
                    doc.isPdf()
                        ? Icons.picture_as_pdf_outlined
                        : doc.isImage()
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
                IconButton(
                  tooltip: 'فتح الملف',
                  onPressed: _isOpening ? null : _openExternally,
                  icon: _isOpening
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.open_in_new,
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
                  _ParallelStepRow(step: document.workflows[i]),
                  if (i < document.workflows.length - 1)
                    const Divider(height: 16),
                ],
              ],
            ),
    );
  }
}

class _ParallelStepRow extends StatelessWidget {
  const _ParallelStepRow({required this.step});
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
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _LogTile(log: sorted[i]),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
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
// Action bar (approve / reject)
// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.document,
    required this.currentUser,
    required this.isActing,
    required this.onApprove,
    required this.onReject,
  });

  final Document document;
  final dynamic currentUser;
  final bool isActing;
  final Future<void> Function(String? note) onApprove;
  final Future<void> Function(String? note) onReject;

  @override
  Widget build(BuildContext context) {
    if (!document.isTurnOf(currentUser)) {
      return const SizedBox.shrink();
    }

    return SafeArea(
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
                onPressed: isActing
                    ? null
                    : () => _promptForNote(
                          context,
                          title: 'رفض المستند',
                          confirmLabel: 'رفض',
                          confirmColor: AppColors.statusRejected,
                          isNoteRequired: true,
                          onConfirm: onReject,
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
                onPressed: isActing
                    ? null
                    : () => _promptForNote(
                          context,
                          title: 'اعتماد المستند',
                          confirmLabel: 'اعتماد',
                          confirmColor: AppColors.statusApproved,
                          isNoteRequired: false,
                          onConfirm: onApprove,
                        ),
                icon: isActing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('اعتماد'),
              ),
            ),
          ],
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
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: isNoteRequired ? 'سبب الرفض' : 'ملاحظة (اختياري)',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (isNoteRequired && (value == null || value.trim().isEmpty)) {
                  return 'الرجاء إدخال سبب الرفض';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: Text(
                confirmLabel,
                style: TextStyle(color: confirmColor),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (note == null) return; // cancelled
    await onConfirm(note.isEmpty ? null : note);
  }
}