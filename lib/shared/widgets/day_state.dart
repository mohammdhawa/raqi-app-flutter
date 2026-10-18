import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// How a calendar day is classified for the employee. Every state except
/// [future] carries a label and an icon, so colour is never the only signal.
enum DayState {
  present,
  late,
  leave,
  absent,
  holiday,
  incomplete,
  rejected,
  pendingSync,
  noRecord,
  future,
}

extension DayStateVisuals on DayState {
  String get label => switch (this) {
        DayState.present => 'حاضر',
        DayState.late => 'متأخر',
        DayState.leave => 'إجازة',
        DayState.absent => 'غياب',
        DayState.holiday => 'عطلة',
        DayState.incomplete => 'انصراف ناقص',
        DayState.rejected => 'مرفوض',
        DayState.pendingSync => 'بانتظار المزامنة',
        DayState.noRecord => 'لا يوجد تسجيل',
        DayState.future => '',
      };

  IconData? get icon => switch (this) {
        DayState.present => Icons.check_rounded,
        DayState.late => Icons.schedule_rounded,
        DayState.leave => Icons.work_outline_rounded,
        DayState.absent => Icons.close_rounded,
        DayState.holiday => Icons.star_outline_rounded,
        DayState.incomplete => Icons.timelapse_rounded,
        DayState.rejected => Icons.block_rounded,
        DayState.pendingSync => Icons.cloud_off_rounded,
        DayState.noRecord => Icons.remove_rounded,
        DayState.future => null,
      };

  /// Foreground (text and icon) colour.
  Color get fg => switch (this) {
        DayState.present => AppColors.dayPresentText,
        DayState.late || DayState.incomplete => AppColors.dayLateText,
        DayState.leave => AppColors.dayLeaveText,
        DayState.absent || DayState.rejected => AppColors.dayAbsentText,
        DayState.holiday => AppColors.dayHolidayText,
        DayState.pendingSync => AppColors.pendingText,
        DayState.noRecord => AppColors.text2,
        DayState.future => AppColors.text3,
      };

  Color get bg => switch (this) {
        DayState.present => AppColors.dayPresentBg,
        DayState.late || DayState.incomplete => AppColors.dayLateBg,
        DayState.leave => AppColors.dayLeaveBg,
        DayState.absent || DayState.rejected => AppColors.dayAbsentBg,
        DayState.holiday => AppColors.dayHolidayBg,
        DayState.pendingSync => AppColors.pendingBg,
        DayState.noRecord => AppColors.surface2,
        DayState.future => Colors.transparent,
      };
}
