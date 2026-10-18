import 'package:doc_approval/shared/widgets/day_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every non-future state has a label and an icon', () {
    for (final s in DayState.values.where((s) => s != DayState.future)) {
      expect(s.label, isNotEmpty, reason: '$s');
      expect(s.icon, isNotNull, reason: '$s');
    }
  });
  test('labels match the design', () {
    expect(DayState.present.label, 'حاضر');
    expect(DayState.leave.label, 'إجازة');
    expect(DayState.incomplete.label, 'انصراف ناقص');
    expect(DayState.rejected.label, 'مرفوض');
    expect(DayState.pendingSync.label, 'بانتظار المزامنة');
    expect(DayState.noRecord.label, 'لا يوجد تسجيل');
  });
}
