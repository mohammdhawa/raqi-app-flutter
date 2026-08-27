import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doc_approval/core/storage/token_storage.dart';
import 'package:doc_approval/core/utils/app_constants.dart';
import 'package:doc_approval/shared/widgets/authed_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTokenStorage extends Fake implements TokenStorage {
  _FakeTokenStorage(this.token);
  final String? token;

  @override
  Future<String?> read() async => token;
}

void main() {
  group('document file URLs point at the authenticated API', () {
    test('the main file is served from /documents/{id}/file', () {
      final url = AppConstants.documentFileUrl(42);

      expect(url, '${AppConstants.baseUrl}/documents/42/file');
      expect(url, contains('/api/'));
      expect(url, isNot(contains('/storage/')));
    });

    test('an attachment is nested under its parent document', () {
      final url = AppConstants.documentAttachmentFileUrl(42, 7);

      expect(url, '${AppConstants.baseUrl}/documents/42/attachments/7/file');
      expect(url, isNot(contains('/storage/')));
    });

    test('the stamped copy keeps its existing endpoint', () {
      expect(
        AppConstants.documentStampedPdfUrl(42),
        '${AppConstants.baseUrl}/documents/42/stamped-pdf',
      );
    });

    test('the URL depends on ids only, never on file_path', () {
      // `file_path` / `stamped_file_path` are metadata. Two documents with
      // wildly different stored paths still resolve by id alone, which is
      // what makes the endpoint the single way in.
      expect(AppConstants.documentFileUrl(1),
          isNot(AppConstants.documentFileUrl(2)));
    });
  });

  group('no public /storage URL is built anywhere in the app', () {
    // The public disk is served straight off the filesystem by nginx with no
    // auth in front of it, so any `{host}/storage/{file_path}` URL the client
    // constructs is a permanent unauthenticated handle to that file. This
    // fails if the pattern — or the helper that used to build it — comes back.
    test('lib/ contains no storage-URL construction', () {
      final offenders = <String>[];
      final interpolatedStoragePath = RegExp(r'/storage/\$');

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('storageBase') ||
            interpolatedStoragePath.hasMatch(source)) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These files build a public /storage URL. Document bytes must '
            'come from the authenticated endpoints in AppConstants.',
      );
    });
  });

  group('AuthedNetworkImage', () {
    Future<void> pumpImage(WidgetTester tester, String? token) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(_FakeTokenStorage(token)),
          ],
          child: MaterialApp(
            home: AuthedNetworkImage(
              url: AppConstants.documentFileUrl(42),
              errorWidget: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    }

    testWidgets('sends the session token as a bearer header', (tester) async {
      await pumpImage(tester, 'secret-token');
      // One pump for the async token read to land.
      await tester.pump();

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );

      expect(image.httpHeaders, {'Authorization': 'Bearer secret-token'});
      expect(image.imageUrl, contains('/documents/42/file'));
    });

    testWidgets('requests nothing at all when there is no session',
        (tester) async {
      // Firing the request without a token would spend the attempt on a
      // guaranteed 401, which CachedNetworkImage then caches against the URL.
      await pumpImage(tester, null);
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
