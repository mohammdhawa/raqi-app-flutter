import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/leave_repository.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_section_header.dart';

/// Form for managers to submit a leave request. Start/end dates, optional
/// type and reason, and the approving manager (loaded from
/// `/attendance/leave-managers`). Shows a client-side warning when the
/// requested span exceeds the remaining balance, but still defers to the
/// API as the source of truth.
class LeaveRequestFormScreen extends ConsumerStatefulWidget {
  const LeaveRequestFormScreen({super.key});

  @override
  ConsumerState<LeaveRequestFormScreen> createState() =>
      _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState
    extends ConsumerState<LeaveRequestFormScreen> {
  final _leaveTypeController = TextEditingController();
  final _reasonController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  LeaveManager? _manager;

  bool _isSubmitting = false;
  String? _formError;
  Map<String, List<String>>? _fieldErrors;

  @override
  void dispose() {
    _leaveTypeController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Chargeable working days (Sun–Thu) in the selected span — the amount the
  /// backend deducts. `null` until both ends are picked and ordered.
  int? get _requestedDays {
    if (_startDate == null || _endDate == null) return null;
    if (_endDate!.isBefore(_startDate!)) return null;
    return workingDaysBetween(_startDate!, _endDate!);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final first = isStart ? now : (_startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: DateTime(now.year + 2, 12, 31),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // Keep end ≥ start.
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickManager() async {
    final managersAsync = ref.read(leaveManagersProvider);
    final managers = managersAsync.valueOrNull;
    if (managers == null || managers.isEmpty) {
      // Trigger a (re)load so the user can retry.
      ref.invalidate(leaveManagersProvider);
      return;
    }
    final selected = await showModalBottomSheet<LeaveManager>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ManagerPickerSheet(
        managers: managers,
        selectedId: _manager?.id,
      ),
    );
    if (selected != null) setState(() => _manager = selected);
  }

  Future<void> _submit() async {
    setState(() {
      _formError = null;
      _fieldErrors = null;
    });

    if (_startDate == null || _endDate == null) {
      setState(() => _formError = 'الرجاء تحديد تاريخ البداية والنهاية.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() =>
          _formError = 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية أو مساوياً له.');
      return;
    }
    if ((_requestedDays ?? 0) < 1) {
      setState(() => _formError =
          'الفترة المحددة لا تتضمن أي يوم عمل (الأحد – الخميس). يُرجى اختيار فترة تشمل يوم عمل واحداً على الأقل.');
      return;
    }
    if (_manager == null) {
      setState(() => _formError = 'الرجاء اختيار المدير المعتمد.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(leaveRepositoryProvider).create(
            startDate: _startDate!,
            endDate: _endDate!,
            managerId: _manager!.id,
            leaveType: _leaveTypeController.text.trim(),
            reason: _reasonController.text.trim(),
          );

      // Refresh the dependent surfaces.
      ref.read(myLeaveRequestsProvider.notifier).refresh();
      ref.invalidate(leaveBalanceProvider);
      ref.invalidate(approvedLeaveTodayProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.approved,
          content: Text('تم إرسال طلب الإجازة بنجاح — بانتظار موافقة المدير.'),
        ),
      );
      context.pop();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = failure.fieldErrors;
        _formError = arabicMessageFor(failure.code, fallback: failure.message);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    final balance = ref.watch(leaveBalanceProvider).valueOrNull;
    final requested = _requestedDays;
    // A picked span that resolves to 0 working days (e.g. Fri→Sat) is invalid:
    // the backend would reject it, so block submission client-side.
    final hasNoWorkingDays = requested != null && requested < 1;
    final exceedsBalance = balance != null &&
        requested != null &&
        requested > balance.remainingDays;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
              children: [
                // ── Dates ──
                const LeaveSectionHeader(
                  icon: Icons.date_range_outlined,
                  label: 'فترة الإجازة',
                  required: true,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'من',
                        value: _startDate == null
                            ? null
                            : df.format(_startDate!),
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'إلى',
                        value:
                            _endDate == null ? null : df.format(_endDate!),
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                if (requested != null && !hasNoWorkingDays) ...[
                  const SizedBox(height: 8),
                  Text(
                    'أيام العمل المحسوبة: $requested ${requested == 1 ? "يوم" : "أيام"} '
                    '(تُحتسب أيام العمل من الأحد إلى الخميس فقط)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text2,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ],
                if (hasNoWorkingDays) ...[
                  const SizedBox(height: 10),
                  const _WarningBanner(
                    text:
                        'الفترة المحددة لا تتضمن أي يوم عمل (الأحد – الخميس). '
                        'اختر فترة تشمل يوم عمل واحداً على الأقل.',
                  ),
                ],
                if (exceedsBalance) ...[
                  const SizedBox(height: 10),
                  _WarningBanner(
                    text:
                        'المدة المطلوبة ($requested يوم) تتجاوز رصيدك المتبقي '
                        '(${balance.remainingDays} يوم). يمكنك المتابعة، لكن قد '
                        'يرفض الطلب من قبل النظام.',
                  ),
                ],

                const SizedBox(height: 20),

                // ── Leave type (optional) ──
                const LeaveSectionHeader(
                  icon: Icons.label_outline,
                  label: 'نوع الإجازة (اختياري)',
                ),
                _TextField(
                  controller: _leaveTypeController,
                  hint: 'مثال: سنوية، مرضية، طارئة…',
                  errorText: _fieldErrors?['leave_type']?.first,
                ),

                const SizedBox(height: 20),

                // ── Reason (optional) ──
                const LeaveSectionHeader(
                  icon: Icons.edit_outlined,
                  label: 'السبب (اختياري)',
                ),
                _TextField(
                  controller: _reasonController,
                  hint: 'اكتب سبب طلب الإجازة…',
                  multiline: true,
                  errorText: _fieldErrors?['reason']?.first,
                ),

                const SizedBox(height: 20),

                // ── Approving manager ──
                const LeaveSectionHeader(
                  icon: Icons.verified_user_outlined,
                  label: 'المدير المعتمد',
                  required: true,
                ),
                _ManagerField(
                  manager: _manager,
                  onTap: _pickManager,
                ),
                _ManagersHint(errorText: _fieldErrors?['manager_id']?.first),

                if (_formError != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(text: _formError!),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        isSubmitting: _isSubmitting,
        onSubmit: (_isSubmitting || hasNoWorkingDays) ? null : _submit,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  HEADER
// ═══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 14),
      decoration: const BoxDecoration(color: AppColors.primary),
      child: Row(
        children: [
          const Spacer(),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'طلب إجازة جديد',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'يُرسل للمدير المعتمد للموافقة',
                style: TextStyle(fontSize: 11, color: AppColors.textOnDark2),
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
              child: const Icon(Icons.chevron_right,
                  color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FIELDS
// ═══════════════════════════════════════════════════════════════════════

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.text3)),
                  const SizedBox(height: 2),
                  Text(
                    value ?? 'اختر التاريخ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: value == null ? AppColors.text3 : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    this.hint,
    this.multiline = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String? hint;
  final bool multiline;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: multiline ? null : 1,
      minLines: multiline ? 3 : 1,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface,
      ),
    );
  }
}

class _ManagerField extends StatelessWidget {
  const _ManagerField({required this.manager, required this.onTap});

  final LeaveManager? manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              manager == null
                  ? Icons.person_search_outlined
                  : Icons.account_circle_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                manager?.name ?? 'اختر المدير المعتمد',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: manager == null ? AppColors.text3 : AppColors.text,
                ),
              ),
            ),
            const Icon(Icons.unfold_more_rounded,
                size: 20, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// Shows a hint / load-error for the managers list under the picker.
class _ManagersHint extends ConsumerWidget {
  const _ManagersHint({this.errorText});

  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managersAsync = ref.watch(leaveManagersProvider);
    return managersAsync.when(
      data: (managers) {
        if (errorText != null) {
          return _hint(errorText!, AppColors.rejected);
        }
        if (managers.isEmpty) {
          return _hint('لا يوجد مدراء متاحون للاعتماد حالياً.', AppColors.text3);
        }
        return const SizedBox.shrink();
      },
      loading: () => _hint('جارٍ تحميل المدراء…', AppColors.text3),
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => ref.invalidate(leaveManagersProvider),
          child: const Text(
            'تعذّر تحميل المدراء — اضغط لإعادة المحاولة.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.rejected,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  MANAGER PICKER SHEET
// ═══════════════════════════════════════════════════════════════════════

class _ManagerPickerSheet extends StatelessWidget {
  const _ManagerPickerSheet({required this.managers, this.selectedId});

  final List<LeaveManager> managers;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'اختر المدير المعتمد',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: managers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final m = managers[index];
                final selected = m.id == selectedId;
                return ListTile(
                  onTap: () => Navigator.pop(context, m),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(
                      m.name.isNotEmpty ? m.name.characters.first : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    m.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: m.departmentName != null
                      ? Text(m.departmentName!,
                          style: const TextStyle(fontSize: 12))
                      : null,
                  trailing: selected
                      ? const Icon(Icons.check_circle,
                          color: AppColors.approved)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BANNERS & BOTTOM BAR
// ═══════════════════════════════════════════════════════════════════════

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 20, color: AppColors.pendingText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.pendingText,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rejectedBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.rejected.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.rejected),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.rejected,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.isSubmitting, required this.onSubmit});

  final bool isSubmitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: AppColors.shActionBar,
      ),
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.rLg),
            ),
            elevation: 0,
          ),
          child: isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'إرسال الطلب',
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
