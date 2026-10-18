import 'package:doc_approval/shared/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arabic labels use Levantine months and Western digits', () {
    final d = DateTime(2026, 10, 18);
    expect(arabicDayMonth(d), '18 تشرين الأول');
    expect(arabicWeekdayDayMonth(d), 'الأحد 18 تشرين الأول');
    expect(arabicMonthYear(DateTime(2026, 1)), 'كانون الثاني 2026');
  });
  test('clock and duration', () {
    expect(formatClock(DateTime(2026, 10, 18, 8, 2)), '08:02');
    expect(formatDuration(const Duration(hours: 84, minutes: 30)), '84:30');
    expect(formatDuration(const Duration(minutes: 5)), '0:05');
  });
  test('arabicDays agrees with the count', () {
    expect([1, 2, 3, 10, 11].map(arabicDays).toList(),
        ['يوم واحد', 'يومان', '3 أيام', '10 أيام', '11 يوماً']);
  });
  test('isolateLtr wraps in an LTR isolate', () {
    expect(isolateLtr('08:02'), '\u206608:02\u2069');
  });
}
