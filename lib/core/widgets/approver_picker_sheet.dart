import 'package:flutter/material.dart';

import '../errors/api_failure.dart';
import '../theme/app_colors.dart';

/// Modal bottom sheet for choosing a submission's approvers: search, tick,
/// confirm.
///
/// Generic over the type each form holds its approvers in — the document forms
/// select `User`s and the leave form selects `LeaveManager`s. Only the display
/// accessors and the candidate loader differ, so those are parameters and
/// everything else (the search, the selection model, the loading and error
/// states, the confirm bar) is shared.
///
/// **Eligibility is the caller's business, not this sheet's.** [loadCandidates]
/// returns exactly who may be picked, already filtered: the document forms drop
/// the chief because their workflow appends them itself, while the leave form
/// must keep the chief, who commonly closes an approval chain. Folding either
/// rule in here would silently impose it on the other feature.
///
/// Selection order is tap order, and it is preserved on the way out — the leave
/// chain is submitted in that order, and the form lets it be rearranged
/// afterwards.
class ApproverPickerSheet<T> extends StatefulWidget {
  const ApproverPickerSheet({
    super.key,
    required this.initialSelection,
    required this.loadCandidates,
    required this.idOf,
    required this.nameOf,
    this.departmentOf,
    this.sectionOf,
    this.maxSelection,
  });

  /// Who is already on the chain. Re-opening the sheet edits that selection
  /// rather than starting a new one, so nothing is lost by opening it to look.
  final List<T> initialSelection;

  /// Fetches the pickable candidates. Called on open and again on retry, so a
  /// roster that changed since the form loaded is picked up by re-opening the
  /// sheet — which is how a stale approver gets replaced after a 422.
  final Future<List<T>> Function() loadCandidates;

  final int Function(T approver) idOf;
  final String Function(T approver) nameOf;
  final String? Function(T approver)? departmentOf;
  final String? Function(T approver)? sectionOf;

  /// Ceiling the server also enforces, or null where there is none. At the
  /// limit the unpicked rows stop responding instead of letting the user build
  /// a selection that can only come back as a 422.
  final int? maxSelection;

  /// Present the picker. Returns the selection on confirm, or null when the
  /// sheet is dismissed — which callers must treat as "leave it alone", not as
  /// an empty selection.
  static Future<List<T>?> show<T>(
    BuildContext context, {
    required List<T> initial,
    required Future<List<T>> Function() loadCandidates,
    required int Function(T approver) idOf,
    required String Function(T approver) nameOf,
    String? Function(T approver)? departmentOf,
    String? Function(T approver)? sectionOf,
    int? maxSelection,
  }) {
    return showModalBottomSheet<List<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 40,
              offset: Offset(0, -10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ApproverPickerSheet<T>(
          initialSelection: initial,
          loadCandidates: loadCandidates,
          idOf: idOf,
          nameOf: nameOf,
          departmentOf: departmentOf,
          sectionOf: sectionOf,
          maxSelection: maxSelection,
        ),
      ),
    );
  }

  @override
  State<ApproverPickerSheet<T>> createState() => _ApproverPickerSheetState<T>();
}

class _ApproverPickerSheetState<T> extends State<ApproverPickerSheet<T>> {
  final _searchController = TextEditingController();
  late List<T> _selected;

  List<T> _allResults = [];
  List<T> _filteredResults = [];

  bool _isLoading = true;
  ApiFailure? _error;

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initialSelection];
    _searchController.addListener(_applyFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  bool get _atLimit =>
      widget.maxSelection != null && _selected.length >= widget.maxSelection!;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await widget.loadCandidates();
      if (!mounted) return;
      setState(() {
        _allResults = results;
        _isLoading = false;
      });
      _applyFilter();
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Approver picker failed to load: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = ApiFailure(
          code: ApiErrorCode.unknown,
          message: arabicMessageFor(ApiErrorCode.unknown),
        );
        _isLoading = false;
      });
    }
  }

  /// Filters over the loaded page, on every field the row displays, so a search
  /// never hides something the user can see.
  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredResults = List.of(_allResults);
        return;
      }
      _filteredResults = _allResults.where((approver) {
        final haystack = [
          widget.nameOf(approver),
          widget.departmentOf?.call(approver) ?? '',
          widget.sectionOf?.call(approver) ?? '',
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      }).toList();
    });
  }

  void _toggle(T approver) {
    final id = widget.idOf(approver);
    final index = _selected.indexWhere((s) => widget.idOf(s) == id);
    // Deselecting always works; only adding is capped.
    if (index < 0 && _atLimit) return;
    setState(() {
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(approver);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close,
                      size: 18, color: AppColors.text2),
                ),
              ),
              const Spacer(),
              const Text(
                'اختيار المعتمدين',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              decoration: const InputDecoration(
                hintText: 'بحث عن مستخدم...',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.text3),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: AppColors.text3),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        Expanded(child: _buildBody()),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_atLimit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'بلغت الحد الأقصى (${widget.maxSelection} معتمدين). '
                    'ألغِ اختيار أحدهم لإضافة غيره.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.pendingText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      key: const Key('confirm-approver-selection'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, _selected),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.4),
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppColors.rLg),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: const Text(
                        'تأكيد الاختيار',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentTint,
                        borderRadius: BorderRadius.circular(AppColors.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'مختار',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pendingText,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${_selected.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      if (_error!.code == ApiErrorCode.forbidden) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'لا تملك صلاحية عرض قائمة المستخدمين.\n'
              'تواصل مع المسؤول لإضافة نقطة وصول لقائمة المعتمدين.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2, fontSize: 13),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                arabicMessageFor(_error!.code, fallback: _error!.message),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text2, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredResults.isEmpty) {
      return Center(
        child: Text(
          _allResults.isEmpty
              ? 'لا يوجد معتمدون متاحون.'
              : 'لا توجد نتائج مطابقة للبحث.',
          style: const TextStyle(color: AppColors.text2, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredResults.length,
      itemBuilder: (_, i) {
        final approver = _filteredResults[i];
        final id = widget.idOf(approver);
        final isSelected = _selected.any((s) => widget.idOf(s) == id);
        return _buildRow(approver, isSelected);
      },
    );
  }

  Widget _buildRow(T approver, bool isSelected) {
    final department = widget.departmentOf?.call(approver);
    final section = widget.sectionOf?.call(approver);
    // Nothing more can be added at the limit, so an unpicked row says so by
    // dimming rather than by accepting a tap that does nothing.
    final blocked = !isSelected && _atLimit;

    return Opacity(
      opacity: blocked ? 0.45 : 1,
      child: GestureDetector(
        onTap: blocked ? null : () => _toggle(approver),
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x0D224167) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primary : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nameOf(approver),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (department != null && department.isNotEmpty)
                      Text(
                        'الادارة: $department',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                    if (section != null && section.isNotEmpty)
                      Text(
                        'القسم: $section',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.text2),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(widget.nameOf(approver)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// First letter of the first name plus first letter of the last. Guards the
  /// empty string a payload without a name would otherwise turn into a crash.
  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters.first;
    return '${parts.first.characters.first}${parts.last.characters.first}';
  }
}
