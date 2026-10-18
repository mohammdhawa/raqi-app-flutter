# Employee App — Phase 1: Shell, Components and Today's-API Screens — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the role-split document/attendance app into the five-tab employee app from the approved design, using only data the current (legacy Raqi-App) API already serves, with honest «ستتوفر قريباً» cards wherever a module has no API yet.

**Architecture:** A go_router `StatefulShellRoute.indexedStack` hosts five tabs (الرئيسية · دوامي · الطلبات · راتبي · حسابي). Existing route paths are kept so push-notification deep links keep working; detail screens are pushed on the root navigator over the tab bar. New screens are built from a small shared component kit and pure, unit-tested derivation functions (`buildHeroModel`, `deriveMonthDays`, `requestFromLeave`/`requestFromDocument`, `buildAttentionItems`). Attendance capture, queue, sync and recovery logic is reused unchanged.

**Tech Stack:** Flutter 3.44, Dart ≥3.3, flutter_riverpod 2 (StateNotifier / Provider / FutureProvider), go_router 14, google_fonts (Cairo), flutter_test. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-18-employee-app-ux-design.md` · Prototype: https://claude.ai/artifact/5sJizfy6oetN3oExvedEAy

### Scope

In this plan: spec §3.1–§3.3 and §3.5 as far as today's API reaches, §4.2, §4.4 (leave + documents), §5, §6, §8 rows for theme/router/attendance/leave/documents/notifications.

Deliberately **not** in this plan — each becomes its own plan once its ERP contract exists:

| Follow-up plan | Blocked on |
|---|---|
| ERP sign-in: `login` field, forced password change, permission primer (§4.1) | the app pointing at the ERP auth endpoints |
| راتبي content: payslips, breakdown, تصنيفي (§3.4) | `GET /api/me/payslips` (Stage 4) |
| حسابي ← الملف الوظيفي, مستنداتي, «اطّلعت» acknowledgement (§3.5, §4.5) | `GET /api/me/profile`, `/api/me/documents` (Stage 2) |
| Team screen + HR priorities (§3.6) | scoped team-attendance endpoint |
| Late / holiday / absent day states (§3.2) | server-computed day states or shift + holiday calendar |
| Administrative request types (§3.3) | Stage 2 approvals engine |

## Global Constraints

- Brand tokens in `AppColors` keep their current names and values; this plan only **adds** tokens.
- Gold (`AppColors.accent`) is used for at most one primary action per screen.
- Times, amounts, counts beside text and employee identifiers use Western digits and go through `isolateLtr()` when embedded in Arabic text.
- Every status shown to the user has a text label and an icon; colour is never the only signal.
- Never invent a value: a module without an API renders `UnavailableCard`; a null field is omitted; unknown pay is never shown as `0`; a null manager is never guessed.
- Never hardcode a weekend or holiday. `attendance_window.dart` stays as it is.
- Do not change capture/queue/sync/recovery behaviour: `AttendanceController.checkInOrOut`, `AttendanceQueueController`, `AttendanceSyncService`, `attendance_capture_recovery.dart`.
- A role-less or unknown-role user gets no approver or document affordances (`User.canUseDocumentWorkflow` stays the gate).
- Tap targets ≥ 48 logical px; primary buttons 52 px high; cards radius 16, sheets radius 24.
- Arabic copy is exactly as written in the tasks below.
- Every commit leaves `flutter analyze` with no new issues and `flutter test` green.

## Review Focus

1. **Midnight with the app open** — the hero and the calendar must move to the new day (driven by `currentLocalDayProvider`), not keep yesterday's "checked in". Tests: Task 4 `rolls over at midnight`, Task 5 `today boundary`.
2. **Offline capture** — a queued record must render as «بانتظار المزامنة» in the hero and the calendar, never as present/confirmed. Tests: Task 4 `pending check-in is not confirmed`, Task 5 `pending local record wins over noRecord`.
3. **Refused or auto-closed records** — HR-rejected and `missing_checkout` records must not count as worked days or hours. Test: Task 5 `rejected and missing-checkout records do not count`.
4. **Role-less user** — no «بانتظار قراري» segment, no «مستند من قالب» option, no pending-decisions card, document routes still redirect home. Tests: Tasks 7, 8, 9, 11.
5. **Push deep links under the shell** — `/attendance/leave/requests/5`, `/attendance/history?date=…`, `/documents/9`, `/notifications/broadcast/x` must still resolve. Test: Task 11 `legacy deep links resolve`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/core/theme/app_colors.dart` (modify) | add day-state colour tokens |
| `lib/core/theme/app_theme.dart` (modify) | light app bar, bottom-sheet + navigation-bar themes |
| `lib/shared/utils/format.dart` (new) | `isolateLtr`, Arabic day/month labels, `formatClock`, `formatDuration`, `arabicDays` |
| `lib/shared/widgets/day_state.dart` (new) | `DayState` enum + label/icon/colours |
| `lib/shared/widgets/status_pill.dart` (new) | `StatusPill` |
| `lib/shared/widgets/card_kit.dart` (new) | `CardSlot`, `SkeletonCard`, `UnavailableCard`, `StatTile`, `AttentionRow` |
| `lib/features/attendance/domain/attendance_action.dart` (new) | `resolveAttendanceAction` (moved out of `AttendanceScreen.build`) |
| `lib/features/attendance/domain/attendance_twins.dart` (new) | public `hasRemoteTwin` (moved from controller) |
| `lib/features/attendance/domain/month_days.dart` (new) | `DayEntry`, `MonthSummary`, `deriveMonthDays`, `summarizeMonth` |
| `lib/features/attendance/presentation/providers/month_attendance_providers.dart` (new) | `fetchAllMyRecords`, `monthRecordsProvider`, `monthDaysProvider` |
| `lib/features/attendance/presentation/widgets/hero_today_card.dart` (new) | `HeroTodayModel`, `buildHeroModel`, `HeroTodayCard` |
| `lib/features/attendance/presentation/widgets/pending_sync_banner.dart` (new) | `PendingSyncBanner` (moved from `_PendingBanner`) |
| `lib/features/attendance/presentation/widgets/month_calendar.dart` (new) | `MonthCalendar`, `showDaySheet` |
| `lib/features/attendance/presentation/screens/attendance_tab_screen.dart` (new) | دوامي tab |
| `lib/features/requests/domain/request_item.dart` (new) | `RequestItem`, mappers, `mergeRequests` |
| `lib/features/requests/presentation/providers/requests_providers.dart` (new) | feeds + counts |
| `lib/features/requests/presentation/screens/requests_screen.dart` (new) | الطلبات tab + new-request sheet |
| `lib/features/home/domain/attention_items.dart` (new) | `AttentionItem`, `buildAttentionItems` |
| `lib/features/home/presentation/home_screen.dart` (new) | الرئيسية tab |
| `lib/features/salary/presentation/salary_screen.dart` (new) | راتبي placeholder tab |
| `lib/features/account/presentation/account_screen.dart` (new) | حسابي tab |
| `lib/core/router/app_shell.dart` (new) | tab bar shell, staleness notice, capture notice |
| `lib/core/router/app_router.dart` (modify) | shell routes, `resolveRedirect` |
| `lib/main.dart` (modify) | notification routing to tab locations, app title |
| `test/support/test_app.dart` (new) | `pumpTestApp` helper |

