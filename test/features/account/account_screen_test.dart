import 'package:doc_approval/core/providers/app_info_provider.dart';
import 'package:doc_approval/features/account/presentation/account_screen.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/salary/presentation/salary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// Records logout calls; never touches the network or secure storage.
class _FakeAuth extends StateNotifier<AuthState> implements AuthController {
  _FakeAuth() : super(const AuthInitial());

  int logoutCalls = 0;

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<void> login(String email, String password) async {}
}

void main() {
  // Tall enough that the lazy ListView builds every row.
  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('account shows only fields the API provides', (t) async {
    tall(t);
    await pumpTestApp(t, const AccountScreen(), overrides: [
      currentUserProvider.overrideWithValue(const User(
          id: 7, name: 'سامر الحلبي', departmentName: 'الإدارة الهندسية')),
      appVersionProvider.overrideWithValue('2.0.0'),
    ]);
    expect(find.text('سامر الحلبي'), findsOne);
    expect(find.text('الإدارة الهندسية'), findsOne);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('الملف الوظيفي · ستتوفر قريباً'), findsOne);
  });

  testWidgets('account joins department and section and shows email',
      (t) async {
    tall(t);
    await pumpTestApp(t, const AccountScreen(), overrides: [
      currentUserProvider.overrideWithValue(const User(
          id: 7,
          name: 'سامر الحلبي',
          email: 's@x.com',
          departmentName: 'الهندسة',
          sectionName: 'المدني')),
      appVersionProvider.overrideWithValue('2.0.0'),
    ]);
    expect(find.text('الهندسة · المدني'), findsOne);
    expect(find.text('s@x.com'), findsOne);
  });

  testWidgets('account rows navigate', (t) async {
    tall(t);
    await pumpTestApp(t, const AccountScreen(), overrides: [
      currentUserProvider
          .overrideWithValue(const User(id: 7, name: 'سامر الحلبي')),
      appVersionProvider.overrideWithValue('2.0.0'),
    ]);
    await t.tap(find.text('الإشعارات'));
    await t.pumpAndSettle();
    expect(find.text('route:/notifications'), findsOne);
  });

  testWidgets('about row navigates', (t) async {
    tall(t);
    await pumpTestApp(t, const AccountScreen(), overrides: [
      currentUserProvider
          .overrideWithValue(const User(id: 7, name: 'سامر الحلبي')),
      appVersionProvider.overrideWithValue('2.0.0'),
    ]);
    await t.tap(find.text('عن التطبيق'));
    await t.pumpAndSettle();
    expect(find.text('route:/about'), findsOne);
  });

  testWidgets('logout asks for confirmation first', (t) async {
    tall(t);
    final fake = _FakeAuth();
    await pumpTestApp(t, const AccountScreen(), overrides: [
      currentUserProvider
          .overrideWithValue(const User(id: 7, name: 'سامر الحلبي')),
      appVersionProvider.overrideWithValue('2.0.0'),
      authControllerProvider.overrideWith((ref) => fake),
    ]);
    await t.tap(find.text('تسجيل الخروج'));
    await t.pumpAndSettle();
    expect(find.text('هل أنت متأكد من تسجيل الخروج؟'), findsOne);
    expect(fake.logoutCalls, 0);

    await t.tap(find.text('إلغاء'));
    await t.pumpAndSettle();
    expect(fake.logoutCalls, 0);

    await t.tap(find.text('تسجيل الخروج'));
    await t.pumpAndSettle();
    await t.tap(find.text('خروج'));
    await t.pumpAndSettle();
    expect(fake.logoutCalls, 1);
  });

  testWidgets('salary is an honest placeholder', (t) async {
    tall(t);
    await pumpTestApp(t, const SalaryScreen());
    expect(find.text('راتبي'), findsOne);
    expect(find.text('الرواتب · ستتوفر قريباً'), findsOne);
  });
}
