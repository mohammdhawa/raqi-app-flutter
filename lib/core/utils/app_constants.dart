/// Centralised constants. Update [baseUrl] before shipping.
class AppConstants {
  AppConstants._();

  /// API base URL. Per the docs: `https://api.yourcompany.com/api`.
  /// Override per-environment if needed (e.g. via --dart-define).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.yourcompany.com/api',
  );

  /// Used to build file URLs from the relative `file_path` returned
  /// by the API: `{storageBase}/storage/{file_path}`.
  static String get storageBase {
    // Strip the trailing /api so we land on the host root.
    if (baseUrl.endsWith('/api')) {
      return baseUrl.substring(0, baseUrl.length - 4);
    }
    return baseUrl;
  }

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Secure storage keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';

  // File upload limit per docs: 20 MB
  static const int maxUploadBytes = 20 * 1024 * 1024;

  // ── Document attachments (optional supporting files) ──
  /// Max number of attachment files per document.
  static const int maxAttachments = 2;

  /// Allowed attachment extensions — slightly broader than the main file
  /// (adds xlsx/xls).
  static const List<String> attachmentAllowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'xlsx',
    'xls',
  ];
}
