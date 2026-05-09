import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/user.dart';
import '../../data/users_repository.dart';

/// Modal bottom sheet that lets the user search for and pick approvers.
/// Returns the (possibly-reordered) list of selected users on close.
///
/// Note: relies on `/admin/users` per the docs — managers may get a 403
/// here. We surface a friendly message in that case rather than crashing.
class ApproverPickerSheet extends ConsumerStatefulWidget {
  const ApproverPickerSheet({super.key, required this.initialSelection});

  final List<User> initialSelection;

  @override
  ConsumerState<ApproverPickerSheet> createState() =>
      _ApproverPickerSheetState();
}

class _ApproverPickerSheetState
    extends ConsumerState<ApproverPickerSheet> {
  final _searchController = TextEditingController();
  late List<User> _selected;
  List<User> _results = [];
  bool _isLoading = true;
  ApiFailure? _error;

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initialSelection];
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(usersRepositoryProvider)
          .searchPotentialApprovers(search: _searchController.text.trim());
      if (!mounted) return;
      setState(() {
        // Hide the Chief — they are auto-added by the backend.
        _results = results.where((u) => !u.isChief).toList();
        _isLoading = false;
      });
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    } catch (_) {
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'اختيار المعتمدين',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text('تم (${_selected.length})'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_circle_left_outlined),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      // Special-case 403 for managers — explain why this is happening.
      if (_error!.code == ApiErrorCode.forbidden) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'لا تملك صلاحية عرض قائمة المستخدمين. تواصل مع المسؤول لإضافة نقطة وصول لقائمة المعتمدين.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                arabicMessageFor(_error!.code, fallback: _error!.message),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد نتائج.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final user = _results[i];
        final isSelected = _selected.any((u) => u.id == user.id);
        return Material(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _toggle(user),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text(
                      user.name.characters.first,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
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
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected ? AppColors.accent : AppColors.border,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