Deleted in Task 12: `attendance_screen.dart`, `leave_screen.dart`, `documents_home_screen.dart`, `leave_balance_card.dart` (if unreferenced), `homeScreenForUser`.

---

### Task 1: Tokens, formatting helpers, DayState and StatusPill

**Files:**
- Modify: `lib/core/theme/app_colors.dart`, `lib/core/theme/app_theme.dart`
- Create: `lib/shared/utils/format.dart`, `lib/shared/widgets/day_state.dart`, `lib/shared/widgets/status_pill.dart`, `test/support/test_app.dart`
- Test: `test/shared/format_test.dart`, `test/shared/day_state_test.dart`

**Interfaces:**
- Produces:
  - `String isolateLtr(String s)` — wraps in U+2066 … U+2069.
  - `String arabicDayMonth(DateTime d)` → `'18 تشرين الأول'`; `String arabicWeekdayDayMonth(DateTime d)` → `'الأحد 18 تشرين الأول'`; `String arabicMonthYear(DateTime d)` → `'تشرين الأول 2026'`.
  - `String formatClock(DateTime t)` → `'08:02'` (24 h, local time, zero-padded).
  - `String formatDuration(Duration d)` → `'84:30'` (hours unpadded, minutes 2 digits).
  - `String arabicDays(int n)` → 1 `'يوم واحد'`, 2 `'يومان'`, 3–10 `'$n أيام'`, otherwise `'$n يوماً'`.
  - `enum DayState { present, late, leave, absent, holiday, incomplete, rejected, pendingSync, noRecord, future }` with extension getters `String label`, `IconData? icon`, `Color fg`, `Color bg`.
  - `StatusPill({required String label, IconData? icon, required Color fg, required Color bg})` and `StatusPill.day(DayState state)`.
  - `Future<void> pumpTestApp(WidgetTester tester, Widget home, {List<Override> overrides = const []})` — ProviderScope + `MaterialApp.router` with RTL; `/` renders `home`; any other location renders `Text('route:${state.uri}')`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/shared/format_test.dart
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
  expect(isolateLtr('08:02'), '⁦08:02⁩');
});

// test/shared/day_state_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/shared`
Expected: FAIL — `format.dart` / `day_state.dart` not found.

- [ ] **Step 3: Implement**

`app_colors.dart` — add (values from spec §6.1):

| Token | Value |
|---|---|
| `dayPresent` / `dayPresentBg` / `dayPresentText` | `0xFF2E7D5B` / `0xFFE4F2EC` / `0xFF1E5A3F` |
| `dayLate` / `dayLateBg` / `dayLateText` | `0xFFC2410C` / `0xFFFDEBDD` / `0xFF9A3412` |
| `dayLeave` / `dayLeaveBg` / `dayLeaveText` | `0xFF2F5FA7` / `0xFFE3ECF8` / `0xFF1F477F` |
| `dayAbsentBg` / `dayAbsentText` | `0xFFFBE7E5` / `0xFF8A1B17` |
| `dayHoliday` / `dayHolidayBg` / `dayHolidayText` | `0xFF6B5CA5` / `0xFFECE9F6` / `0xFF4A3F80` |
| `rSheet` | `24` |

`DayState` visuals (fg = the `…Text` token, bg = the `…Bg` token):
present → present palette, `Icons.check_rounded`; late → late palette, `Icons.schedule_rounded`, label `'متأخر'`; leave → leave palette, `Icons.work_outline_rounded`; absent → absent palette, `Icons.close_rounded`, label `'غياب'`; holiday → holiday palette, `Icons.star_outline_rounded`, label `'عطلة'`; incomplete → late palette, `Icons.timelapse_rounded`; rejected → absent palette, `Icons.block_rounded`; pendingSync → `pendingBg`/`pendingText`, `Icons.cloud_off_rounded`; noRecord → `surface2`/`text2`, `Icons.remove_rounded`; future → transparent/`text3`, no icon, label `''`.

Months: كانون الثاني، شباط، آذار، نيسان، أيار، حزيران، تموز، آب، أيلول، تشرين الأول، تشرين الثاني، كانون الأول. Weekdays (Mon…Sun): الإثنين، الثلاثاء، الأربعاء، الخميس، الجمعة، السبت، الأحد. Do not use `intl`'s `ar` locale: it produces Egyptian month names and Arabic-Indic digits.

`app_theme.dart` — the app bar becomes `backgroundColor: AppColors.surface`, `foregroundColor: AppColors.text`, `surfaceTintColor: Colors.transparent`, and the title style colour becomes `AppColors.text`; `scaffoldBackgroundColor: AppColors.surface`. Add `bottomSheetTheme` (white, top radius `rSheet`, `showDragHandle: true`). Add `navigationBarTheme` (white background, `indicatorColor: AppColors.accentSoft`, labels Cairo 12: selected `w700` `primary`, unselected `w500` `text2`, height 68).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/shared`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme lib/shared test/shared test/support
git commit -m "feat(ui): day-state tokens, Arabic formatting helpers and StatusPill"
```

---

### Task 2: Card kit — CardSlot, SkeletonCard, UnavailableCard, StatTile, AttentionRow

**Files:**
- Create: `lib/shared/widgets/card_kit.dart`
- Test: `test/shared/card_kit_test.dart`

**Interfaces:**
- Consumes: `pumpTestApp` (Task 1).
- Produces:
  - `CardSlot<T>({required AsyncValue<T> value, required Widget Function(T data) builder, required VoidCallback onRetry, required String subject, double skeletonHeight = 88})` — loading without data → `SkeletonCard(height)`; error without data → inline row `'تعذّر تحميل $subject'` + `TextButton('إعادة المحاولة')`; data → `builder(data)`; error **with** previous data → `builder(data)` followed by a caption row `'تعذّر التحديث'` + `'إعادة المحاولة'`.
  - `SkeletonCard({double height = 88})` — `Semantics(label: 'جارٍ التحميل')`.
  - `UnavailableCard({required String title, required String body, IconData icon = Icons.hourglass_empty_rounded})` — renders `'$title · ستتوفر قريباً'` and `body`, dashed-look border (`AppColors.borderStrong`), no tap.
  - `StatTile({required String label, required String value, String? unit, String? caption, IconData? icon, Color? iconColor, VoidCallback? onTap})`.
  - `AttentionRow({required IconData icon, required Color fg, required Color bg, required String title, required String subtitle, required VoidCallback onTap})` — min height 56, trailing chevron `Icons.chevron_left_rounded`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('CardSlot shows a skeleton while loading', (t) async {
  await pumpTestApp(t, CardSlot<int>(value: const AsyncLoading(), builder: (v) => Text('$v'), onRetry: () {}, subject: 'الرصيد'));
  expect(find.byType(SkeletonCard), findsOne);
});
testWidgets('CardSlot error offers retry and names the subject', (t) async {
  var retried = 0;
  await pumpTestApp(t, CardSlot<int>(value: AsyncError('x', StackTrace.empty), builder: (v) => Text('$v'), onRetry: () => retried++, subject: 'رصيد الإجازات'));
  expect(find.text('تعذّر تحميل رصيد الإجازات'), findsOne);
  await t.tap(find.text('إعادة المحاولة'));
  expect(retried, 1);
});
testWidgets('CardSlot keeps stale data visible on refresh failure', (t) async {
  await pumpTestApp(t, CardSlot<int>(value: AsyncError<int>('x', StackTrace.empty).copyWithPrevious(const AsyncData(14)), builder: (v) => Text('$v'), onRetry: () {}, subject: 'الرصيد'));
  expect(find.text('14'), findsOne);
  expect(find.text('تعذّر التحديث'), findsOne);
});
testWidgets('UnavailableCard says it is coming, never a value', (t) async {
  await pumpTestApp(t, const UnavailableCard(title: 'الرواتب', body: 'ستظهر هنا رواتبك وكشوفها عند تفعيل الخدمة.'));
  expect(find.text('الرواتب · ستتوفر قريباً'), findsOne);
  expect(find.textContaining('0'), findsNothing);
});
```

`copyWithPrevious` is how Riverpod 2 builds an error-that-still-has-data value; it is what a `FutureProvider` emits when a refresh fails.

- [ ] **Step 2: Run to verify failure** — `flutter test test/shared/card_kit_test.dart` → FAIL (undefined names).

- [ ] **Step 3: Implement the five widgets in `card_kit.dart`** with the signatures above, styled per spec §6 (white card, border `AppColors.border`, radius 16, padding 14).

- [ ] **Step 4: Run to verify pass** — `flutter test test/shared` → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(ui): card kit with independent loading, error, stale and unavailable states"`

