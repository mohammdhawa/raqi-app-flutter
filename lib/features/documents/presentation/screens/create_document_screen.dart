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
import 'template_picker_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
//  CREATE DOCUMENT SCREEN
// ═══════════════════════════════════════════════════════════════════════

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

  static const _allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'jpg',
    'png',
    'webp'
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── File picker ────────────────────────────────────────────────────

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

  // ── Approver picker ────────────────────────────────────────────────

  Future<void> _pickApprovers() async {
    debugPrint('╔══ [STEP 1] _pickApprovers() called');
    debugPrint('║  mounted=$mounted, approvers.length=${_approvers.length}');

    try {
      debugPrint('╠══ [STEP 2] Opening showModalBottomSheet...');
      final result = await showModalBottomSheet<List<User>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          debugPrint('╠══ [STEP 3] showModalBottomSheet builder called');
          return FractionallySizedBox(
            heightFactor: 0.85,
            child: ApproverPickerSheet(initialSelection: _approvers),
          );
        },
      );
      debugPrint('╠══ [STEP 8] Sheet closed, result=${result?.length ?? "null"}');
      if (result != null) {
        setState(() => _approvers = result);
      }
    } catch (e, stackTrace) {
      debugPrint('╠══ [ERROR] showModalBottomSheet threw!');
      debugPrint('║  Type: ${e.runtimeType}');
      debugPrint('║  Error: $e');
      debugPrint('║  Stack: $stackTrace');
      if (!mounted) return;
      setState(() {
        _formError = 'تعذّر فتح نافذة اختيار المعتمدين: $e';
      });
    }
    debugPrint('╚══ _pickApprovers() done');
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

  // ── Submit ─────────────────────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // AppBar
          _buildAppBar(context),

          // Form body
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
                  // ── 0. Creation mode toggle ──
                  _CreationModeToggle(
                    onTemplateTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TemplatePickerScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── 1. Title section ──
                  _AlraqiSectionHeader(
                    icon: Icons.description_outlined,
                    label: 'العنوان',
                    required: true,
                  ),
                  _AlraqiTextField(
                    controller: _titleController,
                    hintText: 'مثال: عقد توريد أنظمة Q4',
                    maxLength: 255,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال العنوان';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _titleController,
                      builder: (_, value, __) => Text(
                        '${value.text.length} / 255',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text3,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── 2. Description section ──
                  _AlraqiSectionHeader(
                    icon: Icons.edit_outlined,
                    label: 'الوصف (اختياري)',
                  ),
                  _AlraqiTextField(
                    controller: _descriptionController,
                    hintText:
                        'اكتب وصفاً موجزاً يساعد المعتمدين على فهم سياق المستند...',
                    multiline: true,
                    minLines: 4,
                  ),

                  const SizedBox(height: 20),

                  // ── 3. File section ──
                  _AlraqiSectionHeader(
                    icon: Icons.folder_outlined,
                    label: 'الملف المرفق',
                    required: true,
                  ),
                  _FilePickerArea(
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
                  const SizedBox(height: 8),
                  const Text(
                    'الأنواع المدعومة: PDF · DOC · DOCX · JPG · PNG · WEBP — حد أقصى 20 ميجابايت',
                    style: TextStyle(fontSize: 11, color: AppColors.text3),
                  ),

                  const SizedBox(height: 20),

                  // ── 4. Approval mode section ──
                  _AlraqiSectionHeader(
                    icon: Icons.share_outlined,
                    label: 'نمط الموافقة',
                    required: true,
                  ),
                  _ModeSelector(
                    mode: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),

                  const SizedBox(height: 20),

                  // ── 5. Approvers section ──
                  _AlraqiSectionHeader(
                    icon: Icons.group_outlined,
                    label: 'المعتمدون',
                    required: true,
                  ),
                  _ApproversList(
                    approvers: _approvers,
                    isSequential: _mode == WorkflowMode.sequential,
                    onAdd: _pickApprovers,
                    onReorder: _reorderApprovers,
                    onRemove: _removeApprover,
                  ),

                  // ── Form error ──
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.rejectedBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.rejected.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 20, color: AppColors.rejected),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.rejected,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom action bar ──
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      child: Stack(
        children: [
          // Gold radial glow
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
                // Trailing draft button (appears on right in RTL)
                TextButton(
                  onPressed: () {
                    // Draft action placeholder
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'مسودة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                // Title column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'مستند جديد',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'إنشاء وإرسال للاعتماد',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Leading back button (appears on left in RTL — this is the right side visually)
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

  // ── Bottom bar ─────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: AppColors.shActionBar,
      ),
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.rLg),
            ),
            elevation: 0,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'إنشاء وإرسال للاعتماد',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  CREATION MODE TOGGLE
// ═══════════════════════════════════════════════════════════════════════

class _CreationModeToggle extends StatelessWidget {
  const _CreationModeToggle({required this.onTemplateTap});
  final VoidCallback onTemplateTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Upload mode (currently active — this screen IS the upload flow)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppColors.rMd),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file_outlined, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'رفع ملف',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Template mode — navigates away
        Expanded(
          child: GestureDetector(
            onTap: onTemplateTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppColors.rMd),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'إنشاء من قالب',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════

class _AlraqiSectionHeader extends StatelessWidget {
  const _AlraqiSectionHeader({
    required this.icon,
    required this.label,
    this.required = false,
  });

  final IconData icon;
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          if (required) ...[
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.rejected,
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x4DC8A36B), // 30% gold
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.3, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TEXT FIELD
// ═══════════════════════════════════════════════════════════════════════

class _AlraqiTextField extends StatelessWidget {
  const _AlraqiTextField({
    required this.controller,
    this.hintText,
    this.maxLength,
    this.multiline = false,
    this.minLines,
    this.validator,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;
  final bool multiline;
  final int? minLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: multiline ? null : 1,
      minLines: multiline ? (minLines ?? 3) : 1,
      validator: validator,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rLg),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rLg),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rLg),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rLg),
          borderSide: const BorderSide(color: AppColors.rejected, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rLg),
          borderSide: const BorderSide(color: AppColors.rejected, width: 1.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FILE PICKER AREA
// ═══════════════════════════════════════════════════════════════════════

class _FilePickerArea extends StatelessWidget {
  const _FilePickerArea({
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
    return hasFile ? _buildFilled() : _buildEmpty();
  }

  Widget _buildEmpty() {
    return GestureDetector(
      onTap: onPick,
      child: _DashedBorderWrapper(
        radius: AppColors.rLg,
        color: AppColors.borderStrong,
        strokeWidth: 1.5,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.rLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.upload_file_outlined,
                  size: 24,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'اضغط لاختيار ملف',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'أو اسحب الملف وأفلته هنا',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilled() {
    final ext = fileName?.split('.').last.toUpperCase() ?? 'FILE';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          // File type badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.rejectedBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              ext,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.rejected,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatSize(fileSize ?? 0)} ميجابايت · جاهز للإرسال',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.text3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '0.00';
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1);
    return (bytes / (1024 * 1024)).toStringAsFixed(2);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DASHED BORDER
// ═══════════════════════════════════════════════════════════════════════

class _DashedBorderWrapper extends StatelessWidget {
  const _DashedBorderWrapper({
    required this.child,
    this.radius = 14,
    this.color = AppColors.borderStrong,
    this.strokeWidth = 1.5,
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        radius: radius,
        color: color,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  final double radius;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));

    const dashWidth = 6.0;
    const dashSpace = 4.0;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          paint,
        );
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ═══════════════════════════════════════════════════════════════════════
//  MODE SELECTOR
// ═══════════════════════════════════════════════════════════════════════

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});
  final WorkflowMode mode;
  final ValueChanged<WorkflowMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AlraqiModeCard(
            isSelected: mode == WorkflowMode.sequential,
            icon: Icons.format_list_numbered,
            title: 'تسلسلي',
            subtitle: 'يعتمد كل شخص بعد الآخر بالترتيب.',
            onTap: () => onChanged(WorkflowMode.sequential),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _AlraqiModeCard(
            isSelected: mode == WorkflowMode.parallel,
            icon: Icons.group_outlined,
            title: 'متوازي',
            subtitle: 'الجميع يعتمد بنفس الوقت.',
            onTap: () => onChanged(WorkflowMode.parallel),
          ),
        ),
      ],
    );
  }
}

class _AlraqiModeCard extends StatelessWidget {
  const _AlraqiModeCard({
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon wrap
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.16)
                    : AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.accent : AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.78)
                    : AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  APPROVERS LIST
// ═══════════════════════════════════════════════════════════════════════

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
          _buildEmptyState()
        else ...[
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: onReorder,
            proxyDecorator: (child, index, animation) {
              return Material(
                color: Colors.transparent,
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            itemCount: approvers.length,
            itemBuilder: (context, index) {
              final user = approvers[index];
              final isChief = user.isChief;
              return _buildApproverRow(context, user, index, isChief);
            },
          ),
          const SizedBox(height: 12),
          _buildEditButton(),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return _DashedBorderWrapper(
      radius: AppColors.rLg,
      color: AppColors.borderStrong,
      strokeWidth: 1.5,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.rLg),
        ),
        child: Column(
          children: [
            const Text(
              'لم يتم اختيار معتمدين بعد.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('اختيار معتمدين'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApproverRow(
      BuildContext context, User user, int index, bool isChief) {
    Widget row = Container(
      key: ValueKey(user.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChief ? AppColors.accent : AppColors.border,
          width: isChief ? 1.5 : 1,
        ),
        gradient: isChief
            ? const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [Color(0x0FC8A36B), Colors.transparent],
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Drag handle (sequential only)
              if (isSequential) ...[
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(
                    Icons.drag_handle,
                    size: 20,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Avatar / number
              if (isSequential)
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.name.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),

              const SizedBox(width: 12),

              // Name + department + section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (user.departmentName != null &&
                        user.departmentName!.isNotEmpty)
                      Text(
                        'الادارة: ${user.departmentName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                        ),
                      ),
                    if (user.sectionName != null &&
                        user.sectionName!.isNotEmpty)
                      Text(
                        'القسم: ${user.sectionName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text2,
                        ),
                      ),
                  ],
                ),
              ),

              // Close button
              GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: AppColors.text3,
                  ),
                ),
              ),
            ],
          ),

          // Chief badge
          if (isChief) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppColors.pill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined,
                      size: 12, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text(
                    'المسؤول الأعلى',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pendingText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return row;
  }

  Widget _buildEditButton() {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onAdd,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('تعديل قائمة المعتمدين'),
      ),
    );
  }
}