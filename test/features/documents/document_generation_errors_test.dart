import 'dart:io';

import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/core/utils/app_constants.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/documents/data/documents_repository.dart';
import 'package:doc_approval/features/documents/data/users_repository.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/documents/domain/document_template.dart';
import 'package:doc_approval/features/documents/presentation/screens/generated_document_form_screen.dart';
import 'package:doc_approval/features/documents/presentation/widgets/approver_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeDocumentsRepository extends Fake implements DocumentsRepository {
  _FakeDocumentsRepository({this.counters, this.failure});

  final DocumentCounters? counters;

  /// Thrown by [createGenerated] when set.
  Object? failure;

  int createCalls = 0;

  @override
  Future<DocumentCounters> fetchNextCounters() async =>
      counters ??
      const DocumentCounters(
        departmentId: 1,
        exportNextNumber: 5,
        exportIsInitialized: true,
        importNextNumber: null,
      );

  @override
  Future<Document> createGenerated({
    required int templateId,
    required String title,
    String? description,
    required Map<String, dynamic> fieldValues,
    required WorkflowMode workflowMode,
    required List<int> approverIds,
    int? exportNumber,
    int? importNumber,
    List<File> attachments = const [],
  }) async {
    createCalls++;
    final error = failure;
    if (error != null) throw error;
    throw StateError('no outcome configured');
  }
}

class _FakeUsersRepository extends Fake implements UsersRepository {
  int searchCalls = 0;

  @override
  Future<List<User>> searchPotentialApprovers({String? search}) async {
    searchCalls++;
    return const [
      User(id: 2, name: 'مدير أول', email: 'm1@al-raqi.sa', role: 'manager'),
      User(id: 3, name: 'مدير ثانٍ', email: 'm2@al-raqi.sa', role: 'manager'),
    ];
  }
}