---

### Task 3: Extract the check-in/out action rule

**Files:**
- Create: `lib/features/attendance/domain/attendance_action.dart`
- Modify: `lib/features/attendance/presentation/screens/attendance_screen.dart:131-157` (call the new function), `lib/features/attendance/presentation/providers/attendance_controller.dart` (add provider)
- Test: `test/features/attendance/attendance_action_test.dart`

**Interfaces:**
- Produces:
  - `class AttendanceAction { const AttendanceAction({required this.nextType, this.disabledReason}); final AttendanceType nextType; final String? disabledReason; }`
  - `AttendanceAction resolveAttendanceAction({required AttendanceType? status, required bool onApprovedLeave, required String? checkoutBlockedReason, required DateTime now})`
  - `final attendanceActionProvider = Provider.autoDispose<AttendanceAction>` — watches `attendanceStatusProvider`, `approvedLeaveTodayProvider` (`valueOrNull != null`), `checkOutBlockedReasonProvider`, `currentLocalDayProvider`.

The function body is the existing logic in `AttendanceScreen.build` lines 131–157, moved verbatim, including the three Arabic messages. This is a refactor: no behaviour change.

- [ ] **Step 1: Write the failing test**

```dart
final now = DateTime(2026, 10, 18, 9);
test('no record → check-in allowed', () {
  final a = resolveAttendanceAction(status: null, onApprovedLeave: false, checkoutBlockedReason: null, now: now);
  expect(a.nextType, AttendanceType.checkIn);
  expect(a.disabledReason, isNull);
});
test('checked out → second check-in blocked with the existing message', () {
  final a = resolveAttendanceAction(status: AttendanceType.checkOut, onApprovedLeave: false, checkoutBlockedReason: null, now: now);
  expect(a.disabledReason, 'لقد أكملت دوام اليوم — تم تسجيل الحضور والانصراف.');
});
test('approved leave blocks check-in', () {
  final a = resolveAttendanceAction(status: null, onApprovedLeave: true, checkoutBlockedReason: null, now: now);
  expect(a.disabledReason, 'لديك إجازة معتمدة اليوم — لا حاجة لتسجيل الحضور.');
});
test('checked in → checkout carries the gap countdown', () {
  final a = resolveAttendanceAction(status: AttendanceType.checkIn, onApprovedLeave: false, checkoutBlockedReason: 'انتظر', now: now);
  expect(a.nextType, AttendanceType.checkOut);
  expect(a.disabledReason, 'انتظر');
});
```

- [ ] **Step 2: Run** — `flutter test test/features/attendance/attendance_action_test.dart` → FAIL.
- [ ] **Step 3: Implement the function and provider; make `AttendanceScreen` read `attendanceActionProvider`.**
- [ ] **Step 4: Run** — `flutter test` → all PASS (existing attendance tests unchanged).
- [ ] **Step 5: Commit** — `git commit -m "refactor(attendance): extract the check-in/out action rule"`

---

### Task 4: HeroTodayCard

**Files:**
- Create: `lib/features/attendance/presentation/widgets/hero_today_card.dart`
- Test: `test/features/attendance/hero_today_test.dart`

**Interfaces:**
- Consumes: `attendanceActionProvider` (Task 3), `todayAttendanceProvider`, `approvedLeaveTodayProvider`, `leaveTypeByIdProvider`, `currentUserProvider` (`attendanceCheck`), `attendanceControllerProvider` (`isCapturing`, `captureError`, `checkInOrOut`, `clearCaptureError`), `StatusPill`, format helpers.
- Produces:
  - `enum HeroPhase { disabled, notCheckedIn, checkedIn, done, onLeave }`
  - `class HeroTodayModel { final HeroPhase phase; final DateTime? checkedInAt; final Duration worked; final bool isPendingSync; final String? leaveLabel; }`
  - `HeroTodayModel buildHeroModel({required bool attendanceEnabled, required List<TodayAttendanceItem> today, required LeaveRequest? approvedLeaveToday, required String? leaveTypeLabel, required DateTime now})`
  - `HeroTodayCard({bool compact = false, VoidCallback? onOpenDay})`

**Rules for `buildHeroModel`:**
- `!attendanceEnabled` → `disabled`.
- Valid items = `today` minus `isRejected`, minus `isMissingCheckout`, minus `status == AttendanceSyncStatus.failed`; sorted by `recordedAt`.
- No valid items: approved leave → `onLeave` (`leaveLabel = leaveTypeLabel ?? approvedLeaveToday.leaveType ?? 'إجازة'`); otherwise → `notCheckedIn`.
- Latest valid item is a check-in → `checkedIn`, with `checkedInAt` = its time. Latest is a check-out → `done`.
- `worked` = sum of (check-out − preceding check-in) pairs, plus (`now` − open check-in) when `checkedIn`.
- `isPendingSync` = the latest valid item's `status != AttendanceSyncStatus.synced`.

**Copy:**

| Phase | Pill | Big value / label | Action |
|---|---|---|---|
| notCheckedIn | `لم تسجّل بعد` | `ابدأ يومك` / `سجّل حضورك عند الوصول` | gold `تسجيل الحضور` |
| checkedIn | `حاضر · منذ {formatClock}`, or `حضور محفوظ على الجهاز` (pending palette) if pending | `{formatDuration(worked)}` / `ساعات العمل اليوم` | gold `تسجيل الانصراف` |
| done | `اكتمل الدوام`, or `انصراف محفوظ على الجهاز` if pending | worked / `إجمالي ساعات اليوم` | outlined `عرض تفاصيل اليوم` → `onOpenDay` |
| onLeave | `إجازة` | leaveLabel / `لا يلزم تسجيل الحضور اليوم` | none |
| disabled | — | `تسجيل الحضور غير مفعّل لحسابك` | none |

**The widget:**
- A navy card with radius 22 and `assets/logo-symbol-gold.png` as a 12 % opacity watermark at the start-top corner. Header: `arabicWeekdayDayMonth(today)` plus the pill. `compact` hides the big value and puts the action beside the summary line.
- The gold button shows `disabledReason` as a caption beneath it and is disabled when `disabledReason != null`. It shows a spinner while `isCapturing`.
- The tap handler is moved verbatim from `AttendanceScreen._handleTap` (success / `captureError` SnackBars).
- A `Timer.periodic(1 min)` rebuilds the card while `checkedIn`; cancel it in `dispose`.

