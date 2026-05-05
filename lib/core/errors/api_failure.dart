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
  });

  final ApiErrorCode code;
  final String message;
  final int? statusCode;

  /// Per-field validation errors from a 422 response.
  /// Keys are field names, values are lists of human-readable messages.
  final Map<String, List<String>>? fieldErrors;

  /// First validation message for [field], or null.
  String? firstErrorFor(String field) => fieldErrors?[field]?.first;

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
    case ApiErrorCode.serverError:
      return 'خطأ في الخادم. حاول مرة أخرى.';
    case ApiErrorCode.network:
      return 'تعذر الاتصال بالشبكة. تحقق من الإنترنت.';
    case ApiErrorCode.unknown:
      return fallback ?? 'حدث خطأ غير متوقع.';
  }
}
