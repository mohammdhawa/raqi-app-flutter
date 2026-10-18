# Employee App (تطبيق الموظف) — UI/UX design

**Date:** 2026-10-18 · **Status:** approved in brainstorming, awaiting spec review
**Source requirement:** the project owner's Employee App analysis (11 areas, recorded 2026-09-21, amended 2026-09-22)
**Prototype:** https://claude.ai/artifact/5sJizfy6oetN3oExvedEAy — 16 clickable Arabic RTL screens, fictional data. Source: `docs/design/employee-app-v2/project/*.dc.html` (renders only inside the canvas).

This is a fresh design. The earlier concept in `docs/design/employee-app/` (16 Oct, "three workspaces") was deliberately set aside; nothing here depends on it.

---

## 1. Intent

Every employee — office staff, site workers, drivers — opens the app at least twice a day to record attendance. The app must make that one action effortless, then answer the employee's own questions (my pay, my leave, my requests, my documents) without a call to HR. Managers and HR use the same app to **decide** — approve, check today's team, see what needs attention — while **managing** (creating employees, setting salaries, issuing payroll, reports) stays on the web ERP dashboard.

The app evolves the existing Flutter project (`doc_approval`): same brand, same Riverpod/Dio/GoRouter foundation, same attendance capture and offline queue, same document workflow — new information architecture and presentation.

**Success looks like:**

- Check-in from a cold app start in ≤ 3 taps.
- An employee can answer "how much is my salary, how many leave days do I have, where is my request" from the app alone.
- A manager sees everything waiting on their decision from the home screen.
- The app ships during Stage 1 and lights up card by card as ERP stages land — no screen ever invents a value.

## 2. Decisions taken during brainstorming

| # | Decision | Chosen | Rejected and why |
|---|---|---|---|
| D1 | Starting point | Fresh design | Reviewing the 16 Oct concept — owner chose a clean start |
| D2 | Visual identity | Keep Al-Raqi brand (navy `#224167`, gold `#C8A36B`, rosette, Cairo); new layout | Brand evolution / new direction — the app must still read as the company's |
| D3 | Manager/HR on mobile | **Mobile = decide, web = manage** | Full HR on mobile (duplicates the ERP dashboard); employee+manager only (HR still needs approvals on the go) |
| D4 | Document approval workflow | Kept, **folded into الطلبات** as one request kind | Own tab (fragments "what's waiting on me"); dropped (loses a live feature) |
| D5 | Navigation model | **One 5-tab navigation for everyone + a role layer** | Workspace switcher (mode confusion, built for heavy HR on mobile which D3 rules out); tile-grid home (buries the daily check-in) |
| D6 | Numerals | Western digits for times, amounts, IDs; isolated LTR | Arabic-Indic digits — owner approved Western; revisit only if users ask |
| D7 | Dark mode | Not in v1; tokens named for it | — |

## 3. Information architecture

Five tabs, identical for every role, right-to-left:

```
الرئيسية · دوامي · الطلبات · راتبي · حسابي
```

A notification bell sits in the header of every tab root (area 8). Role adds **content**, never navigation.

### 3.1 الرئيسية — areas 1, 10, 11

Top to bottom:

1. **Identity header** — photo (initials fallback), name, job title · unit, bell with unread count.
2. **Today hero** (navy card, rosette watermark) — today's state, shift, live worked-hours counter, and one gold button that is تسجيل الحضور before check-in and تسجيل الانصراف after. On a holiday or approved leave the button is replaced by the reason. After checkout the hero shows the completed shift.
3. **Stat tiles (3)** — رصيد الإجازات · أيام/ساعات هذا الشهر · راتب الشهر (masked by default, eye toggle; «قيد الإعداد» when the period isn't issued).
4. **يحتاج انتباهك** — at most 3 rows, each one action: circular to acknowledge, a request decided, a missing checkout, a contract nearing its end. Hidden when empty.
5. **Role layer** — rendered only when the server says the capability applies:
   - **بانتظار قراري (n)** — approvers. Top 2 items + «عرض الكل».
   - **فريقي اليوم** — managers. Present/late/absent/leave counts for the subtree; opens the Team screen.
   - **أولويات الموارد البشرية** — HR. Counts that open filtered lists: requests awaiting HR, contracts ending in 30 days, attendance records awaiting review, circulars with low acknowledgement.
6. **Identity strip** — رقم الموظف · المدير المباشر · موقع العمل.

### 3.2 دوامي — area 3

- The today hero (same component as home).
- Offline-queue banner when any capture is pending: «2 تسجيل بانتظار المزامنة · آخر محاولة 10:42 · إعادة المحاولة».
- Month calendar with five day states + legend; future days are neutral, never absence.
- Month totals: days present, late count, absences, leave days, total hours.
- Tap a day → **day sheet**: each record (check-in/out time, location label, selfie thumbnail), worked hours, and per-record status (مؤكد / بانتظار المزامنة / مرفوض + server reason).

### 3.3 الطلبات — areas 4, 5, document workflow

- Segmented control **طلباتي | بانتظار قراري (n)**; the second segment exists only for approvers.
- Leave-balance strip at the top of طلباتي (one chip per leave type).
- Filter chips: الكل · قيد الانتظار · مقبول · مرفوض.
- **+ طلب جديد** → type sheet: إجازة · طلب إداري (server-configured types) · مستند من قالب (existing templates).
- Every request, of every kind, opens one **request detail** layout:
  summary header (type, reference, status pill) → fields → attachments → **approval timeline** → comments → sticky actions the server permits (approve / reject / cancel / return to work).

### 3.4 راتبي — area 2

- Month selector (current + history).
- Status pill: قيد الإعداد / معتمد / تم التحويل · date.
- Net pay hero, shown by default with a «إخفاء» toggle — the user navigated here on purpose. (Home masks the amount by default, because home is glanced at in public.)
- Breakdown in two groups that reconcile to net:
  - **المستحقات:** الراتب الأساسي، البدلات، الحوافز، العمل الإضافي، المكافآت
  - **الاستقطاعات:** الخصومات، قسط سلفة *(labelled «من الإدارة المالية»)*
- «فتح كشف الراتب» → full payslip view (share/save as PDF when ERP provides it).
- Collapsible **تصنيفي** — the nine classification axes plus pay flags, shown in full to the owner (decision 17).

### 3.5 حسابي — areas 6, 7, 9

- Profile header (photo, name, number, title) with «تحديث الصورة» when the photo is missing.
- **الملف الوظيفي** — grouped sheets: المعلومات الشخصية (phone, address), الوظيفة (job, unit, start date, employment type), العقد (type, start, end), الشهادات (list), الخبرات (list), الهوية وجواز السفر. Missing values read «غير مسجّل», never blank. No العهد card (finance scope).
- **مستنداتي** — tabs: مستنداتي (contract, promotion decisions, work certificates, payslips) · التعاميم (each with acknowledgement state).
- **التقييم والتطوير** — التقييم الدوري، الأهداف، ملاحظات المدير، الدورات التدريبية، الإنجازات. Empty state until the Performance module exists.
- الأجهزة · تغيير كلمة المرور · عن التطبيق · تسجيل الخروج.

### 3.6 Role screens (pushed, not tabs)

- **Team screen** (from فريقي اليوم): today's four counts as filter chips, searchable list (photo, name, title, today's state + time), person page with that person's attendance month and leave history. **No salary** unless the caller holds the pay permission for that person. Scope is the manager's subtree (GAP-3, `scope_type: 3`).
- **HR** gets the same Team screen with company scope and a unit filter, plus the priority lists from §3.1.
- Admin actions (add/disable employee, set salary, deductions, payroll, reports) appear as a single «متاح في لوحة ERP» row — no mobile flow.

## 4. Journeys

### 4.1 First sign-in