- [ ] **Step 1: Write the failing tests**

```dart
final now = DateTime(2026, 10, 18, 13, 43);
TodayAttendanceItem inAt(int h, int m, {bool pending = false}) => pending
    ? TodayAttendanceItem.local(PendingAttendanceRecord(type: AttendanceType.checkIn, latitude: 0, longitude: 0, selfiePath: 'x.jpg', recordedAt: DateTime(2026, 10, 18, h, m)))
    : TodayAttendanceItem.remote(AttendanceRecord(id: 1, userId: 7, type: AttendanceType.checkIn, latitude: 0, longitude: 0, recordedAt: DateTime(2026, 10, 18, h, m), createdAt: DateTime(2026, 10, 18, h, m)));

test('no records → notCheckedIn', () {
  expect(buildHeroModel(attendanceEnabled: true, today: const [], approvedLeaveToday: null, leaveTypeLabel: null, now: now).phase, HeroPhase.notCheckedIn);
});
test('open check-in counts worked time to now', () {
  final m = buildHeroModel(attendanceEnabled: true, today: [inAt(8, 2)], approvedLeaveToday: null, leaveTypeLabel: null, now: now);
  expect(m.phase, HeroPhase.checkedIn);
  expect(m.worked, const Duration(hours: 5, minutes: 41));
});
test('pending check-in is not confirmed', () {
  final m = buildHeroModel(attendanceEnabled: true, today: [inAt(8, 2, pending: true)], approvedLeaveToday: null, leaveTypeLabel: null, now: now);
  expect(m.isPendingSync, isTrue);
});
test('rejected and missing-checkout rows are ignored', () { /* one rejected check-in only → notCheckedIn */ });
test('attendanceCheck false → disabled even with records', () { /* → HeroPhase.disabled */ });
test('rolls over at midnight', () {
  // the controller only feeds today's items; with an empty list after midnight the phase is notCheckedIn
  expect(buildHeroModel(attendanceEnabled: true, today: const [], approvedLeaveToday: null, leaveTypeLabel: null, now: DateTime(2026, 10, 19, 0, 1)).phase, HeroPhase.notCheckedIn);
});
testWidgets('disabledReason renders and disables the button', (t) async { /* override attendanceActionProvider → AttendanceAction(nextType: checkOut, disabledReason: 'انتظر') ; expect find.text('انتظر'); the تسجيل الانصراف button onPressed == null */ });
```

`PendingAttendanceRecord` defaults to `status: AttendanceSyncStatus.pending`; pass `status: AttendanceSyncStatus.failed` for a failed fixture.

- [ ] **Step 2: Run** — `flutter test test/features/attendance/hero_today_test.dart` → FAIL.
- [ ] **Step 3: Implement `buildHeroModel` and `HeroTodayCard`.**
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): today hero card with offline-honest states"`

---

### Task 5: Month day states and the month providers

**Files:**
- Create: `lib/features/attendance/domain/attendance_twins.dart`, `lib/features/attendance/domain/month_days.dart`, `lib/features/attendance/presentation/providers/month_attendance_providers.dart`
- Modify: `attendance_controller.dart` — delete private `_hasRemoteTwin`, import the public one (pure move).
- Test: `test/features/attendance/month_days_test.dart`

**Interfaces:**
- Produces:
  - `bool hasRemoteTwin(PendingAttendanceRecord local, Iterable<AttendanceRecord> remote)` — same body as today: same type, < 2 min apart.
  - `class DayEntry { final DateTime day; final DayState state; final List<AttendanceRecord> records; final List<PendingAttendanceRecord> pending; final LeaveRequest? leave; final Duration worked; }`
  - `class MonthSummary { final int presentDays; final Duration worked; final int incompleteDays; final int rejectedDays; final int leaveDays; }`
  - `List<DayEntry> deriveMonthDays({required DateTime month, required DateTime today, required List<AttendanceRecord> records, required List<PendingAttendanceRecord> pending, required List<LeaveRequest> approvedLeaves})` — one entry per calendar day of `month`.
  - `MonthSummary summarizeMonth(List<DayEntry> days)`
  - `Future<List<AttendanceRecord>> fetchAllMyRecords(AttendanceRepository repo, {required DateTime from, required DateTime to, int maxPages = 20})`
  - `class MonthRecords { final List<AttendanceRecord> records; final List<LeaveRequest> approvedLeaves; }`
  - `final monthRecordsProvider = FutureProvider.autoDispose.family<MonthRecords, DateTime>` — the key is `DateTime(year, month)`. It fetches `fetchAllMyRecords(from: first day, to: last day)` and `leaveRepository.myRequests(status: LeaveStatusFilter.approved, year: month.year)`, keeping leaves that overlap the month.
  - `final monthDaysProvider = Provider.autoDispose.family<AsyncValue<List<DayEntry>>, DateTime>` — combines `monthRecordsProvider(month)`, `attendanceQueueProvider` and `currentLocalDayProvider`.

**State precedence per day** (first match wins):
1. `day > today` → `future`.
2. A local record on that day that is not failed and has no remote twin → `pendingSync`.
3. A valid (not rejected) check-in with `isMissingCheckout` → `incomplete`.
4. A valid check-in → `present`.
5. An approved leave whose `coversDate(day)` → `leave`.
6. Only rejected remote records or failed local records → `rejected`.
7. Otherwise → `noRecord`.

`worked` = the sum of `workHours` on valid check-out rows that day. `MonthSummary.presentDays` counts `present` only.

- [ ] **Step 1: Write the failing tests**

```dart
final month = DateTime(2026, 10);
final today = DateTime(2026, 10, 18);
test('one entry per day, future after today', () {
  final days = deriveMonthDays(month: month, today: today, records: const [], pending: const [], approvedLeaves: const []);
  expect(days, hasLength(31));
  expect(days[17].state, DayState.noRecord); // 18th
  expect(days[18].state, DayState.future);   // 19th
});
test('rejected and missing-checkout records do not count', () {
  final days = deriveMonthDays(month: month, today: today, records: [
    checkIn(DateTime(2026, 10, 5, 8), rejected: true),
    checkIn(DateTime(2026, 10, 6, 8), missingCheckout: true),
    checkIn(DateTime(2026, 10, 7, 8)), checkOut(DateTime(2026, 10, 7, 16), workHours: 8.0),
  ], pending: const [], approvedLeaves: const []);
  expect(days[4].state, DayState.rejected);
  expect(days[5].state, DayState.incomplete);
  expect(days[6].state, DayState.present);
  final s = summarizeMonth(days);
  expect(s.presentDays, 1);
  expect(s.worked, const Duration(hours: 8));
});
test('pending local record wins over noRecord', () { /* pending check-in on the 18th → pendingSync */ });
test('a synced local twin does not mask the server row', () { /* local + remote within 2 min → present */ });
test('approved leave shows as leave unless attended', () { /* leave 11–12 → leave; attended 12th → present */ });
test('today boundary', () { /* record dated 2026-10-19 00:05 with today=2026-10-19 → present on 19th, 20th future */ });
test('fetchAllMyRecords follows pagination', () async {
  // fake AttendanceRepository returning page 1 (lastPage 2) then page 2
  final all = await fetchAllMyRecords(fakeRepo, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
  expect(all, hasLength(fakeRepo.totalRecords));
  expect(fakeRepo.requestedPages, [1, 2]);
});
```

