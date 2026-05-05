import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_constants.dart';
import '../../../auth/domain/user.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';
import '../providers/documents_list_controller.dart';
import '../widgets/approver_picker_sheet.dart';

class CreateDocumentScreen extends ConsumerStatefulWidget {
  const CreateDocumentScreen({super.key});

  @override
  ConsumerState<CreateDocumentScreen> createState() =>
      _CreateDocumentScreenState();
}

class _CreateDocumentScreenState extends ConsumerState<CreateDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  WorkflowMode _mode = WorkflowMode.sequential;
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  List<User> _approvers = [];
  bool _isSubmitting = false;
  String? _formError;

  static const _allowedExtensions = ['pdf', 'doc', 'docx', 'jpg', 'png', 'webp'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;
    if (picked.size > AppConstants.maxUploadBytes) {
      setState(() {
        _formError = 'حجم الملف يتجاوز الحد الأقصى (20 ميجابايت).';
      });
      return;
    }
    setState(() {
      _selectedFile = File(picked.path!);
      _selectedFileName = picked.name;
      _selectedFileSize = picked.size;
      _formError = null;
    });
  }

  Future<void> _pickApprovers() async {
    final result = await showModalBottomSheet<List<User>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ApproverPickerSheet(initialSelection: _approvers),
    );
    if (result != null) {
      setState(() => _approvers = result);
    }
  }

  void _reorderApprovers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _approvers.removeAt(oldIndex);
      _approvers.insert(newIndex, item);
    });
  }

  void _removeApprover(int index) {
    setState(() => _approvers.removeAt(index));
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      setState(() => _formError = 'الرجاء اختيار ملف.');
      return;
    }
    if (_approvers.isEmpty) {
      setState(() => _formError = 'الرجاء اختيار معتمد واحد على الأقل.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(documentsRepositoryProvider);
      await repo.create(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        file: _selectedFile!,
        workflowMode: _mode,
        approverIds: _approvers.map((u) => u.id).toList(),
      );

      for (final type in DocumentListType.values) {
        // ignore: unawaited_futures
        ref.read(documentsListProvider(type).notifier).refresh();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء المستند وإرساله للاعتماد.')),
      );
      context.pop();
    } on ApiFailure catch (failure) {
      setState(() {
        _formError = arabicMessageFor(failure.code, fallback: failure.message);
      });
    } catch (e, stackTrace) {
      debugPrint('=== UPLOAD ERROR ===');
      debugPrint('Type: ${e.runtimeType}');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      setState(() {
        _formError = '[DEBUG] ${e.runtimeType}: $e';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مستند جديد')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'العنوان *',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'الرجاء إدخال العنوان';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'الوصف (اختياري)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'الملف المرفق', icon: Icons.attach_file),
            const SizedBox(height: 8),
            _FilePickerTile(
              fileName: _selectedFileName,
              fileSize: _selectedFileSize,
              onPick: _pickFile,
              onClear: _selectedFile == null
                  ? null
                  : () => setState(() {
                        _selectedFile = null;
                        _selectedFileName = null;
                        _selectedFileSize = null;
                      }),
            ),
            const SizedBox(height: 6),
            Text(
              'الأنواع المدعومة: PDF · DOC · DOCX · JPG · PNG · WEBP — حد أقصى 20 ميجابايت',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(
              title: 'نمط الموافقة',
              icon: Icons.alt_route,
            ),
            const SizedBox(height: 8),
            _ModeSelector(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(
              title: 'المعتمدون',
              icon: Icons.group_outlined,
            ),
            const SizedBox(height: 8),
            _ApproversList(
              approvers: _approvers,
              isSequential: _mode == WorkflowMode.sequential,
              onAdd: _pickApprovers,
              onReorder: _reorderApprovers,
              onRemove: _removeApprover,
            ),
            if (_formError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusRejectedBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 20,
                      color: AppColors.statusRejected,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formError!,
                        style: const TextStyle(
                          color: AppColors.statusRejected,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: const Text('إنشاء وإرسال للاعتماد'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

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

class _FilePickerTile extends StatelessWidget {
  const _FilePickerTile({
    required this.fileName,
    required this.fileSize,
    required this.onPick,
    required this.onClear,
  });

  final String? fileName;
  final int? fileSize;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile ? AppColors.primary : AppColors.border,
              width: hasFile ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.upload_file,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasFile ? fileName! : 'اضغط لاختيار ملف',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hasFile
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (hasFile && fileSize != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatSize(fileSize!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});
  final WorkflowMode mode;
  final ValueChanged<WorkflowMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeOption(
            isSelected: mode == WorkflowMode.sequential,
            icon: Icons.format_list_numbered,
            title: 'تسلسلي',
            subtitle: 'يعتمد كل شخص بعد الآخر بالترتيب.',
            onTap: () => onChanged(WorkflowMode.sequential),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeOption(
            isSelected: mode == WorkflowMode.parallel,
            icon: Icons.groups_outlined,
            title: 'متوازي',
            subtitle: 'الجميع يعتمد بنفس الوقت.',
            onTap: () => onChanged(WorkflowMode.parallel),
          ),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool isSelected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.white : AppColors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? AppColors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? AppColors.white.withOpacity(0.85)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApproversList extends StatelessWidget {
  const _ApproversList({
    required this.approvers,
    required this.isSequential,
    required this.onAdd,
    required this.onReorder,
    required this.onRemove,
  });

  final List<User> approvers;
  final bool isSequential;
  final VoidCallback onAdd;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (approvers.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 36,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 8),
                const Text(
                  'لم يتم اختيار معتمدين بعد.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('اختيار معتمدين'),
                ),
              ],
            ),
          )
        else ...[
          if (isSequential)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'الترتيب مهم — اسحب لإعادة الترتيب.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: isSequential,
            onReorder: onReorder,
            itemCount: approvers.length,
            itemBuilder: (context, index) {
              final user = approvers[index];
              return Container(
                key: ValueKey(user.id),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    if (isSequential)
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(
                          user.name.characters.first,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            user.email ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => onRemove(index),
                    ),
                  ],
                ),
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.edit),
            label: const Text('تعديل قائمة المعتمدين'),
          ),
        ],
      ],
    );
  }
}