void main() {
  final template = DocumentTemplate(
    id: 1,
    name: 'طلب شراء',
    slug: 'purchase',
    type: 'purchase',
    layoutKey: 'default',
    fieldsSchema: const [],
  );

  /// Pumps the generated-document form inside a router, so the killswitch's
  /// navigation away from the form has somewhere to go.
  Future<_FakeDocumentsRepository> pumpForm(
    WidgetTester tester, {
    required Object failure,
    DocumentCounters? counters,
  }) async {
    final repo = _FakeDocumentsRepository(counters: counters, failure: failure);
    final router = GoRouter(
      initialLocation: '/generate',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('شاشة المستندات')),
        ),
        GoRoute(
          path: '/generate',
          builder: (_, __) => GeneratedDocumentFormScreen(template: template),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsRepositoryProvider.overrideWithValue(repo),
          usersRepositoryProvider.overrideWithValue(_FakeUsersRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  /// Chooses an approver through the real picker sheet, then submits.
  Future<void> pickApproverAndSubmit(WidgetTester tester) async {
    // The form is a long lazy ListView, so the approver button has to be
    // scrolled into existence before it can be tapped.
    await tester.scrollUntilVisible(
      find.text('اختيار المعتمدين'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختيار المعتمدين'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('مدير أول'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الاختيار'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إنشاء وإرسال للاعتماد'));
    await tester.pumpAndSettle();
  }

  /// Scrolls back up the lazy ListView until [finder] has been built again.
  Future<void> scrollUpTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('document generation killswitch', () {
    testWidgets('a 403 document_generation_disabled explains and leaves',
        (tester) async {
      const backendMessage = 'إنشاء المستندات من القوالب متوقف حالياً.';
      final repo = await pumpForm(
        tester,
        failure: ApiFailure(
          code: ApiErrorCode.documentGenerationDisabled,
          message: backendMessage,
          statusCode: 403,
        ),
      );

      await pickApproverAndSubmit(tester);

      // The backend's own wording is what the user is told.
      expect(find.textContaining(backendMessage), findsOneWidget);
      // …and it points at the flow that still works.
      expect(find.textContaining('يمكنك إنشاء مستند برفع ملف'), findsOneWidget);

      // Exactly one attempt: the refusal stands until an admin re-enables the
      // feature, so retrying it automatically would only burn requests.
      expect(repo.createCalls, 1);

      // Dismiss the notice — the stale template form is left behind.
      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();

      expect(find.text('شاشة المستندات'), findsOneWidget);
      expect(find.byType(GeneratedDocumentFormScreen), findsNothing);
    });
  });

  group('export-number business rules', () {
    testWidgets('a duplicate export number is reported on that field',
        (tester) async {
      const backendMessage = 'رقم الصادر 5 مستخدم مسبقاً في هذا القسم.';
      await pumpForm(
        tester,
        failure: ApiFailure(
          code: ApiErrorCode.duplicateExportNumber,
          message: backendMessage,
          statusCode: 422,
        ),
      );

      await pickApproverAndSubmit(tester);
      // The export field sits above the approver button we scrolled to.
      await scrollUpTo(tester, find.text(backendMessage));

      expect(find.text(backendMessage), findsOneWidget);
      // Still on the form so the number can be corrected in place.
      expect(find.byType(GeneratedDocumentFormScreen), findsOneWidget);
    });

    testWidgets('an uninitialised counter asks for a starting number',
        (tester) async {
      const backendMessage =
          'هذا أول مستند في القسم، يرجى إدخال رقم الصادر/الوارد لتحديد نقطة البداية.';
      await pumpForm(
        tester,
        failure: ApiFailure(
          code: ApiErrorCode.counterNotInitialized,
          message: backendMessage,
          statusCode: 422,
        ),
      );

      await pickApproverAndSubmit(tester);
      // The starting-number hint sits directly above the field's error, so
      // scrolling to it brings both into the viewport.
      const startingNumberHint =
          'هذا أول مستند صادر في القسم — يرجى إدخال رقم البداية';
      await scrollUpTo(tester, find.text(startingNumberHint));

      // The department has no starting point yet, so the field is now
      // mandatory however `/document-counters/next` had prefilled it.
      expect(find.text(backendMessage), findsOneWidget);
      expect(find.text(startingNumberHint), findsOneWidget);
      expect(find.byType(GeneratedDocumentFormScreen), findsOneWidget);
    });

    testWidgets('an unexpected failure never shows raw exception text',
        (tester) async {
      // A Dart exception's toString can carry local paths and Dio dumps.
      await pumpForm(
        tester,
        failure: const FileSystemException(
          'Cannot open file',
          '/data/user/0/com.alraqi.app/cache/secret.pdf',
        ),
      );

      await pickApproverAndSubmit(tester);

      expect(find.textContaining('/data/user/0/'), findsNothing);
      expect(find.textContaining('FileSystemException'), findsNothing);
      expect(
        find.text(arabicMessageFor(ApiErrorCode.unknown)),
        findsOneWidget,
      );
    });
  });

  group('stale approvers', () {
    const selection = [
      User(id: 2, name: 'مدير أول'),
      User(id: 3, name: 'مدير ثانٍ'),
      User(id: 4, name: 'مدير ثالث'),
    ];

    ApiFailure rejecting(Map<String, List<String>> errors) => ApiFailure(
          code: ApiErrorCode.validationFailed,
          message: 'The given data was invalid.',
          statusCode: 422,
          fieldErrors: errors,
        );

    test('a rejected index drops exactly that approver', () {
      final outcome = resolveStaleApprovers(
        rejecting({
          'approver_ids.1': [
            'المعتمد المحدد غير موجود أو ليس مديراً أو رئيساً.'
          ],
        }),
        selection,
      );

      expect(outcome, isNotNull);
      expect(outcome!.remaining.map((u) => u.id), [2, 4]);
      expect(outcome.removed.map((u) => u.id), [3]);
      // The user is told who went and what to do next.
      expect(outcome.message, contains('مدير ثانٍ'));
      expect(outcome.message, contains('التأكيد'));
    });

    test('several rejected indices are all dropped', () {
      final outcome = resolveStaleApprovers(
        rejecting({
          'approver_ids.0': ['غير صالح'],
          'approver_ids.2': ['غير صالح'],
        }),
        selection,
      );

      expect(outcome!.remaining.map((u) => u.id), [3]);
    });

    test('a failure about another field is not treated as an approver problem',
        () {
      final outcome = resolveStaleApprovers(
        rejecting({
          'title': ['مطلوب'],
        }),
        selection,
      );

      expect(outcome, isNull);
    });

    test('a bare approver_ids error keeps the selection intact', () {
      final outcome = resolveStaleApprovers(
        rejecting({
          'approver_ids': ['مطلوب'],
        }),
        selection,
      );

      expect(outcome!.remaining, hasLength(3));
      expect(outcome.removed, isEmpty);
    });
  });

  group('upload limits are per-slot, not one shared ceiling', () {
    test('the main document and an attachment have different limits', () {
      // StoreDocumentRequest: file => max:20480, attachments.* => max:51200.
      expect(AppConstants.maxDocumentBytes, 20 * 1024 * 1024);
      expect(AppConstants.maxAttachmentBytes, 50 * 1024 * 1024);
      expect(AppConstants.maxDocumentBytes,
          lessThan(AppConstants.maxAttachmentBytes));
    });

    test('at most ten attachments', () {
      expect(AppConstants.maxAttachments, 10);
    });

    test('a 30 MB file is rejected as a document but allowed as an attachment',
        () {
      const thirtyMb = 30 * 1024 * 1024;
      expect(thirtyMb > AppConstants.maxDocumentBytes, isTrue);
      expect(thirtyMb > AppConstants.maxAttachmentBytes, isFalse);
    });
  });
}