`checkIn`/`checkOut` are local test helpers that build `AttendanceRecord`s. The fake repository `extends Fake implements AttendanceRepository` and overrides `myRecords`.

- [ ] **Step 2: Run** — `flutter test test/features/attendance/month_days_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — `flutter test` → all PASS (including the existing `attendance_status_test.dart` after the `hasRemoteTwin` move).
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): derive month day states from records, queue and leave"`

---

### Task 6: دوامي tab screen

**Files:**
- Create: `lib/features/attendance/presentation/widgets/pending_sync_banner.dart` (move `_PendingBanner` from `attendance_screen.dart:598-680` verbatim, renamed `PendingSyncBanner({required int count})`, and make `AttendanceScreen` use it), `lib/features/attendance/presentation/widgets/month_calendar.dart`, `lib/features/attendance/presentation/screens/attendance_tab_screen.dart`
- Test: `test/features/attendance/attendance_tab_test.dart`

**Interfaces:**
- Consumes: `HeroTodayCard`, `monthDaysProvider`, `summarizeMonth`, `pendingAttendanceCountProvider`, `CardSlot`, `StatusPill.day`, format helpers.
- Produces:
  - `MonthCalendar({required DateTime month, required List<DayEntry> days, required ValueChanged<DayEntry> onDayTap})`
  - `Future<void> showDaySheet(BuildContext context, DayEntry entry)`
  - `AttendanceTabScreen()`

**Layout, top to bottom:**
1. Title `دوامي`, plus a month switcher: previous `IconButton`, `arabicMonthYear(month)`, and next, which is disabled on the current month. The selected month is held in local `State`.
2. `HeroTodayCard(compact: true, onOpenDay: …)` — only while the selected month is the current month.
3. `PendingSyncBanner` when the pending count is > 0.
4. `CardSlot` over `monthDaysProvider(month)`, containing:
   - weekday header `سبت أحد إثنين ثلاثاء أربعاء خميس جمعة` (Saturday first; leading blanks = `(firstDay.weekday - DateTime.saturday + 7) % 7`);
   - a 7-column grid of 46 px cells, each a button with semantics label `'${arabicWeekdayDayMonth(day)} — ${state.label}'` showing the day number and the state icon at 12 px; future cells are disabled; today has a 2 px `AppColors.accent` border;
   - a legend of `StatusPill.day` chips with counts, only for states present in the month;
   - a totals card: `أيام الحضور` presentDays, `ساعات العمل` `formatDuration(worked)`, plus `انصراف ناقص` incompleteDays and `مرفوض` rejectedDays when > 0.
5. `TextButton('السجل الكامل')` → `context.push('/attendance/history')`.

Pull-to-refresh runs the existing two refreshes (queue + controller reload) and invalidates `monthRecordsProvider(month)`.

**`showDaySheet`:**
- Title `arabicWeekdayDayMonth(day)` plus `StatusPill.day`.
- One row per remote record: `type.arabicLabel · formatClock` with a pill — `مؤكد`, or `مرفوض` with `rejectionReasonLabel` under it, or `انصراف ناقص`.
- One row per pending local record: `بانتظار المزامنة`; failed rows show `errorMessage`.
- `ساعات العمل` worked when > 0. A leave line shows the leave label and `معتمدة`. `noRecord` shows `لا يوجد تسجيل لهذا اليوم.`
- When the state is rejected or incomplete, a `عرض في السجل` button → `context.push('/attendance/history?date=yyyy-MM-dd')`.

- [ ] **Step 1: Write the failing widget tests** — override `monthDaysProvider` with a fixed list:

```dart
testWidgets('calendar labels every past day with its state', (t) async {
  await pumpTestApp(t, const AttendanceTabScreen(), overrides: [ /* monthDaysProvider(DateTime(2026,10)) → AsyncData(fixture with 7th present, 5th rejected) ; currentLocalDayProvider → DateTime(2026,10,18); pendingAttendanceCountProvider → 0; attendanceActionProvider stub */ ]);
  expect(find.bySemanticsLabel('الأربعاء 7 تشرين الأول — حاضر'), findsOne);
  expect(find.bySemanticsLabel('الإثنين 5 تشرين الأول — مرفوض'), findsOne);
});
testWidgets('tapping a day opens its sheet', (t) async { /* tap 7 → find.text('مؤكد') */ });
testWidgets('next month is disabled on the current month', (t) async { /* IconButton tooltip 'الشهر التالي' onPressed == null */ });
testWidgets('pending banner shows the count', (t) async { /* pendingAttendanceCountProvider → 1 → find.textContaining('سجل واحد بانتظار المزامنة') */ });
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — `flutter test` → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): دوامي tab with month calendar and day sheet"`

---

### Task 7: Unified request items and feeds

**Files:**
- Create: `lib/features/requests/domain/request_item.dart`, `lib/features/requests/presentation/providers/requests_providers.dart`
- Test: `test/features/requests/request_item_test.dart`, `test/features/requests/requests_providers_test.dart`

**Interfaces:**
- Consumes: `LeaveRequest` (`orderedApprovals`, `stepNumberOf`, `isExcuse`, `days`, `canBeReviewedBy`), `Document` (`status`, `nextPendingUsers`, `documentNumber`, `templateName`, `createdAt`), `myLeaveRequestsProvider`, `leaveApprovalsProvider`, `leaveTypeByIdProvider`, `documentsRepositoryProvider`, `currentUserProvider`, `arabicDayMonth`, `arabicDays`.
- Produces:
  - `enum RequestKind { leave, document }`
  - `enum RequestStatus { pending, approved, rejected, cancelled }`, with `label` (`قيد الانتظار` / `مقبول` / `مرفوض` / `ملغى`), `fg`, `bg` (pending/approved/rejected tokens; cancelled → `surface2`/`text2`).
  - `class RequestItem { final RequestKind kind; final int id; final String title; final String subtitle; final RequestStatus status; final String? stepLabel; final DateTime sortDate; final String route; final String? requesterName; }`
  - `RequestItem requestFromLeave(LeaveRequest r, {String? typeLabel})`
  - `RequestItem requestFromDocument(Document d)`
  - `bool isAwaitingUser(Document d, int userId)`
  - `List<RequestItem> mergeRequests(List<RequestItem> leaves, List<RequestItem> documents, {required bool documentsHaveMore})`
  - `final canReviewRequestsProvider = Provider<bool>` (= `currentUser?.canUseDocumentWorkflow ?? false`)
  - `final sentDocumentsProvider = FutureProvider.autoDispose<DocumentsPage>` (page 1 of `DocumentListType.sent`; returns an empty page when `!canReviewRequests`)
  - `final documentsAwaitingMeProvider = FutureProvider.autoDispose<List<Document>>` (inbox, `DocumentStatusFilter.pending`, pages 1..5, filtered by `isAwaitingUser`; empty when `!canReviewRequests`)
  - `final myRequestsFeedProvider = Provider.autoDispose<AsyncValue<List<RequestItem>>>`
  - `final inboxFeedProvider = Provider.autoDispose<AsyncValue<List<RequestItem>>>` (leave approvals where `canBeReviewedBy(me)`, plus documents awaiting me; empty `AsyncData` when `!canReviewRequests`)
  - `final pendingDecisionsCountProvider = Provider.autoDispose<int>`

