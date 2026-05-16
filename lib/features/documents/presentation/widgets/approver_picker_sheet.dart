import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/user.dart';
import '../../data/users_repository.dart';

/// Modal bottom sheet that lets the user search for and pick approvers.
/// Returns the (possibly-reordered) list of selected users on close.
///
/// Use [ApproverPickerSheet.show] to present the sheet with the correct
/// constraints, shape, and shadow.
class ApproverPickerSheet extends ConsumerStatefulWidget {
  const ApproverPickerSheet({super.key, required this.initialSelection});

  final List<User> initialSelection;

  /// Present the picker as a modal bottom sheet.
  /// Returns the selected list on confirm, or `null` on dismiss.
  static Future<List<User>?> show(
    BuildContext context, {
    List<User> initial = const [],
  }) {
    return showModalBottomSheet<List<User>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000), // 20 %
              blurRadius: 40,
              offset: Offset(0, -10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ApproverPickerSheet(initialSelection: initial),
      ),
    );
  }

  @override
  ConsumerState<ApproverPickerSheet> createState() =>
      _ApproverPickerSheetState();
}

class _ApproverPickerSheetState extends ConsumerState<ApproverPickerSheet> {
  final _searchController = TextEditingController();
  late List<User> _selected;

  /// Full list returned by the API.
  List<User> _allResults = [];

  /// Filtered subset shown in the list view.
  List<User> _filteredResults = [];

  bool _isLoading = true;
  ApiFailure? _error;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initialSelection];

    _searchController.addListener(_applyFilter);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(usersRepositoryProvider);
      final results = await repo.searchPotentialApprovers(search: '');
      if (!mounted) return;

      final filtered = results.where((u) => !u.isChief).toList();

      setState(() {
        _allResults = filtered;
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
      debugPrint('❌ _loadUsers error: $e\n$stackTrace');
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

  /// Real-time local filter by name OR email, case-insensitive.
  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredResults = List.of(_allResults);
      } else {
        _filteredResults = _allResults.where((u) {
          final name = u.name.toLowerCase();
          final email = (u.email ?? '').toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      }
    });
  }

  // ── Selection ──────────────────────────────────────────────────────

  void _toggle(User user) {
    setState(() {
      final idx = _selected.indexWhere((u) => u.id == user.id);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(user);
      }
    });
  }

  void _close() => Navigator.pop(context, _selected);
  void _dismiss() => Navigator.pop(context);

  // ── Helpers ────────────────────────────────────────────────────────

  /// Initials = first letter of first name + first letter of last name.
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first.characters.first}${parts.last.characters.first}';
    }
    return parts.first.characters.first;
  }

  /// Subtitle built from available User fields.
  /// TODO: if your User model gains a role / jobTitle field, prepend it
  /// here so rows read "{role} · {email}".
  String _subtitle(User user) {
    return (user.email != null && user.email!.isNotEmpty) ? user.email! : '';
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        // ── Drag handle ──────────────────────────────────────────────
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

        // ── Header row ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              // Close button
              GestureDetector(
                onTap: _dismiss,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.text2,
                  ),
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

        // ── Search field ─────────────────────────────────────────────
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

        // ── Body ─────────────────────────────────────────────────────
        Expanded(child: _buildBody()),

        // ── Footer ───────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Confirm button
              IgnorePointer(
                ignoring: _selected.isEmpty,
                child: Opacity(
                  opacity: _selected.isEmpty ? 0.4 : 1.0,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _close,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppColors.rLg),
                        ),
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      child: const Text(
                        'تأكيد الاختيار',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Count pill — hidden when nothing selected
              if (_selected.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        ),
      ],
    );
  }

  // ── Body states ────────────────────────────────────────────────────

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
              'لا تملك صلاحية عرض قائمة المستخدمين.\nتواصل مع المسؤول لإضافة نقطة وصول لقائمة المعتمدين.',
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
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredResults.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد نتائج.',
          style: TextStyle(color: AppColors.text2, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filteredResults.length,
      itemBuilder: (_, i) {
        final user = _filteredResults[i];
        final isSelected = _selected.any((u) => u.id == user.id);
        return _buildUserRow(user, isSelected);
      },
    );
  }

  // ── User row ───────────────────────────────────────────────────────

  Widget _buildUserRow(User user, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggle(user),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0x0D224167) // rgba(34,65,103,0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // ── Checkbox ──
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.borderStrong,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),

            // ── Name & subtitle ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (_subtitle(user).isNotEmpty)
                    Text(
                      _subtitle(user),
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
            const SizedBox(width: 12),

            // ── Avatar ──
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(user.name),
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
    );
  }
}