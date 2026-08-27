import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/attendance/data/leave_type_cache.dart';
import '../errors/error_log.dart';
import 'media_cache.dart';

/// One wipe of one cache.
typedef CacheWipe = Future<void> Function();

/// Everything the app cached on behalf of a session, dropped as one step.
///
/// This is called from [AuthController] — the code that owns "the session
/// ended" — rather than from a lifecycle listener watching for the state
/// change. The listener version looked equivalent and was not: it depended on
/// a subscription registered in the root widget's `initState`, nothing proved
/// it was ever registered, and when it silently failed to run, protected
/// document images stayed on disk through every logout with no symptom
/// anywhere. Sitting on the logout path instead means there is nothing to
/// register, the caller can await it, and a test can assert that signing out
/// empties the caches.
///
/// Each wipe is independent: one failing store must not strand the others,
/// and none of them may stop a logout.
class SessionCleanup {
  const SessionCleanup(this._wipes);

  final List<CacheWipe> _wipes;

  Future<void> run() async {
    for (final wipe in _wipes) {
      try {
        await wipe();
      } catch (e, stack) {
        logUnexpected('Session cache wipe failed', e, stack);
      }
    }
  }
}

final sessionCleanupProvider = Provider<SessionCleanup>((ref) {
  final leaveTypes = ref.watch(leaveTypeCacheProvider);
  return SessionCleanup([
    // Cached document images and selfies: fetched under a bearer token, but
    // replayed from disk with no request at all.
    clearCachedMedia,
    // The leave-type vocabulary: scoped to the user who fetched it.
    leaveTypes.clear,
  ]);
});
