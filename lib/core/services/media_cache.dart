import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../errors/error_log.dart';

/// Where `CachedNetworkImage` keeps its downloads: a folder named after the
/// manager's cache key inside the temporary directory, exactly as
/// `IOFileSystem.createDirectory` builds it.
@visibleForTesting
Future<Directory> defaultImageCacheDirectory() async {
  final base = await getTemporaryDirectory();
  return Directory(
    '${base.path}${Platform.pathSeparator}${DefaultCacheManager.key}',
  );
}

/// Wipes every image byte this app has cached.
///
/// `CachedNetworkImage` stores what it downloads on disk, keyed by URL and
/// nothing else — not by account, not by token. That is fine for a public
/// asset and wrong for the ones this app shows: document files and attendance
/// selfies come from `auth:sanctum` endpoints, and once they are on disk they
/// render with no request at all. Left alone they outlive the session that was
/// allowed to fetch them, so a revoked user, or the next person to sign in on
/// a shared device, keeps seeing pages they can no longer request — the bearer
/// header on `AuthedNetworkImage` gates the download, not the replay.
///
/// **The files are deleted here rather than by `CacheManager.emptyCache()`,
/// which does not delete them.** `CacheStore._removeCachedFile` builds
/// `File(cacheObject.relativePath)` from a bare filename, so it resolves
/// against the process working directory (`/` on Android), `existsSync()`
/// answers false, and the entry is dropped from the index while the bytes stay
/// on disk. `emptyCache()` is still called — the index and its in-memory maps
/// have to agree with the now-empty folder, or the manager reports hits for
/// files that are gone — but it is the second step, not the one being relied
/// on. (flutter_cache_manager 3.4.1; re-check this when the package moves.)
///
/// Three layers, in the order that matters: the bytes, then the index that
/// points at them, then Flutter's cache of already-decoded frames — which
/// would otherwise keep painting an image whose file has just been deleted.
///
/// Best-effort by design: a session must end whether or not the cache
/// cooperates, so failures are logged (safely) and swallowed rather than
/// aborting a logout.
///
/// [cacheDirectory] and [emptyIndex] are injectable for tests only. The index
/// call is injectable because the manager opens its store eagerly and reports
/// the failure as an UNHANDLED async error when no platform channels exist —
/// a test that let it run would fail on the package's plumbing rather than on
/// what this function promises.
Future<void> clearCachedMedia({
  Future<Directory> Function()? cacheDirectory,
  Future<void> Function()? emptyIndex,
}) async {
  // 1. The bytes. Delete the folder's CONTENTS and leave the folder itself, so
  //    the cache manager's already-resolved directory handle stays valid and
  //    the next download has somewhere to land.
  try {
    final dir = await (cacheDirectory ?? defaultImageCacheDirectory)();
    var removed = 0;
    if (dir.existsSync()) {
      for (final entry in dir.listSync()) {
        await entry.delete(recursive: true);
        removed++;
      }
    }
    // Debug builds only — the path is an on-device location and release logs
    // are readable over adb. Worth printing at all because the failure mode
    // here is silence: if this ever stops running, or resolves to the wrong
    // folder, nothing else in the app looks different.
    if (kDebugMode) {
      debugPrint(
        'Cleared $removed entrie(s) from the image cache at ${dir.path} '
        '(exists: ${dir.existsSync()})',
      );
    }
  } catch (e, stack) {
    logUnexpected('Could not delete cached image files', e, stack);
  }

  // 2. The index, so nothing reports a hit for a file that no longer exists.
  try {
    await (emptyIndex ?? () => DefaultCacheManager().emptyCache())();
  } catch (e, stack) {
    logUnexpected('Could not empty the image cache index', e, stack);
  }

  // 3. The decoded frames. `clear()` drops idle entries; `clearLiveImages()`
  //    also releases the ones still attached to a widget, so an image on screen
  //    when the session ended is re-fetched (and now refused) instead of
  //    lingering.
  try {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  } catch (e, stack) {
    logUnexpected('Could not clear the in-memory image cache', e, stack);
  }
}