Login (رقم الموظف + كلمة المرور; email accepted for non-employee accounts) → forced change of the temporary password (enforced by the API; the app only renders it) → permission primer (location, camera, notifications — each with the reason) → home.

Errors are distinct: wrong credentials · rate-limited (with wait time) · inactive account («تواصل مع الموارد البشرية») · network.

### 4.2 Check-in / check-out

1. Hero button → camera for selfie; a location chip reads «جارٍ تحديد الموقع…».
2. Review: selfie thumbnail, time, location + accuracy → **تأكيد**.
3. Outcome:
   - **Confirmed** — green state with time.
   - **Saved on device** — amber «حُفظ على الجهاز · سيُرسل تلقائياً»; never styled as confirmed.
   - **Rejected** — the server's reason, and «إعادة المحاولة».
4. Missing permission → targeted «افتح الإعدادات».

The flow sits on the existing `AttendanceController.checkInOrOut`, `captureWithDraft` recovery, and `AttendanceQueueController` / `AttendanceSyncService` — presentation changes only.

### 4.3 Leave request

Type (balance shown per type) → date range (chargeable days from the server) → reason + attachment (camera / photo / file) → review with **approval-route preview** (المدير المباشر ← مدير الموارد البشرية) → submit → request detail. Cancel and return-to-work appear only when server state allows.

### 4.4 Approving

Inbox card: requester, type, dates, balance after. Detail → sticky bar **موافقة / رفض**; reject requires a reason. After a manager approves, the timeline shows the next step («انتقل إلى مدير الموارد البشرية»), not "completed". Decided requests lose their actions; self-approval is never offered.

### 4.5 Circular acknowledgement

Reader view → sticky bar: checkbox «اطّلعت على المستند» + **تأكيد** → stamp «تم الاطلاع · 18 تشرين الأول 2026 · 09:14». Wording becomes «قرأت ووافقت» only once the owner decides it is a receipt and not a legal signature (spec §8 Q2).

### 4.6 Notifications

| Event | Icon / tone | Opens |
|---|---|---|
| إيداع الراتب | wallet / green | that month's payslip |
| الموافقة على طلب (or rejection) | check / green (✕ / red) | request detail |
| التأخير | clock / orange | that day's sheet |
| تحديث الراتب | trending / navy | راتبي |
| تعميم | megaphone / gold | the circular reader |
| قرب انتهاء العقد | file-clock / orange | العقد sheet |

## 5. Card states (progressive availability)

Every data card is independent. `/api/me/summary` returns `null` per card until its stage lands.

| State | Presentation |
|---|---|
| Ready | value + link to detail |
| Not yet available | quiet card «ستتوفر قريباً» with the module name |
| Empty | short message + next action |
| Loading | skeleton of the same size |
| Error | inline «تعذّر التحميل · إعادة المحاولة»; rest of the screen unaffected |
| Offline | cached value + «آخر تحديث 10:42» |

Hard rules: unissued payroll is «قيد الإعداد», never `0`. A null manager is «غير محدد», never guessed. A permission removed mid-session removes the action and refreshes capabilities.

## 6. Visual system

### 6.1 Colour

Brand and neutrals are the existing `AppColors` tokens unchanged.

| Role | Token |
|---|---|
| Primary (navy) | `#224167` · pressed `#1A3554` |
| Accent (gold) — **primary action only** | `#C8A36B` · soft `#F2E4CC` |
| Canvas / card | `#F6F7FB` / `#FFFFFF` |
| Text / secondary / tertiary | `#1B2A41` / `#6B7591` / `#9099AD` |
| Border | `#E4E6EE` |

New **day-state palette** — each paired with an icon so colour is never the only signal:

| State | Colour | Background | Icon |
|---|---|---|---|
| حاضر | `#2E7D5B` | `#E4F2EC` | check |
| متأخر | `#C2410C` | `#FDEBDD` | clock |
| إجازة | `#2F5FA7` | `#E3ECF8` | suitcase |
| غياب | `#B3261E` | `#FBE7E5` | x |
| عطلة | `#6B5CA5` | `#ECE9F6` | star |

