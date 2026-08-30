import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_controller.dart';

/// Visible warning shown while the app is using a cached profile offline.
class SessionStalenessNotice extends ConsumerWidget {
  const SessionStalenessNotice({super.key});

  static const message =
      'أنت تعمل دون اتصال. قد تكون صلاحيات الحساب قديمة حتى عودة الشبكة.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStale = ref.watch(
      currentUserProvider.select((user) => user?.sessionStale ?? false),
    );

    if (!isStale) return const SizedBox.shrink();

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Container(
        key: const Key('session-staleness-indicator'),
        width: double.infinity,
        color: const Color(0xFFFFF3CD),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: Color(0xFF7A5A00)),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B4E00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
