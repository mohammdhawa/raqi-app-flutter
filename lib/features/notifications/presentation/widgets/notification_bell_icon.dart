import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/notifications_controller.dart';

/// Bell button with an unread-count badge, styled for the app's dark
/// (`AppColors.primary`) headers by default; [onDarkBackground] `false` gives
/// the light variant (white 48 px square, outlined) for the home header.
/// Tapping it opens `/notifications`.
///
/// Drop this into any custom header row, alongside the screen's other
/// 36×36 icon buttons:
/// ```dart
/// Row(
///   children: const [
///     _HeaderIconBtn(icon: Icons.logout, onTap: onLogout),
///     SizedBox(width: 8),
///     NotificationBellIcon(),
///   ],
/// )
/// ```
///
/// Watching [unreadCountProvider] here — rather than in the parent header —
/// keeps rebuilds scoped to the badge when the count changes.
class NotificationBellIcon extends ConsumerWidget {
  const NotificationBellIcon({super.key, this.onDarkBackground = true});

  final bool onDarkBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);

    final size = onDarkBackground ? 36.0 : 48.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/notifications'),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: onDarkBackground
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(onDarkBackground ? 10 : 12),
                border: onDarkBackground
                    ? null
                    : Border.all(color: AppColors.border),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: onDarkBackground ? Colors.white : AppColors.primary,
                size: 20,
              ),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.rejected,
                    borderRadius: BorderRadius.circular(AppColors.pill),
                    border: Border.all(
                      color:
                          onDarkBackground ? AppColors.primary : Colors.white,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