Late is orange, deliberately distinct from the gold accent.

### 6.2 Layout principles

- Light canvas. Navy is reserved for the today hero, headings and the active tab — the existing heavy navy app bar goes.
- Gold means "tap this": check-in button and the single primary CTA per screen.
- The rosette appears once, as a watermark in the hero.

### 6.3 Type, space, shape

- Cairo: 12 meta · 14 body · 16 emphasis · 18 section · 22 page title · 28 hero figures.
- Western digits; times, amounts, IDs isolated LTR.
- Spacing 4/8/12/16/24/32; page inset 16.
- Radius: inputs/buttons 12, cards 16, sheets 24, pills full.
- Targets ≥ 48 dp; directional icons mirrored; layouts tolerate 200 % system text.

### 6.4 Component kit

`HeroTodayCard` · `StatTile` · `AttentionRow` · `StatusPill` (icon + text) · `ApprovalTimeline` · `StickyActionBar` · `AppBottomSheet` · `SegmentedTabs` · `CalendarDayCell` · `SkeletonCard` · `UnavailableCard` · `MaskedAmount` · `RequestCard` · `PersonRow`.

## 7. Requirement coverage

| Area | Where | Notes |
|---|---|---|
| 1 حساب الموظف | الرئيسية | every listed field on home; degrades per card |
| 2 الراتب | راتبي | السلف as a finance-sourced deduction line only |
| 3 الدوام | دوامي + hero | five states incl. عطلة (needs holiday calendar, spec §5.5) |
| 4 الإجازات | الطلبات | attachment supported (spec §5.6); two-step chain |
| 5 الطلبات الإدارية | الطلبات | server-configured types; no طلب سلفة |
| 6 الملف الوظيفي | حسابي | no العهد (finance scope) |
| 7 العقود والمستندات | حسابي ← مستنداتي | acknowledgement as receipt pending Q2 |
| 8 الإشعارات | bell | six typed events, each deep-links |
| 9 التقييم | حسابي ← التقييم والتطوير | empty state until module; «الإيجازات» read as الإنجازات |
| 10 لوحة المدير | home role layer + Team screen | subtree scope, no salary |
| 11 لوحة HR | home role layer + Team screen | decide on mobile; manage on web ERP |

## 8. Reuse map (existing Flutter project)

| Path | Treatment |
|---|---|
| `lib/core/theme/app_colors.dart` | keep tokens; add day-state palette |
| `lib/core/theme/app_theme.dart` | lighter app bar, new type scale |
| `lib/core/router/app_router.dart` | replace the role-based `/` landing with a 5-tab `StatefulShellRoute`; keep redirects and deep-link guards |
| `lib/features/auth/` | `login` field (number or email), forced-change screen |
| `lib/features/attendance/` (data, providers) | unchanged; new presentation |
| `lib/features/attendance/.../leave_*` | reuse controllers; new form steps, attachment, shared request detail |
| `lib/features/documents/` | reuse; template documents become a request kind; add personal library + acknowledgement |
| `lib/features/notifications/` | reuse transport; typed events + deep links |
| `lib/shared/widgets/` | home of the component kit (§6.4) |
| new: `home/`, `payroll/`, `profile/`, `team/` | built as their ERP contracts become available |

## 9. Out of scope

- HR admin flows on mobile (D3).
- طلب سلفة, the advance ledger, العهد — إدارة المالية.
- A colleague directory (spec §8 Q4 open).
- Dark mode (D7).

## 10. Open questions carried from the requirement

1. «قرأت ووافقت» — receipt or signature? (affects §4.5 wording)
2. Evaluation scale and cadence (affects §3.5 content)
3. Holiday calendar owner, per worksite? (affects عطلة)
4. Does area 9's «الإيجازات» mean الإنجازات (assumed) or briefings?
5. Payslip PDF — generated by ERP or rendered in-app?