**Mapping rules:**
- Leave **title** = `typeLabel ?? r.leaveType ?? 'طلب إجازة'`. **Subtitle** = `'${arabicDayMonth(start)} – ${arabicDayMonth(end)} · ${arabicDays(r.days)}'`; a single-day request drops the range.
- Leave **stepLabel**:
  - excuse → `سجّلتها الموارد البشرية`;
  - pending with a chain → `'الخطوة $k من $n · بانتظار $name'`;
  - pending without a chain but with `managerName` → `'بانتظار $managerName'`;
  - approved → `اكتمل المسار`;
  - otherwise null.
- **Status:** `LeaveStatus` maps 1:1 to `RequestStatus`. **sortDate** = `createdAt ?? startDate`. **route** = `/attendance/leave/requests/$id`. **requesterName** = `r.requesterName`.
- Document **title** = `d.title`. **Subtitle** = `'${d.documentNumber ?? d.templateName ?? 'مستند'} · ${arabicDayMonth(d.createdAt)}'`. **stepLabel** when pending and `nextPendingUsers` is non-empty = `'بانتظار ${names joined by '، '}'`. **requesterName** = `d.creator.name`. **route** = `/documents/$id`.
- **Merge:** sort descending by `sortDate`. When `documentsHaveMore` and documents are non-empty, drop leave items older than the oldest loaded document, so the list never claims an order it hasn't loaded.
- **Feed `AsyncValue`:** loading while any source is loading with no data; error when a source failed and nothing is loaded; otherwise data from whatever loaded.

- [ ] **Step 1: Write the failing tests**

```dart
test('leave pending step names the current approver', () {
  final r = leaveFixture(status: 'pending', approvals: [step(1, 'رامي العلي', 'approved'), step(2, 'هالة منصور', 'pending')]);
  final i = requestFromLeave(r, typeLabel: 'إجازة مرضية');
  expect(i.title, 'إجازة مرضية');
  expect(i.stepLabel, 'الخطوة 2 من 2 · بانتظار هالة منصور');
  expect(i.status, RequestStatus.pending);
  expect(i.route, '/attendance/leave/requests/${r.id}');
});
test('cancelled leave is not pending', () {
  expect(requestFromLeave(leaveFixture(status: 'cancelled')).status, RequestStatus.cancelled);
});
test('document awaiting me only when I am a next pending user', () {
  expect(isAwaitingUser(docFixture(status: 'pending', nextPending: [7]), 7), isTrue);
  expect(isAwaitingUser(docFixture(status: 'pending', nextPending: [8]), 7), isFalse);
  expect(isAwaitingUser(docFixture(status: 'approved', nextPending: [7]), 7), isFalse);
});
test('merge cuts leave items older than unloaded documents', () {
  final merged = mergeRequests([leaveAt(DateTime(2026, 9, 1)), leaveAt(DateTime(2026, 10, 10))], [docAt(DateTime(2026, 10, 1))], documentsHaveMore: true);
  expect(merged.map((e) => e.sortDate), [DateTime(2026, 10, 10), DateTime(2026, 10, 1)]);
});
test('role-less user has an empty inbox and no document fetch', () async {
  final c = ProviderContainer(overrides: [currentUserProvider.overrideWithValue(const User(id: 7, name: 'x')), documentsRepositoryProvider.overrideWithValue(ThrowingDocumentsRepository())]);
  expect(c.read(canReviewRequestsProvider), isFalse);
  expect(await c.read(documentsAwaitingMeProvider.future), isEmpty);
  expect(c.read(pendingDecisionsCountProvider), 0);
});
```

`leaveFixture` / `docFixture` build models through `fromJson` with minimal maps. `ThrowingDocumentsRepository` fails the test on any call.

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(requests): unify leave and document requests into one feed"`

---

### Task 8: الطلبات tab screen

**Files:**
- Create: `lib/features/requests/presentation/screens/requests_screen.dart`
- Test: `test/features/requests/requests_screen_test.dart`

**Interfaces:**
- Consumes: Task 7 providers, `leaveBalanceProvider`, `CardSlot`, `StatusPill`, `myLeaveRequestsProvider.notifier.refresh`, `leaveApprovalsProvider.notifier.refresh`.
- Produces: `RequestsScreen({bool openInbox = false})`.

**Layout:**
1. Title `الطلبات`.
2. A segmented control `طلباتي | بانتظار قراري (n)`, only when `canReviewRequestsProvider` is true. `openInbox` selects the second segment.
3. On the طلباتي segment:
   - a balance strip `CardSlot(leaveBalanceProvider)` → chip `سنوية` `'${remainingDays} يوماً'`;
   - filter chips `الكل · قيد الانتظار · مقبولة · مرفوضة` (client-side over the feed);
   - request cards: title, `StatusPill(label: item.status.label, fg: item.status.fg, bg: item.status.bg)`, subtitle, stepLabel. A tap does `context.push(item.route)`.
4. On the inbox segment: the caption `طلبات تنتظر قرارك.`, then cards that also show `requesterName`.
5. An empty feed shows `لا توجد طلبات بعد` on طلباتي, or `لا يوجد ما ينتظر قرارك` on the inbox.
6. A gold extended FAB `طلب جديد` opens a bottom sheet:
   - `إجازة` → `context.push('/attendance/leave/new')`;
   - `مستند من قالب` → `context.push('/documents/new')`, only when `canReviewRequestsProvider`;
   - the footnote `أنواع أخرى من الطلبات الإدارية ستتوفر قريباً.`

Pull-to-refresh refreshes both leave controllers and invalidates both document providers.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('role-less user sees no inbox segment and no document option', (t) async {
  await pumpTestApp(t, const RequestsScreen(), overrides: [currentUserProvider.overrideWithValue(const User(id: 7, name: 'x')), myRequestsFeedProvider.overrideWithValue(const AsyncData([])), leaveBalanceProvider.overrideWith((ref) async => const LeaveBalance(year: 2026, allocatedDays: 14, usedDays: 0, remainingDays: 14))]);
  expect(find.text('بانتظار قراري'), findsNothing);
  await t.tap(find.text('طلب جديد')); await t.pumpAndSettle();
  expect(find.text('مستند من قالب'), findsNothing);
  await t.tap(find.text('إجازة')); await t.pumpAndSettle();
  expect(find.text('route:/attendance/leave/new'), findsOne);
});
testWidgets('manager sees the inbox count and opens on inbox when asked', (t) async { /* manager user; inboxFeedProvider → 2 items; RequestsScreen(openInbox: true) → find.text(requesterName) */ });
testWidgets('tapping a request opens its route', (t) async { /* tap card → find.text('route:/documents/9') */ });
testWidgets('filter chips narrow the list', (t) async { /* tap مرفوضة → only rejected card */ });
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(requests): الطلبات tab with inbox segment and new-request sheet"`

---

### Task 9: الرئيسية — home screen and attention items

