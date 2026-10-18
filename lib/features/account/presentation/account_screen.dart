import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_info_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/card_kit.dart';
import '../../auth/presentation/providers/auth_controller.dart';

/// حسابي — the profile fields the API provides, placeholders for modules
/// without an API yet, and the account actions.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// Moved verbatim from `AttendanceScreen._confirmAndLogout`.
  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'خروج',
              style: TextStyle(color: AppColors.rejected),
            ),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('حسابي', style: AppTheme.heading1(color: AppColors.text)),
            const SizedBox(height: 16),
            _ProfileCard(
              name: user?.name ?? '',
              unit: [user?.departmentName, user?.sectionName]
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              email: user?.email,
            ),
            const SizedBox(height: 20),
            const _GroupTitle('الملف والمستندات'),
            const UnavailableCard(
              title: 'الملف الوظيفي',
              body: 'بياناتك الشخصية والوظيفية والعقد والشهادات.',
            ),
            const SizedBox(height: 10),
            const UnavailableCard(
              title: 'مستنداتي والتعاميم',
              body: 'عقودك وقراراتك والتعاميم الموجهة إليك.',
            ),
            const SizedBox(height: 10),
            const UnavailableCard(
              title: 'التقييم والتطوير',
              body: 'التقييم الدوري والأهداف والدورات.',
            ),
            const SizedBox(height: 20),
            const _GroupTitle('الحساب'),
            _ActionRow(
              icon: Icons.notifications_none_rounded,
              label: 'الإشعارات',
              onTap: () => context.push('/notifications'),
            ),
            const SizedBox(height: 10),
            _ActionRow(
              icon: Icons.info_outline_rounded,
              label: 'عن التطبيق',
              onTap: () => context.push('/about'),
            ),
            const SizedBox(height: 10),
            _ActionRow(
              icon: Icons.logout_rounded,
              label: 'تسجيل الخروج',
              color: AppColors.rejected,
              showChevron: false,
              onTap: () => _confirmAndLogout(context, ref),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'تطبيق الموظف · الإصدار ${isolateLtr(version)}',
                style: AppTheme.caption(color: AppColors.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: AppTheme.label(color: AppColors.text2)),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.unit,
    required this.email,
  });

  final String name;
  final String unit;
  final String? email;

  /// First letters of the first two words of the name.
  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => String.fromCharCode(w.runes.first)).join();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.rXl),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              child: initials.isEmpty
                  ? const Icon(Icons.person_outline,
                      size: 32, color: AppColors.textOnDark)
                  : Text(initials,
                      style: AppTheme.heading2(color: AppColors.textOnDark)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty)
                  Text(name, style: AppTheme.title(color: AppColors.text)),
                if (unit.isNotEmpty)
                  Text(unit, style: AppTheme.bodyS(color: AppColors.text2)),
                if (email != null && email!.isNotEmpty)
                  Text(email!,
                      textDirection: TextDirection.ltr,
                      style: AppTheme.caption(color: AppColors.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.text,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.rXl),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label, style: AppTheme.label(color: color))),
                if (showChevron)
                  const Icon(Icons.chevron_left_rounded,
                      size: 22, color: AppColors.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
