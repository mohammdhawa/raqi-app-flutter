import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the two listings the way the backend does: `status` narrows the
/// result, and the rows come back one page at a time.
class _FilteringLeaveRepository extends Fake implements LeaveRepository {
  _FilteringLeaveRepository({
    this.mine = const [],
    this.queue = const [],
    this.approvalsFailure,
    this.pageSize = 2,
  });

  final List<LeaveRequest> mine;
  final List<LeaveRequest> queue;

  /// Thrown by both approvals entry points when set.
  final ApiFailure? approvalsFailure;

  /// Small on purpose, so a handful of rows spans several pages.
  final int pageSize;

  /// Every `status` value the listings were asked for.
  final List<LeaveStatusFilter> requestedFilters = [];

  /// Page numbers fetched from each listing, in order. Kept apart because the
  /// lookup walks the caller's own requests first and only then the approvals
  /// queue — one combined log could not tell the two walks apart.
  final List<int> minePages = [];
  final List<int> queuePages = [];

  List<LeaveRequest> _apply(
    List<LeaveRequest> rows,
    LeaveStatusFilter status,
  ) {
    requestedFilters.add(status);
    if (status == LeaveStatusFilter.all) return rows;
    return [for (final r in rows) if (r.status.apiValue == status.apiValue) r];
  }

  LeaveRequestsPage _page(
    List<LeaveRequest> rows,
    LeaveStatusFilter status,
    int page,
    List<int> log,
  ) {
    log.add(page);
    final filtered = _apply(rows, status);
    final start = (page - 1) * pageSize;
    if (start >= filtered.length) {
      return (requests: const <LeaveRequest>[], hasMore: false);
    }
    final end =
        start + pageSize > filtered.length ? filtered.length : start + pageSize;
    return (
      requests: filtered.sublist(start, end),
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      _apply(mine, status);

  @override
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async =>
      _page(mine, status, page, minePages);

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async {
    final failure = approvalsFailure;
    if (failure != null) throw failure;
    return _apply(queue, status);
  }

  @override
  Future<LeaveRequestsPage> approvalsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
    int page = 1,
  }) async {
    final failure = approvalsFailure;
    if (failure != null) throw failure;
    return _page(queue, status, page, queuePages);
  }
}

ApiFailure _forbidden() => ApiFailure(
      code: ApiErrorCode.forbidden,
      message: 'لا تملك صلاحية تنفيذ هذا الإجراء.',
      statusCode: 403,
    );

LeaveRequest _request({
  required int id,
  LeaveStatus status = LeaveStatus.approved,
  bool isExcuse = false,
}) =>
    LeaveRequest(
      id: id,
      startDate: DateTime(2026, 8, 20),
      endDate: DateTime(2026, 8, 21),
      status: status,
      isExcuse: isExcuse,
      days: 2,
    );

