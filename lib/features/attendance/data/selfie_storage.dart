import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Durable storage for attendance selfies (the pre-upload photos captured at
/// check-in/out). Kept in one place so the capture, sync, dismiss, and
/// startup-sweep paths all agree on where files live and how paths are
/// stored/resolved/deleted.
///
/// Files live under `<app-support>/attendance_selfies/`. App-support (not
/// Documents) on purpose: these transient files must not be swept into iCloud
/// backups on iOS. The picker writes into the OS cache, which aggressive
/// cleaners (MIUI etc.) may wipe before the record syncs, so every selfie is
/// copied here at capture time.

/// Subdirectory (relative to app-support) that persisted selfies live in.
const selfiesSubdir = 'attendance_selfies';

/// Capture limits used before an attendance selfie enters the offline queue.
///
/// 1600 px on the long edge keeps enough facial detail for a human attendance
/// reviewer while avoiding the multi-megapixel files produced by modern front
/// cameras. JPEG quality 85 is intentionally conservative: resizing provides
/// most of the size reduction without introducing distracting face artifacts.
const attendanceSelfieMaxDimension = 1600.0;
const attendanceSelfieJpegQuality = 85;

/// Copies a freshly-captured, capture-time-compressed selfie out of the
/// picker's cache into permanent app-support storage and returns the path to
/// store on the queue row.
///
/// The returned path is RELATIVE to the app-support directory (e.g.
/// `attendance_selfies/1720000000000_1a2b.jpg`), not absolute — see
/// [resolveSelfiePath] for why. [baseDir] overrides the destination for tests.
///
/// Throws if the copy fails (e.g. disk full); callers must abort the capture
/// rather than queue a fragile path.
Future<String> persistSelfieForUpload(File source, {Directory? baseDir}) async {
  final supportDir = baseDir ?? await getApplicationSupportDirectory();
  final selfiesDir = Directory(
    '${supportDir.path}${Platform.pathSeparator}$selfiesSubdir',
  );
  await selfiesDir.create(recursive: true);

  final sourceName = _basename(source.path);
  final dot = sourceName.lastIndexOf('.');
  final extension = dot == -1 ? '.jpg' : sourceName.substring(dot);
  final fileName = '${DateTime.now().millisecondsSinceEpoch}_'
      '${Random().nextInt(0x7fffffff).toRadixString(16)}$extension';

  // Copy rather than rename: a cross-directory rename is unreliable on some
  // Android storage layouts. The cache original is left for the OS to clean.
  await source.copy('${selfiesDir.path}${Platform.pathSeparator}$fileName');
  // Store RELATIVE to app-support, not absolute — see resolveSelfiePath.
  return '$selfiesSubdir${Platform.pathSeparator}$fileName';
}

/// Resolves a stored selfie path to an absolute path on the CURRENT device.
///
/// New rows store a path relative to the app-support directory. iOS re-creates
/// the app container (a new UUID) on every update/restore and migrates files
/// into it, so an absolute path captured under the old container stops
/// resolving even though the file survived — re-joining the relative path
/// against the current support dir survives that rotation. Legacy rows (from
/// the old cache-path behavior) and test fakes hold absolute paths; those are
/// returned unchanged and simply fail the existence check if truly gone.
Future<String> resolveSelfiePath(String selfiePath,
    {Directory? baseDir}) async {
  if (_isAbsolutePath(selfiePath)) return selfiePath;
  final supportDir = baseDir ?? await getApplicationSupportDirectory();
  return '${supportDir.path}${Platform.pathSeparator}$selfiePath';
}

/// Best-effort deletion of a persisted selfie. Never throws — a failed delete
/// (already gone, locked) must never disrupt the sync result or a dismissal.
void deleteSelfieQuietly(String absolutePath) {
  try {
    File(absolutePath).deleteSync();
  } catch (_) {
    // Already gone or locked — nothing to do.
  }
}

/// Deletes persisted selfies not referenced by any queue row.
///
/// Reclaims files orphaned when the process was killed between copying a selfie
/// and inserting its row, or between a successful sync and its per-record
/// cleanup — windows the OS never reclaims on its own in app-support storage.
/// [referencedFileNames] must be the basenames of every selfie still owned by
/// a queue row, across ALL users, so a shared device never wipes another
/// account's pending selfie. Best-effort: any failure is swallowed.
Future<void> sweepOrphanedSelfieFiles(
  Set<String> referencedFileNames, {
  Directory? baseDir,
}) async {
  try {
    final supportDir = baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory(
      '${supportDir.path}${Platform.pathSeparator}$selfiesSubdir',
    );
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (!referencedFileNames.contains(_basename(entity.path))) {
        deleteSelfieQuietly(entity.path);
      }
    }
  } catch (_) {
    // Best-effort — a failed sweep must never disrupt startup.
  }
}

/// Basename of [path], tolerant of either separator (picker/Dio paths can use
/// '/' even when Platform.pathSeparator is '\').
String selfieFileName(String path) => _basename(path);

String _basename(String path) => path.split('/').last.split('\\').last;

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true; // POSIX: Android, iOS
  // Windows drive path — only the test host; real devices are POSIX.
  return path.length >= 2 && path[1] == ':';
}
