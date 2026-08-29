import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:flutter_test/flutter_test.dart';

/// The leave-type vocabulary and the fields it added to the balance and to
/// request rows. Every one of them must degrade to the pre-types behaviour
/// when the backend does not send it.
void main() {
  group('LeaveType', () {
    test('parses the picker payload', () {
      final type = LeaveType.fromJson({
        'id': 3,
        'code': 'sick',
        'name_ar': 'إجازة مرضية',
        'name_en': 'Sick leave',
        'deducts_balance': false,
        'requires_reason': true,
      });

      expect(type.id, 3);
      expect(type.code, 'sick');
      expect(type.label, 'إجازة مرضية');
      expect(type.deductsBalance, isFalse);
      expect(type.requiresReason, isTrue);
    });

    // An unreadable flag must never buy free days: the backend's own fallback
    // for anything it cannot resolve is "deducts", so ours is too.
    test('a missing deducts_balance defaults to deducting', () {
      final type = LeaveType.fromJson({
        'id': 1,
        'code': 'annual',
        'name_ar': 'إجازة سنوية',
      });

      expect(type.deductsBalance, isTrue);
      expect(type.requiresReason, isFalse);
      expect(type.nameEn, isNull);
    });

    test('survives a round trip through the local cache', () {
      const original = LeaveType(
        id: 5,
        code: 'unpaid',
        nameAr: 'إجازة بدون راتب',
        nameEn: 'Unpaid',
        deductsBalance: false,
        requiresReason: true,
      );

      final restored = LeaveType.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.code, original.code);
      expect(restored.nameAr, original.nameAr);
      expect(restored.deductsBalance, isFalse);
      expect(restored.requiresReason, isTrue);
    });

    test('falls back through the label chain when name_ar is empty', () {
      expect(
        LeaveType.fromJson({'id': 9, 'code': 'hajj', 'name_en': 'Hajj'}).label,
        'Hajj',
      );
      expect(
        LeaveType.fromJson({'id': 9, 'code': 'hajj'}).label,
        'hajj',
      );
    });
  });

  group('LeaveBalance', () {
    test('reads non_deducting_days and over_balance_days', () {
      final balance = LeaveBalance.fromJson({
        'year': 2026,
        'allocated_days': 21,
        'used_days': 5,
        'remaining_days': 16,
        'over_balance_days': 0,
        'non_deducting_days': 4,
      });

      expect(balance.usedDays, 5);
      expect(balance.remainingDays, 16);
      expect(balance.nonDeductingDays, 4);
      expect(balance.overBalanceDays, 0);
    });

    test('a payload without the new fields behaves exactly as before', () {
      final balance = LeaveBalance.fromJson({
        'year': 2026,
        'allocated_days': 21,
        'used_days': 5,
        'remaining_days': 16,
      });

      expect(balance.nonDeductingDays, 0);
      expect(balance.overBalanceDays, 0);
      expect(balance.remainingDays, 16);
    });

    // The four figures do not reconcile, by design: non-deducting days are
    // outside used_days and do not reduce remaining_days. Asserted so nobody
    // "fixes" the card with arithmetic later.
    test('allocated is not the sum of used, non-deducting and remaining', () {
      final balance = LeaveBalance.fromJson({
        'year': 2026,
        'allocated_days': 21,
        'used_days': 5,
        'remaining_days': 16,
        'non_deducting_days': 4,
      });

      expect(
        balance.usedDays + balance.nonDeductingDays + balance.remainingDays,
        isNot(balance.allocatedDays),
      );
    });
  });

  group('LeaveRequest', () {
    test('parses the ordered approval chain and viewer-specific fields', () {
      final request = LeaveRequest.fromJson({
        'id': 21,
        'start_date': '2026-09-01',
        'end_date': '2026-09-03',
        'status': 'pending',
        'manager_id': '12',
        'current_approver_id': '12',
        'can_review': '1',
        'approvals': [
          {
            'user_id': 7,
            'approval_order': 1,
            'status': 'approved',
            'reviewed_at': '2026-08-29T09:30:00Z',
            'user': {'id': 7, 'name': 'المدير الأول'},
          },
          {
            'user_id': 12,
            'approval_order': '2',
            'status': 'pending',
            'reviewed_at': null,
            'user': {'name': 'المدير الثاني'},
          },
          {
            'user_id': 3,
            'approval_order': 3,
            // Be tolerant of the uppercase spelling used in some payloads.
            'status': 'SKIPPED',
            'user': {'name': 'الرئيس'},
          },
        ],
      });

      expect(request.currentApproverId, 12);
      expect(request.canReview, isTrue);
      expect(request.approvals, hasLength(3));
      expect(request.approvals[0].userName, 'المدير الأول');
      expect(request.approvals[0].reviewedAt, isNotNull);
      expect(request.approvals[1].approvalOrder, 2);
      expect(request.approvals[2].status, LeaveApprovalStatus.skipped);
      expect(request.approvals[2].status.apiValue, 'skipped');
      expect(request.approvals[2].status.arabicLabel, 'تم تجاوزها');
    });

    test('legacy and excuse rows keep absent chain fields nullable', () {
      final request = LeaveRequest.fromJson({
        'id': 22,
        'start_date': '2026-09-01',
        'end_date': '2026-09-01',
        'status': 'approved',
        'is_excuse': true,
      });

      expect(request.approvals, isEmpty);
      expect(request.currentApproverId, isNull);
      expect(request.canReview, isNull);
    });

    test('reads the type, balance snapshot and excuse fields', () {
      final request = LeaveRequest.fromJson({
        'id': 12,
        'start_date': '2026-08-22',
        'end_date': '2026-08-23',
        'status': 'approved',
        'leave_type': 'إجازة مرضية',
        'leave_type_id': 3,
        'deducts_balance': false,
        'is_excuse': true,
        'created_by': 7,
        'manager_id': null,
        'requested_days': 2,
      });

      expect(request.leaveTypeId, 3);
      expect(request.deductsBalance, isFalse);
      expect(request.isExcuse, isTrue);
      expect(request.createdBy, 7);
      expect(request.managerId, isNull);
      expect(request.days, 2);
    });

    test('a row from before types existed still deducts and is no excuse', () {
      final request = LeaveRequest.fromJson({
        'id': 4,
        'start_date': '2026-08-22',
        'end_date': '2026-08-23',
        'status': 'approved',
        'leave_type': 'annual',
        'requested_days': 2,
      });

      expect(request.leaveTypeId, isNull);
      expect(request.deductsBalance, isTrue);
      expect(request.isExcuse, isFalse);
      expect(request.createdBy, isNull);
      // The raw free text is still shown as the label — it just isn't parsed.
      expect(request.leaveType, 'annual');
    });

    test('booleans sent as strings are read as booleans', () {
      final request = LeaveRequest.fromJson({
        'id': 5,
        'start_date': '2026-08-22',
        'end_date': '2026-08-22',
        'status': 'approved',
        'deducts_balance': '0',
        'is_excuse': '1',
      });

      expect(request.deductsBalance, isFalse);
      expect(request.isExcuse, isTrue);
    });

    test('without a server day count it falls back to working days', () {
      // Thu 27 → Sat 29 spans a Friday, which the current calendar charges
      // like any other day.
      final request = LeaveRequest.fromJson({
        'id': 6,
        'start_date': '2026-08-27',
        'end_date': '2026-08-29',
        'status': 'pending',
      });

      expect(request.days, 3);
    });

    // The fallback is a fallback: whenever the server sends a count, that is
    // the number, even if the device's calendar would have said otherwise.
    test('the server day count wins over the local calendar', () {
      final request = LeaveRequest.fromJson({
        'id': 7,
        'start_date': '2026-08-27',
        'end_date': '2026-08-29',
        'status': 'approved',
        'requested_days': 2,
      });

      expect(request.days, 2);
    });
  });

  group('arabicLeaveRuleMessage', () {
    test('translates the three English business rules', () {
      expect(
        arabicLeaveRuleMessage('The selected period contains no working days.'),
        'الفترة المحددة لا تتضمن أي يوم عمل.',
      );
      expect(
        arabicLeaveRuleMessage(
            'Leave request exceeds the remaining annual leave balance.'),
        'طلب الإجازة يتجاوز رصيد الإجازات السنوية المتبقي.',
      );
      expect(
        arabicLeaveRuleMessage(
            'A pending or approved leave request already overlaps this period.'),
        'يوجد طلب إجازة معلق أو معتمد يتداخل مع هذه الفترة.',
      );
    });

    test('tolerates wrapped whitespace and casing', () {
      expect(
        arabicLeaveRuleMessage('  the selected period contains\n'
            'no working days.  '),
        'الفترة المحددة لا تتضمن أي يوم عمل.',
      );
    });

    test('leaves anything else to the caller', () {
      expect(arabicLeaveRuleMessage(null), isNull);
      expect(arabicLeaveRuleMessage(''), isNull);
      // Already-Arabic validation messages are shown as-is, not remapped.
      expect(
        arabicLeaveRuleMessage('نوع الإجازة (إجازة مرضية) يتطلب ذكر السبب.'),
        isNull,
      );
    });
  });

  group('arabicLeaveReviewMessage', () {
    test('translates the untyped not-your-turn validation', () {
      expect(
        arabicLeaveReviewMessage(
          'It is not your turn to review this leave request.',
        ),
        'ليس دورك بعد. الرجاء انتظار المعتمد السابق.',
      );
    });

    test('translates every untyped 422 the review endpoint can return', () {
      // All four carry a bare `message` with no `error` code, so anything this
      // switch misses is shown to an Arabic-only approver in English.
      for (final english in const [
        'Only pending leave requests can be reviewed.',
        'This leave request has no pending approval step.',
        'It is not your turn to review this leave request.',
        'Leave request exceeds the employee remaining annual leave balance.',
      ]) {
        final arabic = arabicLeaveReviewMessage(english);
        expect(arabic, isNotNull, reason: '$english was left untranslated');
        expect(
          RegExp(r'[a-zA-Z]').hasMatch(arabic!),
          isFalse,
          reason: '$english leaked Latin characters into "$arabic"',
        );
      }
    });

    test('the review balance rule is worded differently from the store one',
        () {
      // The store-time sentence says "the remaining", the review-time one says
      // "the employee remaining". They are separate strings on the backend and
      // arabicLeaveRuleMessage catches only the first, which is how the
      // review-time one went untranslated.
      const reviewTime =
          'Leave request exceeds the employee remaining annual leave balance.';
      expect(arabicLeaveRuleMessage(reviewTime), isNull);
      expect(arabicLeaveReviewMessage(reviewTime), isNotNull);
    });

    test('leaves unrelated review messages to the generic mapper', () {
      expect(arabicLeaveReviewMessage(null), isNull);
      expect(
          arabicLeaveReviewMessage('The request is already approved.'), isNull);
    });
  });
}
