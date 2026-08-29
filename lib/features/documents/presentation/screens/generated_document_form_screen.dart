import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/api_failure.dart';
import '../../../../core/errors/error_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/user.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';
import '../../domain/document_template.dart';
import '../providers/documents_list_controller.dart';
import '../../data/users_repository.dart';
import '../../../../core/validation/approver_validation.dart';
import '../../../../core/widgets/approver_picker_sheet.dart';
import '../../../../core/widgets/reorderable_approver_list.dart';
import '../widgets/attachments_field.dart';

// ═══════════════════════════════════════════════════════════════════════
//  GENERATED DOCUMENT FORM SCREEN
// ═══════════════════════════════════════════════════════════════════════

class GeneratedDocumentFormScreen extends ConsumerStatefulWidget {
  const GeneratedDocumentFormScreen({super.key, required this.template});

  final DocumentTemplate template;

  @override
  ConsumerState<GeneratedDocumentFormScreen> createState() =>
      _GeneratedDocumentFormScreenState();
}

class _GeneratedDocumentFormScreenState
    extends ConsumerState<GeneratedDocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _exportController = TextEditingController();
  final _importController = TextEditingController();
  WorkflowMode _mode = WorkflowMode.sequential;
  List<User> _approvers = [];
  List<PickedAttachment> _attachments = [];
  bool _isSubmitting = false;
  bool _isLoadingCounters = false;
  DocumentCounters? _counters;
  String? _formError;
  String? _exportError;
  String? _importError;
  String? _approverError;
  Map<String, String> _fieldApiErrors = {};

  /// Set when the server rejected one of the chosen approvers. Blocks submit
  /// until the user has re-opened the picker (which re-reads `/managers`)
  /// and confirmed the corrected list.
  bool _approversNeedConfirmation = false;

  /// Dynamic field controllers — keyed by field key from schema.
  final Map<String, TextEditingController> _fieldControllers = {};

  /// Select field values.
  final Map<String, String?> _selectValues = {};

  /// Table field values — list of rows, each row is a list of cell values.
  final Map<String, List<List<String>>> _tableValues = {};

  DocumentTemplate get template => widget.template;

  @override
  void initState() {
    super.initState();
    // Pre-populate title with template name.
    _titleController.text = template.name;

    // Initialise controllers for each field in the schema.
    for (final field in template.fieldsSchema) {
      final key = field['key'] as String;
      final type = field['type'] as String;
      if (type == 'table') {
        _tableValues[key] = [];
      } else if (type == 'select') {
        _selectValues[key] = null;
      } else {
        _fieldControllers[key] = TextEditingController();
      }
    }

    // Fetch suggested counters after the first frame so ref is ready.
    Future.microtask(_loadCounters);
  }

  Future<void> _loadCounters() async {
    if (!mounted) return;
    setState(() => _isLoadingCounters = true);
    try {
      final counters =
          await ref.read(documentsRepositoryProvider).fetchNextCounters();
      if (!mounted) return;
      setState(() {
        _counters = counters;
        _isLoadingCounters = false;
        // Pre-fill export only when counter is already initialized.
        if (counters.exportIsInitialized && counters.exportNextNumber != null) {
          _exportController.text = counters.exportNextNumber.toString();
        }
        // Pre-fill import if the server returned a suggested number.
        if (counters.importNextNumber != null) {
          _importController.text = counters.importNextNumber.toString();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingCounters = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _exportController.dispose();
    _importController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Collect field values ────────────────────────────────────────────

  Map<String, dynamic> _collectFieldValues() {
    final values = <String, dynamic>{};
    for (final field in template.fieldsSchema) {
      final key = field['key'] as String;
      final type = field['type'] as String;
      if (type == 'table') {
        values[key] = _tableValues[key] ?? [];
      } else if (type == 'select') {
        values[key] = _selectValues[key];
      } else {
        values[key] = _fieldControllers[key]?.text.trim();
      }
    }
    return values;
  }

  // ── Build field widget ─────────────────────────────────────────────

  Widget _buildField(Map<String, dynamic> field) {
    final key = field['key'] as String;
    final type = field['type'] as String;
    final required = field['required'] == true;

    switch (type) {
      case 'text':
        return _StyledTextField(
          controller: _fieldControllers[key]!,
          hintText: field['label'] as String? ?? '',
          validator: required
              ? (v) =>
                  (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
              : null,
        );

      case 'number':
        return _StyledTextField(
          controller: _fieldControllers[key]!,
          hintText: field['label'] as String? ?? '',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          validator: required
              ? (v) =>
                  (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
              : null,
        );

      case 'textarea':
        return _StyledTextField(
          controller: _fieldControllers[key]!,
          hintText: field['label'] as String? ?? '',
          multiline: true,
          minLines: 3,
          validator: required
              ? (v) =>
                  (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
              : null,
        );

      case 'date':
        return _DatePickerField(
          controller: _fieldControllers[key]!,
          required: required,
        );

      case 'select':
        final options = ((field['options'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        return _SelectField(
          value: _selectValues[key],
          options: options,
          required: required,
          onChanged: (v) => setState(() => _selectValues[key] = v),
        );

      case 'table':
        final columns = ((field['columns'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        return _TableField(
          columns: columns,
          rows: _tableValues[key] ?? [],
          required: required,
          label: field['label'] as String? ?? '',
          onChanged: (rows) => setState(() => _tableValues[key] = rows),
        );

      default:
        return _StyledTextField(
          controller: _fieldControllers[key] ??= TextEditingController(),
          hintText: field['label'] as String? ?? '',
        );
    }
  }

  // ── Attachments picker ─────────────────────────────────────────────

  Future<void> _pickAttachments() async {
    final result = await pickAttachments(_attachments);
    if (!mounted) return;
    setState(() {
      _attachments = result.attachments;
      _formError = result.error;
    });
  }

  // ── Approver picker ────────────────────────────────────────────────

  /// Who this form may pick. The chief is dropped for the same reason as on
  /// the upload form: the generated-document workflow appends them itself, so
  /// listing them would offer a step the backend rejects. Deliberately not a
  /// rule inside the shared picker — the leave form needs the chief.
  Future<List<User>> _loadApproverCandidates() async {
    final all =
        await ref.read(usersRepositoryProvider).searchPotentialApprovers();
    return all.where((user) => !user.isChief).toList();
  }

  Future<void> _pickApprovers() async {
    try {
      final result = await showModalBottomSheet<List<User>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return FractionallySizedBox(
            heightFactor: 0.85,
            child: ApproverPickerSheet<User>(
              initialSelection: _approvers,
              loadCandidates: _loadApproverCandidates,
              idOf: (user) => user.id,
              nameOf: (user) => user.name,
              departmentOf: (user) => user.departmentName,
              sectionOf: (user) => user.sectionName,
            ),
          );
        },
      );
      if (result != null) {
        setState(() {
          _approvers = result;
          // Confirming the picker IS the confirmation of the refreshed list:
          // the sheet re-reads `/managers` every time it opens, so whatever
          // came back has just been checked against the live roster.
          _approverError = null;
          _approversNeedConfirmation = false;
        });
      }
    } catch (e, stackTrace) {
      logUnexpected('Approver picker failed to open', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _formError = 'تعذّر فتح نافذة اختيار المعتمدين. حاول مرة أخرى.';
      });
    }
  }

  void _reorderApprovers(int oldIndex, int newIndex) {
    setState(() {
      final item = _approvers.removeAt(oldIndex);
      _approvers.insert(newIndex, item);
    });
  }

  void _removeApprover(int index) {
    setState(() => _approvers.removeAt(index));
  }

  // ── Submit ─────────────────────────────────────────────────────────
  //
  // FIX #2: Added better error handling and ensured the payload
  // matches what the backend expects.

  Future<void> _submit() async {
    setState(() {
      _formError = null;
      _exportError = null;
      _importError = null;
      _fieldApiErrors = {};
    });
    if (!_formKey.currentState!.validate()) return;
    if (_approvers.isEmpty) {
      setState(() => _formError = 'الرجاء اختيار معتمد واحد على الأقل.');
      return;
    }
    // A previous attempt had an approver rejected. Re-sending before the user
    // has looked at the corrected list would just fail the same way.
    if (_approversNeedConfirmation) {
      setState(() => _approverError ??=
          'يرجى مراجعة قائمة المعتمدين وتأكيدها قبل الإرسال.');
      return;
    }

    // When the counter is not initialized, export_number is required.
    final exportText = _exportController.text.trim();
    if (_counters != null &&
        !_counters!.exportIsInitialized &&
        exportText.isEmpty) {
      setState(
          () => _exportError = 'يرجى إدخال رقم الصادر لتحديد نقطة البداية.');
      return;
    }

    final exportNumber =
        exportText.isNotEmpty ? int.tryParse(exportText) : null;
    final importText = _importController.text.trim();
    final importNumber =
        importText.isNotEmpty ? int.tryParse(importText) : null;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(documentsRepositoryProvider);
      await repo.createGenerated(
        templateId: template.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        fieldValues: _collectFieldValues(),
        workflowMode: _mode,
        approverIds: _approvers.map((u) => u.id).toList(),
        exportNumber: exportNumber,
        importNumber: importNumber,
        attachments: _attachments.map((a) => a.file).toList(),
      );

      for (final type in DocumentListType.values) {
        ref.read(documentsListProvider(type).notifier).refresh();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء المستند وإرساله للاعتماد.')),
      );
      // Pop back through the template picker to the home screen.
      context.go('/');
    } on ApiFailure catch (failure) {
      // ── The generation killswitch ──────────────────────────────────
      //
      // `config/document.php → generation_enabled` can be turned off at any
      // time, and since backend v10 the endpoint actually enforces it: the
      // request is refused with 403 `document_generation_disabled` before
      // validation runs, so nothing was written and no export number was
      // claimed. It is not a transient outage — it stays refused until an
      // admin turns the feature back on — so there is nothing to retry, and
      // the template this form was built from is now unusable.
      if (failure.code == ApiErrorCode.documentGenerationDisabled) {
        await _handleGenerationDisabled(failure);
        return;
      }

      // Business rules the backend answers with their own code rather than a
      // per-field `errors` map — both are about the export number, so both
      // belong under that field rather than in the generic form banner.
      if (failure.code == ApiErrorCode.duplicateExportNumber ||
          failure.code == ApiErrorCode.counterNotInitialized) {
        if (!mounted) return;
        setState(() {
          _exportError =
              arabicMessageFor(failure.code, fallback: failure.message);
          // A cold-start counter means the department has no starting point
          // yet, so the field is now mandatory however it was prefilled —
          // `/document-counters/next` evidently disagreed with the write
          // path. Recording it as uninitialised (rather than clearing the
          // counters, which would switch the client-side requirement OFF)
          // marks the field required and shows the starting-number hint.
          if (failure.code == ApiErrorCode.counterNotInitialized) {
            _counters = DocumentCounters(
              departmentId: _counters?.departmentId ?? 0,
              exportIsInitialized: false,
              importNextNumber: _counters?.importNextNumber,
            );
            _exportController.clear();
          }
        });
        return;
      }

      // An approver was deleted or demoted between loading `/managers` and
      // submitting. Drop the rejected entries and make the user re-pick.
      final stale = resolveStaleApprovers(
        failure,
        _approvers,
        nameOf: (user) => user.name,
      );
      if (stale != null) {
        if (!mounted) return;
        setState(() {
          _approvers = stale.remaining;
          _approverError = stale.message;
          _approversNeedConfirmation = true;
        });
        return;
      }

      final exportErr = failure.firstErrorFor('export_number');
      final importErr = failure.firstErrorFor('import_number');

      // Extract per-field errors for each template field.
      // Laravel sends them as "field_values.key"; fall back to bare "key".
      final newFieldErrors = <String, String>{};
      if (failure.fieldErrors != null) {
        for (final field in template.fieldsSchema) {
          final key = field['key'] as String;
          final err = failure.firstErrorFor('field_values.$key') ??
              failure.firstErrorFor(key);
          if (err != null) newFieldErrors[key] = err;
        }
      }

      setState(() {
        _exportError = exportErr;
        _importError = importErr;
        _fieldApiErrors = newFieldErrors;

        if (newFieldErrors.isNotEmpty) {
          final labels = newFieldErrors.keys.map((k) {
            final field = template.fieldsSchema.firstWhere(
              (f) => f['key'] == k,
              orElse: () => <String, dynamic>{'label': k},
            );
            return field['label'] as String? ?? k;
          }).join('، ');
          _formError = 'يرجى مراجعة الحقول التالية: $labels';
        } else if (exportErr == null && importErr == null) {
          _formError =
              arabicMessageFor(failure.code, fallback: failure.message);
        }
      });
    } catch (e, stackTrace) {
      // The exception text can carry a local file path or a Dio object's
      // dump — diagnostics, not user copy, and not release-log material.
      logUnexpected('Generated document submit failed', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _formError = arabicMessageFor(ApiErrorCode.unknown);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Generation was switched off server-side. Explains why, throws away the
  /// form state built from a template that can no longer be used, and returns
  /// to the documents list — where the plain file-upload flow still works.
  /// Nothing is re-sent: the refusal stands until an admin re-enables it.
  Future<void> _handleGenerationDisabled(ApiFailure failure) async {
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _formError = null;
      _approvers = [];
      _attachments = [];
      _exportController.clear();
      _importController.clear();
      _counters = null;
    });

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنشاء المستندات من القوالب متوقف'),
          // The backend's message is the authoritative wording for this code.
          content: Text(
            '${arabicMessageFor(failure.code, fallback: failure.message)}\n\n'
            'يمكنك إنشاء مستند برفع ملف بدلاً من ذلك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    context.go('/');
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildAppBar(context),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
                  // ── Template badge ──
                  _TemplateBadge(template: template),
                  const SizedBox(height: 20),

                  // ── 1. Title ──
                  _SectionHeader(
                    icon: Icons.description_outlined,
                    label: 'العنوان',
                    required: true,
                  ),
                  _StyledTextField(
                    controller: _titleController,
                    hintText: 'عنوان المستند',
                    maxLength: 255,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال العنوان';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── 2. Description ──
                  _SectionHeader(
                    icon: Icons.edit_outlined,
                    label: 'الوصف (اختياري)',
                  ),
                  _StyledTextField(
                    controller: _descriptionController,
                    hintText:
                        'وصف موجز يساعد المعتمدين على فهم سياق المستند...',
                    multiline: true,
                    minLines: 3,
                  ),
                  const SizedBox(height: 20),

                  // ── 3. Export / Import numbers ──
                  _SectionHeader(
                    icon: Icons.outbox_outlined,
                    label: 'رقم الصادر',
                    required:
                        _counters != null && !_counters!.exportIsInitialized,
                  ),
                  if (_isLoadingCounters)
                    const _NumbersLoadingRow()
                  else ...[
                    _StyledTextField(
                      controller: _exportController,
                      hintText: 'رقم الصادر',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                    if (_counters != null &&
                        !_counters!.exportIsInitialized) ...[
                      const SizedBox(height: 6),
                      const _HintText(
                        'هذا أول مستند صادر في القسم — يرجى إدخال رقم البداية',
                      ),
                    ],
                    if (_exportError != null) ...[
                      const SizedBox(height: 4),
                      _FieldErrorText(_exportError!),
                    ],
                  ],
                  const SizedBox(height: 20),

                  _SectionHeader(
                    icon: Icons.move_to_inbox_outlined,
                    label: 'رقم الوارد (اختياري)',
                  ),
                  if (_isLoadingCounters)
                    const _NumbersLoadingRow()
                  else ...[
                    _StyledTextField(
                      controller: _importController,
                      hintText: 'رقم الوارد (اختياري)',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                    if (_importError != null) ...[
                      const SizedBox(height: 4),
                      _FieldErrorText(_importError!),
                    ],
                  ],
                  const SizedBox(height: 20),

                  // ── 4. Dynamic fields from schema ──
                  for (final field in template.fieldsSchema) ...[
                    _SectionHeader(
                      icon: _iconForFieldType(field['type'] as String),
                      label:
                          field['label'] as String? ?? field['key'] as String,
                      required: field['required'] == true,
                    ),
                    _buildField(field),
                    if (_fieldApiErrors[field['key'] as String] != null) ...[
                      const SizedBox(height: 4),
                      _FieldErrorText(_fieldApiErrors[field['key'] as String]!),
                    ],
                    const SizedBox(height: 20),
                  ],

                  // ── 4b. Attachments (optional) ──
                  _SectionHeader(
                    icon: Icons.attach_file,
                    label: 'مرفقات إضافية (اختياري)',
                  ),
                  AttachmentsField(
                    attachments: _attachments,
                    onPick: _pickAttachments,
                    onRemove: (i) => setState(() => _attachments.removeAt(i)),
                  ),
                  const SizedBox(height: 6),
                  const _HintText(
                    'حتى 10 ملفات — PDF · DOC · DOCX · JPG · PNG · WEBP · XLSX · XLS — حد أقصى 50 ميجابايت',
                  ),
                  const SizedBox(height: 20),

                  // ── 5. Approval mode ──
                  _SectionHeader(
                    icon: Icons.share_outlined,
                    label: 'نمط الموافقة',
                    required: true,
                  ),
                  _WorkflowModeSelector(
                    mode: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                  const SizedBox(height: 20),

                  // ── 6. Approvers ──
                  _SectionHeader(
                    icon: Icons.group_outlined,
                    label: 'المعتمدون',
                    required: true,
                  ),

                  // Approver list
                  if (_approvers.isNotEmpty) ...[
                    ReorderableApproverList(
                      itemCount: _approvers.length,
                      itemKey: (index) => ValueKey(_approvers[index].id),
                      onReorder: _reorderApprovers,
                      proxyDecorator: (child, _, __) =>
                          Material(color: Colors.transparent, child: child),
                      itemBuilder: (context, index, reorder) {
                        final user = _approvers[index];
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: GestureDetector(
                            onTap: () => _removeApprover(index),
                            child: const Icon(Icons.close,
                                size: 18, color: AppColors.text3),
                          ),
                          title: Text(
                            user.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text),
                          ),
                          subtitle: Text(
                            user.email ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.text3),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              reorder.handle(
                                const Icon(Icons.drag_handle,
                                    size: 18, color: AppColors.text3),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Edit approvers button
                  SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _pickApprovers,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(
                        _approvers.isEmpty
                            ? 'اختيار المعتمدين'
                            : 'تعديل قائمة المعتمدين',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.rLg),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // Approver rejection — shown beside the selector it is
                  // about, not in the generic form banner at the bottom.
                  if (_approverError != null) ...[
                    const SizedBox(height: 6),
                    _FieldErrorText(_approverError!),
                  ],

                  // Error message
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.rejected.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppColors.rMd),
                        border: Border.all(
                          color: AppColors.rejected.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: AppColors.rejected),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.rejected,
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
          _buildBottomBar(),
        ],
      ),
    );
  }

  IconData _iconForFieldType(String type) {
    switch (type) {
      case 'text':
        return Icons.text_fields;
      case 'number':
        return Icons.numbers;
      case 'textarea':
        return Icons.notes;
      case 'date':
        return Icons.calendar_today_outlined;
      case 'select':
        return Icons.list;
      case 'table':
        return Icons.table_chart_outlined;
      default:
        return Icons.input;
    }
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
                      'مستند جديد',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'إنشاء من قالب',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
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
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: AppColors.shActionBar,
      ),
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: (_isSubmitting || _isLoadingCounters) ? null : _submit,
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
//  TEMPLATE BADGE
// ═══════════════════════════════════════════════════════════════════════

class _TemplateBadge extends StatelessWidget {
  const _TemplateBadge({required this.template});
  final DocumentTemplate template;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppColors.rMd),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              template.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.text2),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
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
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  STYLED TEXT FIELD
// ═══════════════════════════════════════════════════════════════════════

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hintText,
    this.multiline = false,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });
  final TextEditingController controller;
  final String hintText;
  final bool multiline;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: multiline ? null : 1,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType:
          keyboardType ?? (multiline ? TextInputType.multiline : null),
      inputFormatters: inputFormatters,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      validator: validator,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DATE PICKER FIELD
// ═══════════════════════════════════════════════════════════════════════

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.controller,
    this.required = false,
  });
  final TextEditingController controller;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1920),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          controller.text = DateFormat('yyyy-MM-dd').format(picked);
        }
      },
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: 'اختر التاريخ',
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.text3),
        suffixIcon:
            const Icon(Icons.calendar_today, size: 18, color: AppColors.text3),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SELECT FIELD
// ═══════════════════════════════════════════════════════════════════════

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.value,
    required this.options,
    required this.onChanged,
    this.required = false,
  });
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
      validator: required
          ? (v) => (v == null || v.isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: 'اختر',
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TABLE FIELD  — Card-based layout with per-row edit/view modes
// ═══════════════════════════════════════════════════════════════════════

class _TableField extends StatefulWidget {
  const _TableField({
    required this.columns,
    required this.rows,
    required this.onChanged,
    this.required = false,
    this.label = '',
  });
  final List<String> columns;
  final List<List<String>> rows;
  final ValueChanged<List<List<String>>> onChanged;
  final bool required;
  final String label;

  @override
  State<_TableField> createState() => _TableFieldState();
}

class _TableFieldState extends State<_TableField> {
  final Map<String, TextEditingController> _cellControllers = {};
  final Set<int> _editingRows = {};

  TextEditingController _controllerFor(int row, int col) {
    final key = '$row:$col';
    if (!_cellControllers.containsKey(key)) {
      final text = (widget.rows.length > row && widget.rows[row].length > col)
          ? widget.rows[row][col]
          : '';
      _cellControllers[key] = TextEditingController(text: text);
    }
    return _cellControllers[key]!;
  }

  void _syncControllers() {
    _cellControllers.removeWhere((key, ctrl) {
      final r = int.parse(key.split(':')[0]);
      if (r >= widget.rows.length) {
        ctrl.dispose();
        return true;
      }
      return false;
    });
  }

  @override
  void didUpdateWidget(covariant _TableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length) {
      _syncControllers();
      final old = Map<String, TextEditingController>.from(_cellControllers);
      _cellControllers.clear();
      for (int r = 0; r < widget.rows.length; r++) {
        for (int c = 0; c < widget.columns.length; c++) {
          final key = '$r:$c';
          final text = widget.rows[r].length > c ? widget.rows[r][c] : '';
          if (old.containsKey(key) && old[key]!.text == text) {
            _cellControllers[key] = old.remove(key)!;
          } else {
            _cellControllers[key] = TextEditingController(text: text);
          }
        }
      }
      for (final ctrl in old.values) {
        ctrl.dispose();
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _cellControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final newIdx = widget.rows.length;
    final newRows = [...widget.rows, List.filled(widget.columns.length, '')];
    widget.onChanged(newRows);
    setState(() => _editingRows.add(newIdx));
  }

  void _removeRow(int index) {
    for (int c = 0; c < widget.columns.length; c++) {
      final key = '$index:$c';
      _cellControllers[key]?.dispose();
      _cellControllers.remove(key);
    }
    final updated = <int>{};
    for (final i in _editingRows) {
      if (i < index) updated.add(i);
      if (i > index) updated.add(i - 1);
    }
    setState(() {
      _editingRows.clear();
      _editingRows.addAll(updated);
    });
    widget.onChanged([...widget.rows]..removeAt(index));
  }

  void _updateCell(int rowIndex, int colIndex, String value) {
    final newRows = widget.rows.map((r) => List<String>.from(r)).toList();
    newRows[rowIndex][colIndex] = value;
    widget.onChanged(newRows);
  }

  // ── View card ──────────────────────────────────────────────────────

  Widget _buildViewCard(int r) {
    final row = widget.rows[r];
    final title = row.isNotEmpty && row[0].isNotEmpty ? row[0] : '—';
    final subtitle = row.length > 1
        ? row.sublist(1).where((v) => v.isNotEmpty).join('  •  ')
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A1B2A41), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Delete
            GestureDetector(
              onTap: () => _removeRow(r),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.rejected.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.delete_outline,
                    size: 16, color: AppColors.rejected),
              ),
            ),
            const SizedBox(width: 6),
            // Edit
            GestureDetector(
              onTap: () => setState(() => _editingRows.add(r)),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_outlined,
                    size: 16, color: AppColors.text2),
              ),
            ),
            const SizedBox(width: 10),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Number badge
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${r + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit card ──────────────────────────────────────────────────────

  Widget _buildEditCard(int r) {
    final isNew = widget.rows[r].every((v) => v.isEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D1B2A41), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row
            Row(
              children: [
                GestureDetector(
                  onTap: isNew
                      ? () => _removeRow(r)
                      : () => setState(() => _editingRows.remove(r)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isNew
                          ? AppColors.rejected.withValues(alpha: 0.1)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isNew ? Icons.delete_outline : Icons.close,
                      size: 16,
                      color: isNew ? AppColors.rejected : AppColors.text3,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    isNew ? 'بيانات العنصر' : 'قيد التحرير',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${r + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Fields
            for (int c = 0; c < widget.columns.length; c++) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  widget.columns[c],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _controllerFor(r, c),
                onChanged: (v) => _updateCell(r, c, v),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              if (c < widget.columns.length - 1) const SizedBox(height: 12),
            ],
            // Save button (only when re-editing an existing card)
            if (!isNew) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: () => setState(() => _editingRows.remove(r)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppColors.rMd),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('حفظ',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormField<List<List<String>>>(
      initialValue: widget.rows,
      validator: widget.required
          ? (_) => widget.rows.isEmpty ? 'أضف صفاً واحداً على الأقل' : null
          : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${widget.rows.length} ${widget.rows.length == 1 ? 'عنصر' : 'عناصر'}',
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
                ),
              ),
            for (int r = 0; r < widget.rows.length; r++)
              _editingRows.contains(r) ? _buildEditCard(r) : _buildViewCard(r),
            SizedBox(
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 16),
                label:
                    Text(widget.rows.isEmpty ? 'إضافة عنصر' : 'إضافة عنصر آخر'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Text(
                state.errorText!,
                style: const TextStyle(fontSize: 12, color: AppColors.rejected),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  NUMBER FIELD HELPERS
// ═══════════════════════════════════════════════════════════════════════

class _NumbersLoadingRow extends StatelessWidget {
  const _NumbersLoadingRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 13, color: AppColors.accent),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldErrorText extends StatelessWidget {
  const _FieldErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 13, color: AppColors.rejected),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.rejected,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS (same patterns as CreateDocumentScreen)
// ═══════════════════════════════════════════════════════════════════════

class _WorkflowModeSelector extends StatelessWidget {
  const _WorkflowModeSelector({
    required this.mode,
    required this.onChanged,
  });
  final WorkflowMode mode;
  final ValueChanged<WorkflowMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            isSelected: mode == WorkflowMode.sequential,
            icon: Icons.format_list_numbered,
            title: 'تسلسلي',
            subtitle: 'يعتمد كل شخص بعد الآخر بالترتيب.',
            onTap: () => onChanged(WorkflowMode.sequential),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeCard(
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.16)
                    : AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 20,
                  color: isSelected ? AppColors.accent : AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppColors.text)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.78)
                        : AppColors.text3)),
          ],
        ),
      ),
    );
  }
}
