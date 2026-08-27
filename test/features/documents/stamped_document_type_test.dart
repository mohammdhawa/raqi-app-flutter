import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GET /documents/{id}/file` streams `stamped_file_path ?: file_path`, so
/// once one approver has signed it returns a freshly rendered PDF whatever
/// was uploaded — while `file_mime` / `file_name` keep describing the upload.
/// Trusting those columns previewed PDF bytes in an image viewer and saved
/// them as `.jpg` / `.docx`.
void main() {
  Document doc({
    String? mime,
    String? name,
    String? path,
    String? stampedPath,
    int id = 42,
  }) =>
      Document(
        id: id,
        title: 'مستند',
        status: DocumentStatus.pending,
        workflowMode: WorkflowMode.sequential,
        createdAt: DateTime(2026, 8, 18),
        creator: User.empty(),
        workflows: const [],
        logs: const [],
        fileMime: mime,
        fileName: name,
        filePath: path,
        stampedFilePath: stampedPath,
      );

  group('an uploaded image', () {
    final before = doc(
      mime: 'image/jpeg',
      name: 'صورة.jpg',
      path: 'documents/abc.jpg',
    );
    final after = doc(
      mime: 'image/jpeg',
      name: 'صورة.jpg',
      path: 'documents/abc.jpg',
      stampedPath: 'stamped/abc-signed.pdf',
    );

    test('is previewed as an image before stamping', () {
      expect(before.servesStampedFile, isFalse);
      expect(before.servedIsImage, isTrue);
      expect(before.servedIsPdf, isFalse);
      expect(before.servedMime, 'image/jpeg');
      expect(before.servedFileName, 'صورة.jpg');
    });

    test('becomes a PDF once stamped, and is no longer previewed as an image',
        () {
      expect(after.servesStampedFile, isTrue);
      // The regression: an image viewer handed PDF bytes renders nothing.
      expect(after.servedIsImage, isFalse);
      expect(after.servedIsPdf, isTrue);
      expect(after.servedMime, 'application/pdf');
    });

    test('downloads as .pdf once stamped, not .jpg', () {
      expect(after.servedFileName, 'صورة.pdf');
      expect(after.servedFileName, isNot(endsWith('.jpg')));
    });
  });

  group('an uploaded Word document', () {
    final before = doc(
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      name: 'تقرير.docx',
      path: 'documents/report.docx',
    );
    final after = doc(
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      name: 'تقرير.docx',
      path: 'documents/report.docx',
      stampedPath: 'stamped/report-signed.pdf',
    );

    test('is neither image nor PDF before stamping', () {
      expect(before.servedIsImage, isFalse);
      expect(before.servedIsPdf, isFalse);
      expect(before.servedFileName, 'تقرير.docx');
    });

    test('is served and named as a PDF once stamped', () {
      expect(after.servedIsPdf, isTrue);
      expect(after.servedIsImage, isFalse);
      expect(after.servedMime, 'application/pdf');
      // Saving PDF bytes as .docx makes a file Word refuses to open.
      expect(after.servedFileName, 'تقرير.pdf');
    });
  });

  group('an uploaded PDF', () {
    test('is a PDF either way, and keeps its name', () {
      final before = doc(
          mime: 'application/pdf', name: 'عقد.pdf', path: 'documents/c.pdf');
      final after = doc(
        mime: 'application/pdf',
        name: 'عقد.pdf',
        path: 'documents/c.pdf',
        stampedPath: 'stamped/c-signed.pdf',
      );

      expect(before.servedIsPdf, isTrue);
      expect(after.servedIsPdf, isTrue);
      expect(before.servedFileName, 'عقد.pdf');
      expect(after.servedFileName, 'عقد.pdf');
    });
  });

  group('filename fallbacks', () {
    test('falls back to the stored path basename when file_name is absent', () {
      final d = doc(name: null, path: 'documents/2026/abc123.jpg');
      expect(d.servedFileName, 'abc123.jpg');
    });

    test('the basename fallback is also forced to .pdf when stamped', () {
      final d = doc(
        name: null,
        path: 'documents/2026/abc123.jpg',
        stampedPath: 'stamped/x.pdf',
      );
      expect(d.servedFileName, 'abc123.pdf');
    });

    test('falls back to the document id when nothing else is known', () {
      expect(doc(name: null, path: null, id: 7).servedFileName, 'document-7');
      expect(
        doc(name: null, path: null, stampedPath: 'stamped/x.pdf', id: 7)
            .servedFileName,
        'document-7.pdf',
      );
    });

    test('a name with no extension simply gains .pdf when stamped', () {
      final d = doc(name: 'مسح ضوئي', stampedPath: 'stamped/x.pdf');
      expect(d.servedFileName, 'مسح ضوئي.pdf');
    });

    test('a leading-dot name is not mistaken for an extension', () {
      final d = doc(name: '.hidden', stampedPath: 'stamped/x.pdf');
      expect(d.servedFileName, '.hidden.pdf');
    });
  });

  group('type detection without file_mime', () {
    test('falls back to the path extension', () {
      expect(doc(mime: null, path: 'documents/a.pdf').servedIsPdf, isTrue);
      expect(doc(mime: null, path: 'documents/a.png').servedIsImage, isTrue);
      expect(doc(mime: null, path: 'documents/a.docx').servedIsPdf, isFalse);
      expect(doc(mime: null, path: 'documents/a.docx').servedIsImage, isFalse);
    });

    test('a stamped copy still wins over the path extension', () {
      final d = doc(
        mime: null,
        path: 'documents/a.png',
        stampedPath: 'stamped/a.pdf',
      );
      expect(d.servedIsPdf, isTrue);
      expect(d.servedIsImage, isFalse);
    });
  });
}
