import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/data/leave_type_cache.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingLeaveRepository extends Fake implements LeaveRepository {
  _CountingLeaveRepository(this.types);

  final List<LeaveType> types;
  int calls = 0;

  @override
  Future<List<LeaveType>> leaveTypes({
    LeaveTypeForm form = LeaveTypeForm.requests,
  }) async {
    calls++;
    return types;
  }
}

const _annual = LeaveType(
  id: 1,
  code: 'annual',
  nameAr: 'إجازة سنوية',
  deductsBalance: true,
);

const _sick = LeaveType(
  id: 2,
  code: 'sick',
  nameAr: 'إجازة مرضية',
  deductsBalance: false,
  requiresReason: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LeaveTypeCache', () {
    // Shared device: the vocabulary one account was served must not be handed
    // to the next person who signs in, from disk, with no request the server
    // could refuse.
    test('one user cannot read another user\'s cached vocabulary', () async {
      const cache = LeaveTypeCache();

      await cache.save(1, LeaveTypeForm.requests, [_annual, _sick]);

      expect(await cache.read(1, LeaveTypeForm.requests), hasLength(2));
      expect(await cache.read(2, LeaveTypeForm.requests), isEmpty);
    });

    test('the two forms are cached apart', () async {
      const cache = LeaveTypeCache();

      await cache.save(1, LeaveTypeForm.requests, [_annual]);

      expect(await cache.read(1, LeaveTypeForm.excuses), isEmpty);
    });

    test('clear drops every user and form', () async {
      const cache = LeaveTypeCache();
      await cache.save(1, LeaveTypeForm.requests, [_annual]);
      await cache.save(2, LeaveTypeForm.excuses, [_sick]);

      await cache.clear();

      expect(await cache.read(1, LeaveTypeForm.requests), isEmpty);
      expect(await cache.read(2, LeaveTypeForm.excuses), isEmpty);
    });

    test('a stored vocabulary survives a round trip intact', () async {
      const cache = LeaveTypeCache();
      await cache.save(3, LeaveTypeForm.requests, [_sick]);

      final restored = await cache.read(3, LeaveTypeForm.requests);

      expect(restored.single.code, 'sick');
      expect(restored.single.deductsBalance, isFalse);
      expect(restored.single.requiresReason, isTrue);
    });
  });

  group('leaveTypesProvider', () {
    final userOverride = StateProvider<User?>((ref) => null);

    ProviderContainer containerFor(_CountingLeaveRepository repo) {
      final container = ProviderContainer(overrides: [
        leaveRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWith((ref) => ref.watch(userOverride)),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('signed out, it is empty and asks the server nothing', () async {
      final repo = _CountingLeaveRepository([_annual]);
      final container = containerFor(repo);

      expect(await container.read(leaveTypesProvider.future), isEmpty);
      expect(repo.calls, 0);
    });

    // The provider is kept alive across screens, so without an explicit
    // dependency on the signed-in user the previous account's types would
    // still be sitting in it after a logout and a new login.
    test('a different user gets their own list, not the previous one',
        () async {
      final repo = _CountingLeaveRepository([_annual]);
      final container = containerFor(repo);

      container.read(userOverride.notifier).state =
          const User(id: 1, name: 'الأول');
      expect(await container.read(leaveTypesProvider.future), hasLength(1));
      expect(repo.calls, 1);

      // Sign out: back to empty, without a request.
      container.read(userOverride.notifier).state = null;
      expect(await container.read(leaveTypesProvider.future), isEmpty);
      expect(repo.calls, 1);

      // A different account signs in on the same device.
      container.read(userOverride.notifier).state =
          const User(id: 2, name: 'الثاني');
      expect(await container.read(leaveTypesProvider.future), hasLength(1));
      expect(repo.calls, 2, reason: 'the new session must fetch for itself');
    });

    test('the fetched list is cached under the user who fetched it', () async {
      final repo = _CountingLeaveRepository([_annual, _sick]);
      final container = containerFor(repo);

      container.read(userOverride.notifier).state =
          const User(id: 5, name: 'موظف');
      await container.read(leaveTypesProvider.future);

      const cache = LeaveTypeCache();
      expect(await cache.read(5, LeaveTypeForm.requests), hasLength(2));
      expect(await cache.read(6, LeaveTypeForm.requests), isEmpty);
    });
  });
}
