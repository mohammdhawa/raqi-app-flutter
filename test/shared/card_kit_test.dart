import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doc_approval/shared/widgets/card_kit.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('CardSlot shows a skeleton while loading', (t) async {
    await pumpTestApp(
      t,
      CardSlot<int>(
        value: const AsyncLoading(),
        builder: (v) => Text('$v'),
        onRetry: () {},
        subject: 'الرصيد',
      ),
    );
    expect(find.byType(SkeletonCard), findsOne);
  });

  testWidgets('CardSlot error offers retry and names the subject', (t) async {
    var retried = 0;
    await pumpTestApp(
      t,
      CardSlot<int>(
        value: const AsyncError('x', StackTrace.empty),
        builder: (v) => Text('$v'),
        onRetry: () => retried++,
        subject: 'رصيد الإجازات',
      ),
    );
    expect(find.text('تعذّر تحميل رصيد الإجازات'), findsOne);
    await t.tap(find.text('إعادة المحاولة'));
    expect(retried, 1);
  });

  testWidgets('CardSlot shows data when loaded', (t) async {
    await pumpTestApp(
      t,
      CardSlot<int>(
        value: const AsyncData(7),
        builder: (v) => Text('$v'),
        onRetry: () {},
        subject: 'الرصيد',
      ),
    );
    expect(find.text('7'), findsOne);
    expect(find.text('تعذّر التحديث'), findsNothing);
  });

  testWidgets('CardSlot keeps stale data visible on refresh failure',
      (t) async {
    // A real provider that succeeds once then fails on refresh is what emits
    // an error that still carries the previous value.
    var calls = 0;
    final provider = FutureProvider<int>((ref) async {
      if (calls++ == 0) return 14;
      throw Exception('x');
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(provider.future);
    await expectLater(container.refresh(provider.future), throwsException);
    final value = container.read(provider);
    expect(value.hasError, isTrue);
    expect(value.hasValue, isTrue);

    var retried = 0;
    await pumpTestApp(
      t,
      CardSlot<int>(
        value: value,
        builder: (v) => Text('$v'),
        onRetry: () => retried++,
        subject: 'الرصيد',
      ),
    );
    expect(find.text('14'), findsOne);
    expect(find.text('تعذّر التحديث'), findsOne);
    await t.tap(find.text('إعادة المحاولة'));
    expect(retried, 1);
  });

  testWidgets('UnavailableCard says it is coming, never a value', (t) async {
    await pumpTestApp(
      t,
      const UnavailableCard(
        title: 'الرواتب',
        body: 'ستظهر هنا رواتبك وكشوفها عند تفعيل الخدمة.',
      ),
    );
    expect(find.text('الرواتب · ستتوفر قريباً'), findsOne);
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('StatTile shows label, value, unit and caption and is tappable',
      (t) async {
    var taps = 0;
    await pumpTestApp(
      t,
      StatTile(
        label: 'رصيد الإجازات',
        value: '14',
        unit: 'يوم',
        caption: 'من 21',
        icon: Icons.beach_access_rounded,
        onTap: () => taps++,
      ),
    );
    expect(find.text('رصيد الإجازات'), findsOne);
    expect(find.text('14'), findsOne);
    expect(find.text('يوم'), findsOne);
    expect(find.text('من 21'), findsOne);
    await t.tap(find.byType(StatTile));
    expect(taps, 1);
  });

  testWidgets('AttentionRow is at least 56 high, shows chevron and taps',
      (t) async {
    var taps = 0;
    await pumpTestApp(
      t,
      AttentionRow(
        icon: Icons.warning_amber_rounded,
        fg: Colors.red,
        bg: Colors.red.shade50,
        title: 'عنوان',
        subtitle: 'تفاصيل',
        onTap: () => taps++,
      ),
    );
    expect(find.byIcon(Icons.chevron_left_rounded), findsOne);
    expect(t.getSize(find.byType(AttentionRow)).height, greaterThanOrEqualTo(56));
    await t.tap(find.text('عنوان'));
    expect(taps, 1);
  });
}
