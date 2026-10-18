// Arabic-facing formatting helpers.
//
// Deliberately hand-rolled instead of `intl`'s `ar` locale: that locale
// yields Egyptian month names and Arabic-Indic digits, while this app uses
// Levantine month names with Western digits.

const _months = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

// Indexed by DateTime.weekday - 1 (Monday first).
const _weekdays = [
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// Wraps [s] in a left-to-right isolate (U+2066 to U+2069) so times, amounts
/// and identifiers keep their order inside right-to-left text.
String isolateLtr(String s) => '\u2066$s\u2069';

/// `18 تشرين الأول`
String arabicDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// `الأحد 18 تشرين الأول`
String arabicWeekdayDayMonth(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${arabicDayMonth(d)}';

/// `تشرين الأول 2026`
String arabicMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// 24-hour local clock, zero-padded: `08:02`.
String formatClock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// Hours (unpadded, may exceed 24) and two-digit minutes: `84:30`.
String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours}:$minutes';
}

/// A day count with correct Arabic number agreement.
String arabicDays(int n) {
  if (n == 1) return 'يوم واحد';
  if (n == 2) return 'يومان';
  if (n >= 3 && n <= 10) return '$n أيام';
  return '$n يوماً';
}