ProviderContainer _containerFor(LeaveRepository repo) {
  final container = ProviderContainer(overrides: [
    leaveRepositoryProvider.overrideWithValue(repo),
    currentUserProvider.overrideWith((ref) => const User(id: 7, name: 'موظف')),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('leaveRequestDetailProvider', () {
    // The lists carry a status filter the USER chose. A notification about an
    // approved request must open it even when the list is showing pending
    // only — otherwise the app reports a request that plainly exists as
    // missing, on the one screen the notification exists to reach.
    test('resolves a request the visible list has filtered out', () async {
      final repo = _FilteringLeaveRepository(
        mine: [_request(id: 42, status: LeaveStatus.approved)],
      );
      final container = _containerFor(repo);

      // The user is looking at "pending only".
      await container
          .read(myLeaveRequestsProvider.notifier)
          .setStatusFilter(LeaveStatusFilter.pending);
      expect(container.read(myLeaveRequestsProvider).requests, isEmpty);

      final found =
          await container.read(leaveRequestDetailProvider(42).future);

      expect(found, isNotNull);
      expect(found!.id, 42);
      expect(
        repo.requestedFilters,
        contains(LeaveStatusFilter.all),
        reason: 'the fallback lookup must be unfiltered',
      );
    });

    test('resolves an HR-filed excuse the same way', () async {
      final repo = _FilteringLeaveRepository(
        mine: [
          _request(id: 77, status: LeaveStatus.approved, isExcuse: true),
        ],
      );
      final container = _containerFor(repo);

      await container
          .read(myLeaveRequestsProvider.notifier)
          .setStatusFilter(LeaveStatusFilter.rejected);

      final found =
          await container.read(leaveRequestDetailProvider(77).future);

      expect(found?.isExcuse, isTrue);
    });

    test('falls back to the approvals queue for a request under review',
        () async {
      final repo = _FilteringLeaveRepository(
        queue: [_request(id: 9, status: LeaveStatus.pending)],
      );
      final container = _containerFor(repo);

      final found = await container.read(leaveRequestDetailProvider(9).future);

      expect(found?.id, 9);
    });

    // A plain employee gets 403 from the approvals endpoint. That means "not
    // yours to review", not "lookup failed" — it must not turn a resolvable
    // request into an error, nor an unresolvable one into a crash.
    test('a 403 from the approvals queue is not an error', () async {
      final repo = _FilteringLeaveRepository(
        mine: [_request(id: 5)],
        approvalsFailure: _forbidden(),
      );
      final container = _containerFor(repo);

      expect((await container.read(leaveRequestDetailProvider(5).future))?.id, 5);
      expect(await container.read(leaveRequestDetailProvider(6).future), isNull);
    });

    // Everything OTHER than a 403 is a failed lookup, and must say so. Folding
    // a timeout into "not found" tells the employee their request does not
    // exist and offers them nothing to retry.
    test('a non-403 approvals failure surfaces instead of reading as missing',
        () async {
      final repo = _FilteringLeaveRepository(
        approvalsFailure: ApiFailure(
          code: ApiErrorCode.network,
          message: 'تعذر الاتصال بالشبكة. تحقق من الإنترنت.',
        ),
      );
      final container = _containerFor(repo);

      await expectLater(
        container.read(leaveRequestDetailProvider(3).future),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('a server error on the caller\'s own listing surfaces too', () async {
      final repo = _ThrowingOwnListingRepository();
      final container = _containerFor(repo);

      await expectLater(
        container.read(leaveRequestDetailProvider(3).future),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('a genuinely unknown id resolves to null, not an error', () async {
      final container = _containerFor(_FilteringLeaveRepository());

      expect(
        await container.read(leaveRequestDetailProvider(999).future),
        isNull,
      );
    });
  });

  group('leaveRequestDetailProvider paging', () {
    // The lists are ordered created_at desc, so an OLD request that is
    // approved (or excused) today sends a fresh notification while sitting
    // far down the listing. Stopping at the first page reports it missing.
    test('walks past the first page to find an older request', () async {
      final repo = _FilteringLeaveRepository(
        pageSize: 2,
        mine: [
          for (var id = 1; id <= 7; id++) _request(id: id),
        ],
      );
      final container = _containerFor(repo);

      // Id 7 is last, i.e. on the fourth page of two.
      final found = await container.read(leaveRequestDetailProvider(7).future);

      expect(found?.id, 7);
      expect(repo.minePages, [1, 2, 3, 4]);
    });

    test('stops as soon as the row is found', () async {
      final repo = _FilteringLeaveRepository(
        pageSize: 2,
        mine: [for (var id = 1; id <= 7; id++) _request(id: id)],
      );
      final container = _containerFor(repo);

      await container.read(leaveRequestDetailProvider(2).future);

      expect(repo.minePages, [1]);
    });

    test('stops at the last page rather than paging forever', () async {
      final repo = _FilteringLeaveRepository(
        pageSize: 2,
        mine: [for (var id = 1; id <= 3; id++) _request(id: id)],
      );
      final container = _containerFor(repo);

      expect(await container.read(leaveRequestDetailProvider(99).future),
          isNull);
      // Two pages of rows, then the paginator says there is no third.
      expect(repo.minePages, [1, 2]);
      expect(repo.queuePages, [1], reason: 'then it tries the approvals queue');
    });

    // A backend whose `last_page` never settles must not spin the app
    // forever on one notification tap.
    test('a paginator that always claims more is bounded', () async {
      final repo = _EndlessLeaveRepository();
      final container = _containerFor(repo);

      expect(
        await container.read(leaveRequestDetailProvider(1).future),
        isNull,
      );
      expect(repo.calls, lessThanOrEqualTo(10));
      expect(repo.calls, greaterThan(1));
    });
  });
}

/// Fails the caller's own listing — the path with no 403 exemption at all.
class _ThrowingOwnListingRepository extends Fake implements LeaveRepository {
  @override
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async =>
      throw ApiFailure(
        code: ApiErrorCode.serverError,
        message: 'خطأ في الخادم. حاول مرة أخرى.',
        statusCode: 500,
      );

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      const [];

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      const [];
}

/// Never runs out of pages and never holds the row.
class _EndlessLeaveRepository extends Fake implements LeaveRepository {
  int calls = 0;

  @override
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async {
    calls++;
    return (requests: [_request(id: 900 + page)], hasMore: true);
  }

  @override
  Future<LeaveRequestsPage> approvalsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
    int page = 1,
  }) async =>
      (requests: const <LeaveRequest>[], hasMore: false);

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      const [];

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      const [];
}
