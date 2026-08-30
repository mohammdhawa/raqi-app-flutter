import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/router/app_router.dart';
import 'package:doc_approval/core/storage/token_storage.dart';
import 'package:doc_approval/features/attendance/presentation/screens/attendance_screen.dart';
import 'package:doc_approval/features/auth/data/auth_repository.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/auth/presentation/widgets/session_staleness_notice.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/documents/presentation/screens/documents_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStorage extends Fake implements TokenStorage {
  _MemoryTokenStorage({required this.token, required this.userJson});

  String? token;
  String? userJson;
  int clearCount = 0;
  int writeCount = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> clear() async {
    clearCount++;
    token = null;
    userJson = null;
  }

  @override
  Future<void> writeSession({
    required String token,
    required String userJson,
  }) async {
    writeCount++;
    this.token = token;
    this.userJson = userJson;
  }
}

class _SessionAdapter implements HttpClientAdapter {
  _SessionAdapter.response(this.statusCode, this.body);

  final int statusCode;
  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NetworkApiClient extends Fake implements ApiClient {
  _NetworkApiClient() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: ApiFailure(
              code: ApiErrorCode.network,
              message: 'offline',
            ),
          ),
        ),
      ),
    );
  }

  final Dio _dio = Dio();

  @override
  Dio get dio => _dio;
}

({AuthRepository repository, ApiClient client}) _repository(
  _MemoryTokenStorage storage,
  _SessionAdapter adapter, {
  void Function()? onUnauthenticated,
}) {
  final client = ApiClient(
    tokenStorage: storage,
    onUnauthenticated: onUnauthenticated ?? () {},
  );
  client.dio.httpClientAdapter = adapter;

  return (
    repository: AuthRepository(client, storage),
    client: client,
  );
}

String _cachedUser({String? role = 'manager'}) => jsonEncode({
      'id': 7,
      'name': 'Cached User',
      'email': 'cached@example.test',
      'role': role,
      'attendance_check': true,
      'can_view_attendance': false,
    });

void main() {
  test('cold restore calls /me and refreshes the cached profile', () async {
    final storage = _MemoryTokenStorage(
      token: 'cached-token',
      userJson: _cachedUser(),
    );
    final adapter = _SessionAdapter.response(
      200,
      jsonEncode({
        'id': 7,
        'name': 'Fresh User',
        'email': 'fresh@example.test',
        'role': 'employee',
        'attendance_check': true,
        'can_view_attendance': false,
      }),
    );
    final repo = _repository(storage, adapter).repository;

    final user = await repo.restoreSession();

    expect(user?.name, 'Fresh User');
    expect(user?.role, 'employee');
    expect(user?.sessionStale, isFalse);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/me');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer cached-token',
    );
    expect(storage.writeCount, 1);
    expect(jsonDecode(storage.userJson!)['name'], 'Fresh User');
  });

  test('a /me 401 clears the cached session and returns null', () async {
    var unauthenticatedSignals = 0;
    final storage = _MemoryTokenStorage(
      token: 'expired-token',
      userJson: _cachedUser(),
    );
    final adapter = _SessionAdapter.response(
      401,
      '{"message":"Unauthenticated.","error":"unauthenticated"}',
    );
    final repo = _repository(
      storage,
      adapter,
      onUnauthenticated: () => unauthenticatedSignals++,
    ).repository;

    final user = await repo.restoreSession();

    expect(user, isNull);
    expect(storage.token, isNull);
    expect(storage.userJson, isNull);
    expect(storage.clearCount, greaterThanOrEqualTo(1));
    expect(unauthenticatedSignals, 1);
  });

  test('a network failure keeps the cached user with a stale flag', () async {
    final storage = _MemoryTokenStorage(
      token: 'offline-token',
      userJson: _cachedUser(role: 'employee'),
    );
    final repo = AuthRepository(_NetworkApiClient(), storage);

    final user =
        await repo.restoreSession().timeout(const Duration(seconds: 2));

    expect(user?.name, 'Cached User');
    expect(user?.sessionStale, isTrue);
    expect(storage.clearCount, 0);
    expect(storage.writeCount, 0);
  });

  test('a /me 503 keeps the cached user and session with a stale flag',
      () async {
    var unauthenticatedSignals = 0;
    final storage = _MemoryTokenStorage(
      token: 'cached-token',
      userJson: _cachedUser(role: 'employee'),
    );
    final adapter = _SessionAdapter.response(
      503,
      '{"message":"Service unavailable."}',
    );
    final repo = _repository(
      storage,
      adapter,
      onUnauthenticated: () => unauthenticatedSignals++,
    ).repository;

    final user = await repo.restoreSession();

    expect(user?.name, 'Cached User');
    expect(user?.role, 'employee');
    expect(user?.sessionStale, isTrue);
    expect(storage.token, 'cached-token');
    expect(storage.userJson, isNotNull);
    expect(storage.clearCount, 0);
    expect(storage.writeCount, 0);
    expect(unauthenticatedSignals, 0);
  });

  testWidgets('a stale cached user renders the offline indicator',
      (tester) async {
    const user = User(
      id: 7,
      name: 'Cached User',
      role: 'employee',
      sessionStale: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(user)],
        child: const MaterialApp(
          home: Scaffold(body: SessionStalenessNotice()),
        ),
      ),
    );

    expect(find.byKey(const Key('session-staleness-indicator')), findsOne);
    expect(find.text(SessionStalenessNotice.message), findsOne);
  });

  testWidgets('role-less models expose no manager affordances', (tester) async {
    final user = User.fromJson({'id': 7, 'name': 'Roleless User'});
    final step = WorkflowStep.fromJson({
      'id': 1,
      'user_id': 7,
      'order': 1,
      'status': 'pending',
    });

    expect(user.role, isNull);
    expect(user.isAdmin, isFalse);
    expect(user.isManager, isFalse);
    expect(user.isChief, isFalse);
    expect(user.isEmployee, isFalse);
    expect(user.canUseDocumentWorkflow, isFalse);
    expect(User.empty().isManager, isFalse);
    expect(step.role, isNull);
    expect(step.isManager, isFalse);
    expect(step.isChief, isFalse);
    expect(homeScreenForUser(user), isA<AttendanceScreen>());
    expect(homeScreenForUser(user), isNot(isA<DocumentsHomeScreen>()));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceManagerActions(
            user: user,
            onRequest: () {},
            onApprovals: () {},
          ),
        ),
      ),
    );

    expect(find.byType(AttendanceManagerActions), findsOne);
    expect(find.text('طلب إجازة'), findsNothing);
    expect(find.text('طلبات للموافقة'), findsNothing);

    // Positive control: these are the real buttons used by AttendanceScreen,
    // not arbitrary strings that could never appear in this widget.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceManagerActions(
            user: const User(id: 8, name: 'Manager', role: 'manager'),
            onRequest: () {},
            onApprovals: () {},
          ),
        ),
      ),
    );

    expect(find.text('طلب إجازة'), findsOne);
    expect(find.text('طلبات للموافقة'), findsOne);
  });
}
