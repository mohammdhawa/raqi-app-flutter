import 'dart:io';

import 'package:doc_approval/core/services/media_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// The disk half of the session wipe.
///
/// This exists because `CacheManager.emptyCache()` — the obvious call, and the
/// one this used to rely on — clears the cache INDEX and leaves the files:
/// `CacheStore._removeCachedFile` resolves `cacheObject.relativePath` (a bare
/// filename) against the process working directory, finds nothing there, and
/// deletes nothing. The bytes of a protected document survived every logout.
/// So the assertion here is deliberately about files on disk, not about the
/// manager reporting a miss.

/// The cache manager opens its index through platform channels that do not
/// exist under `flutter test`, so the index wipe is stubbed out. The bytes on
/// disk are what these tests are about, and what the index call demonstrably
/// does not remove.
Future<void> noIndexWipe() async {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDir;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('libCachedImageData_test');
  });

  tearDown(() {
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  File seedFile(String name) {
    final file = File('${cacheDir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]); // PNG magic
    return file;
  }

  test('cached image files are gone after a session ends', () async {
    final a = seedFile('9f1c-document-42.png');
    final b = seedFile('4b7e-selfie-7.jpg');
    expect(a.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);

    await clearCachedMedia(
      cacheDirectory: () async => cacheDir,
      emptyIndex: noIndexWipe,
    );

    expect(a.existsSync(), isFalse, reason: 'document image survived logout');
    expect(b.existsSync(), isFalse, reason: 'selfie survived logout');
    expect(cacheDir.listSync(), isEmpty);
  });

  test('nested entries go too', () async {
    final nested = Directory('${cacheDir.path}${Platform.pathSeparator}sub')
      ..createSync();
    final file = File('${nested.path}${Platform.pathSeparator}img.png')
      ..writeAsBytesSync([1, 2, 3]);

    await clearCachedMedia(
      cacheDirectory: () async => cacheDir,
      emptyIndex: noIndexWipe,
    );

    expect(file.existsSync(), isFalse);
    expect(cacheDir.listSync(), isEmpty);
  });

  // The folder itself stays: the cache manager resolves its directory handle
  // once, and the next download needs somewhere to land.
  test('the store directory survives so the cache can refill', () async {
    seedFile('img.png');

    await clearCachedMedia(
      cacheDirectory: () async => cacheDir,
      emptyIndex: noIndexWipe,
    );

    expect(cacheDir.existsSync(), isTrue);
  });

  // A logout must complete whether or not the cache cooperates.
  test('a missing cache directory is not an error', () async {
    final absent = Directory(
      '${cacheDir.path}${Platform.pathSeparator}not-created-yet',
    );

    await expectLater(
      clearCachedMedia(cacheDirectory: () async => absent, emptyIndex: noIndexWipe),
      completes,
    );
  });

  test('a failing directory lookup is swallowed', () async {
    await expectLater(
      clearCachedMedia(
        cacheDirectory: () async => throw const FileSystemException('nope'),
        emptyIndex: noIndexWipe,
      ),
      completes,
    );
  });
}
