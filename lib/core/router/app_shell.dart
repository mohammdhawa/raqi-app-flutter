import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/attendance/presentation/providers/attendance_capture_recovery.dart';
import '../../features/auth/presentation/widgets/session_staleness_notice.dart';
import '../../features/requests/presentation/providers/requests_providers.dart';
import '../theme/app_colors.dart';

/// The five-tab frame around every top-level screen.
///
/// Things that concern the whole app rather than one tab live here: the
/// offline-session warning, the count of decisions waiting on the user, and
/// the capture-recovery notice — so none of them depends on which tab the user
/// happens to be on.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Shows startup capture recovery's one-shot result — a check-in/out
  /// finished after the OS killed the app mid-camera, or one that could not
  /// be. Post-frame rather than ref.listen: recovery usually finishes before
  /// the shell first builds, and a listener never sees a value that was
  /// already set when it subscribed.
  void _showCaptureNotice(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(attendanceCaptureNoticeProvider);
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Identity check: several builds can queue a callback for one notice.
      if (!context.mounted ||
          !identical(ref.read(attendanceCaptureNoticeProvider), notice)) {
        return;
      }
      ref.read(attendanceCaptureNoticeProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              notice.isError ? AppColors.rejected : AppColors.approved,
          content: Text(notice.message),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _showCaptureNotice(context, ref);
    final pending = ref.watch(pendingDecisionsCountProvider);

    return Scaffold(
      body: Column(
        children: [
          const SessionStalenessNotice(),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Re-selecting the current tab returns it to its root.
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'دوامي',
          ),
          NavigationDestination(
            icon: _withCount(const Icon(Icons.assignment_outlined), pending),
            selectedIcon: _withCount(const Icon(Icons.assignment), pending),
            label: 'الطلبات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'راتبي',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'حسابي',
          ),
        ],
      ),
    );
  }

  /// No badge at zero: an empty «0» marker reads as something to look at.
  static Widget _withCount(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge(label: Text('$count'), child: icon);
  }
}
