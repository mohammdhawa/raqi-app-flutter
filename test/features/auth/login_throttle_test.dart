import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/core/providers/app_info_provider.dart';
import 'package:doc_approval/core/services/push_notification_service.dart';
import 'package:doc_approval/features/auth/data/auth_repository.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePushService extends Fake implements PushNotificationService {
  @override
  Future<void> beginSession() async {}

  @override
  Future<void> endSession() async {}

  @override
  void invalidateSession() {}
}

class _ThrowingAuthRepository extends Fake implements AuthRepository {
  _ThrowingAuthRepository(this.failure);

  final ApiFailure failure;
  int loginCalls = 0;

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    throw failure;
  }

  @override
  Future<User?> restoreSession() async => null;
}

void main() {
  const lockoutMessage =
      'تم تجاوز عدد محاولات تسجيل الدخول المسموح بها. يرجى المحاولة مرة أخرى '
      'بعد دقيقة واحدة.';

  Future<_ThrowingAuthRepository> pumpLogin(
    WidgetTester tester,
    ApiFailure failure,
  ) async {
    final repo = _ThrowingAuthRepository(failure);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          pushNotificationServiceProvider.overrideWithValue(_FakePushService()),
          appVersionProvider.overrideWithValue('1.0.8'),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'someone@al-raqi.sa',
    );
    await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pump();
    await tester.pump();
  }

  ApiFailure throttled({int? retryAfter = 60}) => ApiFailure(
        code: ApiErrorCode.tooManyAttempts,
        message: lockoutMessage,
        statusCode: 429,
        retryAfter: retryAfter,
      );

  testWidgets('the backend 429 message is displayed as sent', (tester) async {
    // The message is a complete Arabic sentence naming the wait — the client
    // shows it verbatim rather than composing one from retry_after.
    await pumpLogin(tester, throttled());
    await submit(tester);

    expect(find.text(lockoutMessage), findsOneWidget);
  });

  testWidgets('retry_after disables the button and counts down',
      (tester) async {
    final repo = await pumpLogin(tester, throttled(retryAfter: 3));
    await submit(tester);
    expect(repo.loginCalls, 1);

    // Locked out: the button is disabled and shows the remaining time.
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('login-lockout-countdown')), findsOneWidget);
    expect(find.textContaining('3 ثانية'), findsOneWidget);

    // The countdown ticks down rather than sitting on the initial value.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('2 ثانية'), findsOneWidget);

    // Tapping while locked out must not spend another attempt.
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(repo.loginCalls, 1);

    // Once it lifts, the button comes back.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('login-lockout-countdown')), findsNothing);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    final unlocked = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(unlocked.onPressed, isNotNull);
  });

  testWidgets('a long lockout is rendered as minutes:seconds', (tester) async {
    await pumpLogin(tester, throttled(retryAfter: 125));
    await submit(tester);

    expect(find.textContaining('2:05'), findsOneWidget);
  });

  testWidgets(
      'a 429 without retry_after still shows the message and stays usable',
      (tester) async {
    // The general api limiter can answer without a parsable wait; refusing to
    // ever re-enable the button would strand the user.
    await pumpLogin(tester, throttled(retryAfter: null));
    await submit(tester);

    expect(find.text(lockoutMessage), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('an unknown email and a wrong password are indistinguishable',
      (tester) async {
    // The backend answers both with the same body on purpose, so the screen
    // must not add a distinction of its own.
    ApiFailure credentialFailure() => ApiFailure(
          code: ApiErrorCode.validationFailed,
          message: 'The given data was invalid.',
          statusCode: 422,
          fieldErrors: {
            'email': ['بيانات الدخول غير صحيحة.'],
          },
        );

    await pumpLogin(tester, credentialFailure());
    await submit(tester);
    expect(find.text('بيانات الدخول غير صحيحة.'), findsOneWidget);

    // Same failure for the other case ⇒ same rendering, and no lockout UI.
    await pumpLogin(tester, credentialFailure());
    await submit(tester);
    expect(find.text('بيانات الدخول غير صحيحة.'), findsOneWidget);
    expect(find.byKey(const Key('login-lockout-countdown')), findsNothing);
  });
}