**Files:**
- Create: `lib/features/home/domain/attention_items.dart`, `lib/features/home/presentation/home_screen.dart`
- Modify: `lib/features/notifications/presentation/widgets/notification_bell_icon.dart` — add `final bool onDarkBackground` (default `true`, keeps current look). `false` → white 48 px square, `AppColors.border` outline, `AppColors.primary` icon.
- Test: `test/features/home/attention_items_test.dart`, `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `HeroTodayCard`, `monthDaysProvider` + `summarizeMonth`, `leaveBalanceProvider`, `inboxFeedProvider`, `pendingDecisionsCountProvider`, `canReviewRequestsProvider`, `myLeaveRequestsProvider`, `attendanceQueueProvider`, `currentUserProvider`, `fetchAllMyRecords`, card kit, `NotificationBellIcon(onDarkBackground: false)`.
- Produces:
  - `enum AttentionKind { failedCapture, rejectedRecord, missingCheckout, requestDecided }`
  - `class AttentionItem { final AttentionKind kind; final String title; final String subtitle; final String route; }`
  - `List<AttentionItem> buildAttentionItems({required List<AttendanceRecord> recentRecords, required List<PendingAttendanceRecord> failedLocal, required List<LeaveRequest> myLeaves, required DateTime now})` — at most 3, in `AttentionKind` order, newest first within a kind.
  - `final recentRecordsProvider = FutureProvider.autoDispose<List<AttendanceRecord>>` — `fetchAllMyRecords(from: today − 7 days, to: today)`.
  - `HomeScreen()`

**Attention copy:**

| Kind | Source | Title | Subtitle | Route |
|---|---|---|---|---|
| failedCapture | local queue `isFailed` | `لم يُقبل تسجيل ${type.arabicLabel}` | `errorMessage ?? ''` | `/attendance` |
| rejectedRecord | remote `isRejected` | `رُفض تسجيل ${type.arabicLabel} يوم ${arabicWeekdayDayMonth}` | `rejectionReasonLabel` | `/attendance/history?date=yyyy-MM-dd` |
| missingCheckout | remote `isMissingCheckout` | `لم يُسجَّل انصراف يوم ${arabicWeekdayDayMonth}` | `راجع اليوم في دوامي` | `/attendance` |
| requestDecided | my leave approved/rejected with `reviewedAt` within 3 days | `قُبل طلب ${title}` / `رُفض طلب ${title}` | date range | the request route |

**Home layout**, top to bottom:
1. Header: initials avatar (first letters of the first two name words), the greeting `أهلاً`, name, and `departmentName · sectionName` (non-null parts only), with the bell on the end side.
2. `HeroTodayCard(onOpenDay: go('/attendance'))`.
3. A 2-column `StatTile` grid:
   - `رصيد الإجازات` = `remainingDays` `يوماً`, caption `إجازة سنوية`, tap → go `/requests`;
   - `دوام هذا الشهر` = `presentDays` `يوماً`, caption `'${formatDuration(worked)} ساعة عمل'`, tap → go `/attendance`.
4. `UnavailableCard(title: 'الرواتب', body: 'ستظهر هنا رواتبك وكشوفها عند تفعيل الخدمة.')`.
5. `يحتاج انتباهك` + `AttentionRow`s — the whole section is hidden when the list is empty.
6. Only when `canReviewRequestsProvider`: a card `بانتظار قراري` with the count, the top 2 inbox items, and `عرض كل الطلبات` → go `/requests?seg=inbox`.
7. Only when `user.isManager || user.isChief`: `UnavailableCard(title: 'فريقي اليوم', body: 'حضور فريقك اليوم سيظهر هنا عند تفعيل الخدمة.', icon: Icons.groups_outlined)`.

There is no identity strip: employee number and manager are not in today's `/me`.

- [ ] **Step 1: Write the failing tests**

```dart
test('attention items are capped at 3 in priority order', () {
  final items = buildAttentionItems(recentRecords: [missingCheckoutOn(17), rejectedOn(16)], failedLocal: [failedCheckIn()], myLeaves: [approvedYesterday()], now: DateTime(2026, 10, 18, 9));
  expect(items.map((i) => i.kind), [AttentionKind.failedCapture, AttentionKind.rejectedRecord, AttentionKind.missingCheckout]);
});
test('decisions older than 3 days are not attention', () { /* reviewedAt 2026-10-14 → empty */ });
test('rejected record routes to its history day', () { /* route == '/attendance/history?date=2026-10-16' */ });
testWidgets('role-less home has no pending-decisions or team card', (t) async {
  // currentUser role null; inbox/monthDays/leaveBalance/recentRecords overridden with data
  expect(find.text('بانتظار قراري'), findsNothing);
  expect(find.textContaining('فريقي اليوم'), findsNothing);
  expect(find.text('الرواتب · ستتوفر قريباً'), findsOne);
});
testWidgets('manager home shows count and team placeholder', (t) async { /* role manager, 2 inbox items → find.text('2'), find.text('فريقي اليوم · ستتوفر قريباً') */ });
testWidgets('a failing balance does not blank the home', (t) async { /* leaveBalanceProvider throws → find.text('تعذّر تحميل رصيد الإجازات') AND HeroTodayCard still present */ });
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(home): personal home with hero, stats, attention and role layer"`

---

### Task 10: راتبي and حسابي tabs

**Files:**
- Create: `lib/features/salary/presentation/salary_screen.dart`, `lib/features/account/presentation/account_screen.dart`
- Test: `test/features/account/account_screen_test.dart`

**Interfaces:**
- Consumes: `UnavailableCard`, `currentUserProvider`, `authControllerProvider.notifier.logout()`, `appVersionProvider`.
- Produces: `SalaryScreen()`, `AccountScreen()`.

**SalaryScreen:** title `راتبي`, then `UnavailableCard(title: 'الرواتب', body: 'ستظهر هنا كشوف رواتبك الشهرية بتفاصيلها، مع حالة التحويل وتاريخه، عند تفعيل الخدمة.', icon: Icons.account_balance_wallet_outlined)`.

**AccountScreen:**
1. A profile card: 72 px initials avatar, name, `departmentName · sectionName`, and `email` when non-null.
2. Group `الملف والمستندات`:
   - `UnavailableCard(title: 'الملف الوظيفي', body: 'بياناتك الشخصية والوظيفية والعقد والشهادات.')`
   - `UnavailableCard(title: 'مستنداتي والتعاميم', body: 'عقودك وقراراتك والتعاميم الموجهة إليك.')`
   - `UnavailableCard(title: 'التقييم والتطوير', body: 'التقييم الدوري والأهداف والدورات.')`
3. Group `الحساب`: rows `الإشعارات` → push `/notifications` and `عن التطبيق` → push `/about`, then a red `تسجيل الخروج` row. Logout uses the confirmation dialog moved verbatim from `AttendanceScreen._confirmAndLogout`.
4. Footer `'تطبيق الموظف · الإصدار ${isolateLtr(version)}'`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('account shows only fields the API provides', (t) async {
  await pumpTestApp(t, const AccountScreen(), overrides: [currentUserProvider.overrideWithValue(const User(id: 7, name: 'سامر الحلبي', departmentName: 'الإدارة الهندسية')), appVersionProvider.overrideWithValue('2.0.0')]);
  expect(find.text('سامر الحلبي'), findsOne);
  expect(find.text('الإدارة الهندسية'), findsOne);
  expect(find.text('الملف الوظيفي · ستتوفر قريباً'), findsOne);
});
testWidgets('logout asks for confirmation first', (t) async { /* tap تسجيل الخروج → dialog 'هل أنت متأكد من تسجيل الخروج؟'; tap إلغاء → logout not called (fake AuthController notifier) */ });
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(app): راتبي and حسابي tabs with honest placeholders"`

