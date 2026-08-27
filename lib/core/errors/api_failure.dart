/// Typed representation of an API failure.
///
/// The backend returns a consistent shape:
/// ```json
/// { "message": "...", "error": "code", "errors": { "field": [...] } }
/// ```
/// This class normalises that into something the UI layer can switch on
/// without parsing strings.
class ApiFailure implements Exception {
  ApiFailure({
    required this.code,
    required this.message,
    this.statusCode,
    this.fieldErrors,
    this.retryAfter,
  });

  final ApiErrorCode code;
  final String message;

  /// HTTP status of the response that produced this failure. Null for
  /// client-side failures (no response was ever received).
  final int? statusCode;

  /// Per-field validation errors from a 422 response.
  /// Keys are field names, values are lists of human-readable messages.
  final Map<String, List<String>>? fieldErrors;

  /// Seconds the caller must wait before retrying, from the `retry_after`
  /// body field or the `Retry-After` header. Only sent with 429 responses.
  final int? retryAfter;

  /// First validation message for [field], or null.
  String? firstErrorFor(String field) => fieldErrors?[field]?.first;

  /// Every validation message whose key is [prefix] or an indexed/nested
  /// child of it (`approver_ids`, `approver_ids.0`, `approver_ids.*`).
  ///
  /// Laravel reports a rejected array element under its index, so a single
  /// deleted approver arrives as `approver_ids.2` — a key the caller cannot
  /// know in advance.
  List<String> errorsForPrefix(String prefix) {
    final errors = fieldErrors;
    if (errors == null) return const [];
    return [
      for (final entry in errors.entries)
        if (entry.key == prefix || entry.key.startsWith('$prefix.'))
          ...entry.value,
    ];
  }

  /// Indices reported against an array field — e.g. `{2}` for
  /// `approver_ids.2`. Lets a form flag exactly the stale selections.
  Set<int> invalidIndicesFor(String prefix) {
    final errors = fieldErrors;
    if (errors == null) return const {};
    final indices = <int>{};
    for (final key in errors.keys) {
      if (!key.startsWith('$prefix.')) continue;
      final index =
          int.tryParse(key.substring(prefix.length + 1).split('.').first);
      if (index != null) indices.add(index);
    }
    return indices;
  }

  @override
  String toString() => 'ApiFailure(${code.name}, $message)';
}

/// Error codes the mobile app should handle, mirroring the table in
/// section 3 of the API docs.
enum ApiErrorCode {
  unauthenticated,
  forbidden,
  notYourTurn,
  notFound,
  noPendingAction,
  routeNotFound,
  documentAlreadyFinalized,
  validationFailed,
  invalidWorkflow,
  chiefCannotActYet,
  chiefAlreadyExists,
  counterNotInitialized,
  duplicateExportNumber,
  documentGenerationDisabled,
  tooManyAttempts,
  serverError,
  network, // client-side: no internet / timeout
  unknown;

  static ApiErrorCode fromString(String? raw) {
    switch (raw) {
      case 'unauthenticated':
        return ApiErrorCode.unauthenticated;
      case 'forbidden':
        return ApiErrorCode.forbidden;
      case 'not_your_turn':
        return ApiErrorCode.notYourTurn;
      case 'not_found':
        return ApiErrorCode.notFound;
      case 'no_pending_action':
        return ApiErrorCode.noPendingAction;
      case 'route_not_found':
        return ApiErrorCode.routeNotFound;
      case 'document_already_finalized':
        return ApiErrorCode.documentAlreadyFinalized;
      case 'validation_failed':
        return ApiErrorCode.validationFailed;
      case 'invalid_workflow':
        return ApiErrorCode.invalidWorkflow;
      case 'chief_cannot_act_yet':
        return ApiErrorCode.chiefCannotActYet;
      case 'chief_already_exists':
        return ApiErrorCode.chiefAlreadyExists;
      case 'counter_not_initialized':
        return ApiErrorCode.counterNotInitialized;
      case 'duplicate_export_number':
        return ApiErrorCode.duplicateExportNumber;
      case 'document_generation_disabled':
        return ApiErrorCode.documentGenerationDisabled;
      case 'too_many_attempts':
        return ApiErrorCode.tooManyAttempts;
      case 'server_error':
        return ApiErrorCode.serverError;
      default:
        return ApiErrorCode.unknown;
    }
  }
}

/// Maps an [ApiErrorCode] to a user-friendly Arabic message.
/// Used as a fallback when the backend message isn't suitable to show as-is.
String arabicMessageFor(ApiErrorCode code, {String? fallback}) {
  switch (code) {
    case ApiErrorCode.unauthenticated:
      return 'انتهت الجلسة. الرجاء تسجيل الدخول مجدداً.';
    case ApiErrorCode.forbidden:
      return 'لا تملك صلاحية تنفيذ هذا الإجراء.';
    case ApiErrorCode.notYourTurn:
      return 'ليس دورك بعد. الرجاء انتظار المعتمد السابق.';
    case ApiErrorCode.notFound:
      return 'العنصر غير موجود.';
    case ApiErrorCode.noPendingAction:
      return 'لا يوجد إجراء معلق لهذا المستند.';
    case ApiErrorCode.routeNotFound:
      return 'حدث خطأ في الاتصال بالخادم.';
    case ApiErrorCode.documentAlreadyFinalized:
      return 'تم اعتماد أو رفض المستند مسبقاً.';
    case ApiErrorCode.validationFailed:
      return fallback ?? 'الرجاء التأكد من صحة البيانات.';
    case ApiErrorCode.invalidWorkflow:
      return 'إعداد سير الموافقة غير صحيح.';
    case ApiErrorCode.chiefCannotActYet:
      return 'لا يمكن للمسؤول الأعلى اتخاذ إجراء قبل انتهاء جميع المدراء من قراراتهم.';
    case ApiErrorCode.chiefAlreadyExists:
      return 'يوجد مسؤول أعلى بالفعل. مسموح بواحد فقط.';
    // The backend writes these four for the end user and pins the wording to
    // the error code, so its message is preferred when one reached us. See
    // docs/ERROR_RESPONSE_HARDENING.md §2 — a typed code is what makes a
    // message safe to display verbatim.
    case ApiErrorCode.counterNotInitialized:
      return fallback ??
          'هذا أول مستند في القسم، يرجى إدخال رقم الصادر لتحديد نقطة البداية.';
    case ApiErrorCode.duplicateExportNumber:
      return fallback ?? 'رقم الصادر مستخدم مسبقاً في هذا القسم.';
    case ApiErrorCode.documentGenerationDisabled:
      return fallback ?? 'إنشاء المستندات من القوالب متوقف حالياً.';
    case ApiErrorCode.tooManyAttempts:
      return fallback ??
          'تم تجاوز عدد محاولات تسجيل الدخول المسموح بها. يرجى المحاولة لاحقاً.';
    case ApiErrorCode.serverError:
      return 'خطأ في الخادم. حاول مرة أخرى.';
    case ApiErrorCode.network:
      return 'تعذر الاتصال بالشبكة. تحقق من الإنترنت.';
    case ApiErrorCode.unknown:
      return fallback ?? 'حدث خطأ غير متوقع.';
  }
}
