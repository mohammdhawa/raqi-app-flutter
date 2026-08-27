import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/leave_repository.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_section_header.dart';

/// Form for submitting a leave request. Start/end dates, the leave type
/// (picked from the HR vocabulary), a reason, and the approving manager
/// (loaded from `/attendance/leave-managers`).
///
/// The type carries `deducts_balance`, which decides whether the days cost
/// the employee anything — so the balance warning below is gated on it, and
/// the type is never sent as free text (see [LeaveRepository.create]).
class LeaveRequestFormScreen extends ConsumerStatefulWidget {
  const LeaveRequestFormScreen({super.key});

  @override
  ConsumerState<LeaveRequestFormScreen> createState() =>
      _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState
    extends ConsumerState<LeaveRequestFormScreen> {
  final _reasonController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  LeaveType? _leaveType;
  LeaveManager? _manager;

  bool _isSubmitting = false;
  String? _formError;
  Map<String, List<String>>? _fieldErrors;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// Working days in the selected span — the number the backend counts.
  /// `null` until both ends are picked and ordered. A preview: the server's
  /// `requested_days` on the response is what actually applies.
  int? get _requestedDays {
    if (_startDate == null || _endDate == null) return null;
    if (_endDate!.isBefore(_startDate!)) return null;
    return workingDaysBetween(_startDate!, _endDate!);
  }

  /// The types on offer — from the network, or from the local cache when the
  /// network read failed. Empty while they load and after a failure with
  /// nothing cached.
  List<LeaveType> get _availableTypes =>
      ref.read(leaveTypesProvider).valueOrNull ?? const [];

  /// Whether the form is at a dead end: no vocabulary, so no type can be
  /// picked and therefore nothing can be submitted.
  ///
  /// Submitting untyped is NOT the fallback. The backend files a request with
  /// no `leave_type_id` as balance-deducting and skips the type's
  /// required-reason rule, so an employee filing sick leave here would silently
  /// be charged annual days. Failing loudly and letting them retry is the only
  /// safe behaviour: the request can wait, the balance cannot be un-spent.
  bool get _typesUnavailable => _availableTypes.isEmpty;

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial =
        isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
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

  Future<void> _pickLeaveType() async {
    final types = _availableTypes;
    if (types.isEmpty) {
      // Nothing to offer — trigger a (re)load so the user can retry.
      ref.invalidate(leaveTypesProvider);
      return;
    }
    final selected = await showModalBottomSheet<LeaveType>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LeaveTypePickerSheet(
        types: types,
        selectedId: _leaveType?.id,
      ),
    );
    if (selected == null) return;
    setState(() {
      _leaveType = selected;
      // The previous type's errors no longer describe anything on screen.
      _fieldErrors = null;
      _formError = null;
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
      setState(() => _formError =
          'تاريخ النهاية يجب أن يكون بعد تاريخ البداية أو مساوياً له.');
      return;
    }
    if ((_requestedDays ?? 0) < 1) {
      setState(() => _formError =
          'الفترة المحددة لا تتضمن أي يوم عمل. يُرجى اختيار فترة تشمل يوم عمل واحداً على الأقل.');
      return;
    }
    // Never submit without a type. See [_typesUnavailable]: an untyped request
    // is filed as deducting, so letting one through would charge annual days
    // for what the employee meant to take as sick or unpaid leave.
    if (_leaveType == null) {
      setState(() => _formError = _typesUnavailable
          ? 'تعذّر تحميل أنواع الإجازات، ولا يمكن إرسال الطلب دون تحديد النوع '
              '(وإلا احتُسب من رصيدك). تحقّق من الاتصال ثم أعد المحاولة.'
          : 'الرجاء اختيار نوع الإجازة.');
      return;
    }
    // Mirrors the type's `requires_reason`, which the backend enforces with a
    // 422 on `reason`. Asking here saves a round trip on a field the user is
    // already looking at.
    if (_leaveType?.requiresReason == true &&
        _reasonController.text.trim().isEmpty) {
      setState(() {
        _fieldErrors = {
          'reason': ['نوع الإجازة (${_leaveType!.label}) يتطلب ذكر السبب.'],
        };
      });
      return;
    }
    if (_manager == null) {
      setState(() => _formError = 'الرجاء اختيار المدير المعتمد.');
      return;
    }
    // Segregation of duties. The picker no longer offers the current user
    // (see leaveManagersProvider), but a selection made before that list
    // resolved — or restored state — must not slip past: the backend answers
    // 422 on `manager_id`, and saying so here beats a round trip.
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (currentUserId != null && _manager!.id == currentUserId) {
      setState(() {
        _manager = null;
        _fieldErrors = {
          'manager_id': [
            'لا يمكنك اعتماد إجازتك بنفسك. اختر مديراً أو رئيساً آخر.'
          ],
        };
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(leaveRepositoryProvider).create(
            startDate: _startDate!,
            endDate: _endDate!,
            managerId: _manager!.id,
            leaveTypeId: _leaveType!.id,
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
      // A 422 naming the type means this device's vocabulary is stale — the
      // type was retired, or is no longer offered to employees. Refetch so
      // the picker stops offering something the server rejects.
      final typeRejected = failure.fieldErrors?.containsKey('leave_type') ==
              true ||
          failure.fieldErrors?.containsKey('leave_type_id') == true;
      if (typeRejected) {
        setState(() => _leaveType = null);
        ref.invalidate(leaveTypesProvider);
      }
      // The balance the warning was based on may be out of date — refresh it
      // so the card and the next preview agree with the server.
      ref.invalidate(leaveBalanceProvider);
      setState(() {
        _fieldErrors = failure.fieldErrors;
        // This endpoint's business rules come back in English with no `error`
        // code, so translate the known ones before the generic fallback.
        _formError = arabicLeaveRuleMessage(failure.message) ??
            arabicMessageFor(failure.code, fallback: failure.message);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    final balance = ref.watch(leaveBalanceProvider).valueOrNull;
    // Watched (not just read) so the picker and its hint rebuild when the
    // vocabulary loads, fails, or is refetched after a rejected type.
    final typesAsync = ref.watch(leaveTypesProvider);
    final requested = _requestedDays;
    // A span the calendar resolves to 0 working days is one the backend
    // rejects, so block submission client-side. Unreachable for an ordered
    // span while every day is a working day — kept as the guard for a
    // calendar that skips days again, and harmless meanwhile.
    final hasNoWorkingDays = requested != null && requested < 1;
    // Only a deducting type can exceed the balance. A sick, unpaid or
    // bereavement request is never blocked by an exhausted allocation — the
    // backend stopped checking it, and warning here would talk the employee
    // out of leave they are entitled to. Until a type is picked, assume
    // deducting: that is what an untyped request is filed as.
    final deducts = _leaveType?.deductsBalance ?? true;
    final exceedsBalance = deducts &&
        balance != null &&
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
                        value:
                            _startDate == null ? null : df.format(_startDate!),
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'إلى',
                        value: _endDate == null ? null : df.format(_endDate!),
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                if (requested != null && !hasNoWorkingDays) ...[
                  const SizedBox(height: 8),
                  Text(
                    'أيام العمل المحسوبة: $requested ${requested == 1 ? "يوم" : "أيام"} '
                    '(تُحتسب جميع أيام الفترة المحددة)',
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
                    text: 'الفترة المحددة لا تتضمن أي يوم عمل. '
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

                // ── Leave type ──
                const LeaveSectionHeader(
                  icon: Icons.label_outline,
                  label: 'نوع الإجازة',
                  required: true,
                ),
                _LeaveTypeField(
                  type: _leaveType,
                  enabled: typesAsync.valueOrNull?.isNotEmpty ?? false,
                  onTap: _pickLeaveType,
                ),
                _LeaveTypeHint(
                  errorText: _fieldErrors?['leave_type']?.first ??
                      _fieldErrors?['leave_type_id']?.first,
                ),
                // The consequence the employee actually cares about: whether
                // these days come out of their balance. Read off the type,
                // never off its name.
                if (_leaveType != null) ...[
                  const SizedBox(height: 10),
                  _BalanceImpactBanner(
                    deducts: _leaveType!.deductsBalance,
                    days: hasNoWorkingDays ? null : requested,
                  ),
                ],

                const SizedBox(height: 20),

                // ── Reason (required for some types) ──
                LeaveSectionHeader(
                  icon: Icons.edit_outlined,
                  label: _leaveType?.requiresReason == true
                      ? 'السبب'
                      : 'السبب (اختياري)',
                  required: _leaveType?.requiresReason == true,
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
        // Disabled with no vocabulary: there is no type to pick, and a request
        // sent without one would be charged to the balance. The hint under the
        // picker carries the retry.
        onSubmit: (_isSubmitting || hasNoWorkingDays || _typesUnavailable)
            ? null
            : _submit,
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
  const _DateField(
      {required this.label, required this.value, required this.onTap});

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

/// The leave-type picker trigger. Mirrors [_ManagerField] — the type is a
/// choice from a server-owned list, not free text, so it reads as a picker.
class _LeaveTypeField extends StatelessWidget {
  const _LeaveTypeField({
    required this.type,
    required this.enabled,
    required this.onTap,
  });

  final LeaveType? type;

  /// False while the vocabulary is loading or after it failed to load — the
  /// field then reads as unavailable instead of opening an empty sheet.
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
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
                type == null ? Icons.label_outline : Icons.label,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type?.label ?? 'اختر نوع الإجازة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: type == null ? AppColors.text3 : AppColors.text,
                  ),
                ),
              ),
              const Icon(Icons.unfold_more_rounded,
                  size: 20, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading / error / validation hint under the type picker — mirrors
/// [_ManagersHint].
///
/// When the vocabulary can't be reached the hint says the request cannot be
/// sent and offers a retry, rather than offering to send it untyped: the
/// backend would file that as balance-deducting and skip the type's
/// required-reason rule, which is precisely the outcome the picker exists to
/// prevent.
class _LeaveTypeHint extends ConsumerWidget {
  const _LeaveTypeHint({this.errorText});

  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(leaveTypesProvider);
    return typesAsync.when(
      data: (types) {
        if (errorText != null) return _hint(errorText!, AppColors.rejected);
        if (types.isEmpty) return _retry(ref, 'لا توجد أنواع إجازات متاحة');
        return const SizedBox.shrink();
      },
      loading: () => _hint('جارٍ تحميل أنواع الإجازات…', AppColors.text3),
      error: (_, __) => _retry(ref, 'تعذّر تحميل أنواع الإجازات'),
    );
  }

  Widget _retry(WidgetRef ref, String reason) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => ref.invalidate(leaveTypesProvider),
          child: Text(
            '$reason — اضغط لإعادة المحاولة. لا يمكن إرسال الطلب قبل تحديد '
            'نوع الإجازة.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.rejected,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      );

  Widget _hint(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );
}

/// States, in one line, whether the selected type costs balance days — the
/// single thing the employee needs to know before submitting.
class _BalanceImpactBanner extends StatelessWidget {
  const _BalanceImpactBanner({required this.deducts, this.days});

  final bool deducts;

  /// The working-day count, when a valid span is picked.
  final int? days;

  @override
  Widget build(BuildContext context) {
    final (text, color, bg, icon) = deducts
        ? (
            days == null
                ? 'ستُخصم أيام هذه الإجازة من رصيدك.'
                : 'ستُخصم $days ${days == 1 ? "يوم" : "أيام"} من رصيدك.',
            AppColors.pendingText,
            AppColors.pendingBg,
            Icons.remove_circle_outline,
          )
        : (
            'لا تُخصم هذه الإجازة من رصيدك.',
            AppColors.approvedText,
            AppColors.approvedBg,
            Icons.verified_outlined,
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
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
          return _hint(
              'لا يوجد مدراء متاحون للاعتماد حالياً.', AppColors.text3);
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
//  LEAVE TYPE PICKER SHEET
// ═══════════════════════════════════════════════════════════════════════

/// The type picker. [types] arrives in the backend's creation order, which is
/// the intended display order — it is rendered as given and never re-sorted
/// locally (there is no `sort_order` to sort by, and re-ordering would put a
/// newly added type somewhere HR did not choose).
class _LeaveTypePickerSheet extends StatelessWidget {
  const _LeaveTypePickerSheet({required this.types, this.selectedId});

  final List<LeaveType> types;
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
                'اختر نوع الإجازة',
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
              itemCount: types.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final t = types[index];
                final selected = t.id == selectedId;
                return ListTile(
                  onTap: () => Navigator.pop(context, t),
                  leading: Icon(
                    t.deductsBalance
                        ? Icons.remove_circle_outline
                        : Icons.verified_outlined,
                    color: t.deductsBalance
                        ? AppColors.pendingText
                        : AppColors.approved,
                  ),
                  title: Text(
                    t.label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    t.deductsBalance
                        ? 'تُخصم من الرصيد'
                        : 'لا تُخصم من الرصيد',
                    style: const TextStyle(fontSize: 12),
                  ),
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