---

### Task 11: App shell, router and deep links

**Files:**
- Create: `lib/core/router/app_shell.dart`
- Modify: `lib/core/router/app_router.dart`, `lib/main.dart`
- Test: `test/core/router_shell_test.dart`

**Interfaces:**
- Consumes: the five tab screens, `pendingDecisionsCountProvider`, `SessionStalenessNotice`, `attendanceCaptureNoticeProvider`.
- Produces:
  - `final rootNavigatorKey = GlobalKey<NavigatorState>()`
  - `String? resolveRedirect({required AuthState auth, required String matchedLocation})` — today's redirect rules moved verbatim, plus: an exact `/attendance/leave` → `/requests?seg=inbox`.
  - `AppShell({required StatefulNavigationShell shell})`
  - `routerProvider` unchanged in name.

**Route tree:**
- `/splash` and `/login` stay at the top level.
- `StatefulShellRoute.indexedStack(builder: AppShell)` with five branches:
  1. `/` → `HomeScreen`. Children use `parentNavigatorKey: rootNavigatorKey`: `documents/new`, `documents/:id`, `notifications`, `notifications/broadcast/:id`, `about` — same builders as today.
  2. `/attendance` → `AttendanceTabScreen`. Children on the root navigator: `history`, `leave` (builder `(_, __) => const SizedBox.shrink()` — `resolveRedirect` forwards it before it builds), `leave/new`, `leave/requests/:id`.
  3. `/requests` → `RequestsScreen(openInbox: state.uri.queryParameters['seg'] == 'inbox')`.
  4. `/salary` → `SalaryScreen`.
  5. `/account` → `AccountScreen`.

**AppShell:**
- `Scaffold` whose body is `Column([SessionStalenessNotice(), Expanded(child: shell)])`.
- `NavigationBar` with destinations الرئيسية (`home_outlined` / `home_rounded`), دوامي (`schedule_outlined` / `schedule`), الطلبات (`assignment_outlined` / `assignment`), with a `Badge(label: count)` when `pendingDecisionsCountProvider > 0`, راتبي (`account_balance_wallet_outlined` / `account_balance_wallet`) and حسابي (`person_outline` / `person`).
- `onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex)`.
- Move `AttendanceScreen._showCaptureNotice` here so the recovery notice appears on any tab.

**main.dart:**
- In `_navigateFromNotification`, replace `router.push('/attendance')` with `router.go('/attendance')` (both call sites). Keep the other pushes.
- `MaterialApp.router.title` becomes `'تطبيق الموظف'`.

- [ ] **Step 1: Write the failing tests**

```dart
const manager = User(id: 8, name: 'm', role: 'manager');
const roleless = User(id: 7, name: 'x');
test('unauthenticated goes to login', () {
  expect(resolveRedirect(auth: const AuthUnauthenticated(), matchedLocation: '/requests'), '/login');
});
test('role-less user cannot open document routes', () {
  expect(resolveRedirect(auth: const AuthAuthenticated(roleless), matchedLocation: '/documents/9'), '/');
});
test('old leave hub forwards to the requests inbox', () {
  expect(resolveRedirect(auth: const AuthAuthenticated(manager), matchedLocation: '/attendance/leave'), '/requests?seg=inbox');
});
testWidgets('legacy deep links resolve', (t) async {
  // Build the real router with tab screens and detail screens replaced by Text stubs through provider overrides
  // (override currentUserProvider + authControllerProvider state = AuthAuthenticated(manager)).
  for (final loc in ['/attendance/leave/requests/5', '/attendance/history?date=2026-10-16', '/documents/9', '/notifications/broadcast/x']) {
    router.go(loc); await t.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), loc);
    expect(find.byType(NavigationBar), findsNothing, reason: '$loc must cover the tab bar');
  }
});
testWidgets('five tabs, badge on الطلبات', (t) async { /* pendingDecisionsCountProvider → 3 ; find.text('الطلبات'), find.text('3') */ });
```

To make the widget test feasible, have `routerProvider` read the five tab builders from a `tabScreensProvider` (`Provider<List<WidgetBuilder>>`) whose default returns the real screens; tests override it with `Text` stubs. Do the same for detail-route builders only if a detail screen's providers make the test impractical; otherwise let them build against overridden repositories.

- [ ] **Step 2: Run** — `flutter test test/core/router_shell_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — `flutter test` → PASS.
- [ ] **Step 5: Manual check on the emulator** — start the backend per memory note `local-dev-backend`, then `flutter run`. Sign in as an employee and as a manager. Check-in from home; go offline (airplane mode) and check out → the hero shows `انصراف محفوظ على الجهاز`; back online → it becomes `اكتمل الدوام`. Tap a leave push notification → the detail opens over the tab bar.
- [ ] **Step 6: Commit** — `git commit -m "feat(app): five-tab shell with preserved deep links"`

---

### Task 12: Remove the superseded screens

**Files:**
- Delete: `lib/features/attendance/presentation/screens/attendance_screen.dart`, `lib/features/attendance/presentation/screens/leave_screen.dart`, `lib/features/documents/presentation/screens/documents_home_screen.dart`; also `leave_balance_card.dart` and `leave_request_tile.dart` if `grep` finds no remaining import.
- Modify: `lib/core/router/app_router.dart` (remove `homeScreenForUser`, `_HomeScreen`), `test/features/auth/authorization_bootstrap_test.dart`, `pubspec.yaml` (`version: 2.0.0+11`, `description: Al-Raqi employee app.`)

- [ ] **Step 1: Update `authorization_bootstrap_test.dart`.** Replace the `homeScreenForUser` / `AttendanceManagerActions` assertions in `'role-less models expose no manager affordances'` with the equivalent shell-era checks: `container.read(canReviewRequestsProvider)` is false for the role-less user and true for `User(id: 8, name: 'Manager', role: 'manager')`. Keep every model assertion above them.
- [ ] **Step 2: Delete the files.** Then run `grep -rn "AttendanceScreen\b\|LeaveScreen\b\|DocumentsHomeScreen\|homeScreenForUser\|LeaveBalanceCard\|LeaveRequestTile" lib test` → expected: no matches. Any remaining non-test usage is a missed migration: fix it before continuing.
- [ ] **Step 3: Run** — `flutter analyze` → no new issues; `flutter test` → all PASS.
- [ ] **Step 4: Commit** — `git commit -m "chore(app): remove role-split home screens superseded by the tab shell"`

---

## Self-Review Notes (filled in by the planner)

- **Spec coverage:**
  - §3.1 → T9
  - §3.2 → T5, T6
  - §3.3 → T7, T8
  - §3.4 → T10 placeholder (follow-up plan)
  - §3.5 → T10 partial (follow-up)
  - §3.6 → T9 placeholder (follow-up)
  - §4.2 → T4, T6
  - §4.3 → existing leave form, reached from T8
  - §4.4 → existing detail screens, reached from T7/T8
  - §4.6 → existing notifications + bell (T9) + deep links (T11)
  - §5 → T2 and every screen
  - §6 → T1, T2
  - §8 → this plan's file map
- **Deliberate deviations from the prototype, forced by today's API:** no late/holiday/absent day states, no identity strip, no admin request types, no team counts — each shows an honest placeholder or is omitted (Global Constraints: never invent a value).
