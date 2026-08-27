/// Centralised constants. Update [baseUrl] before shipping.
class AppConstants {
  AppConstants._();

  /// API base URL. Per the docs: `https://api.yourcompany.com/api`.
  /// Override per-environment if needed (e.g. via --dart-define).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.yourcompany.com/api',
  );

  // ── Document file endpoints ───────────────────────────────────────
  //
  // Document bytes are fetched from these authenticated API routes, never
  // from `{host}/storage/{file_path}`. The public disk is served straight
  // off the filesystem by nginx with no auth in front of it (see the
  // backend's docs/STORAGE_EXPOSURE_FINDINGS.md), so a `/storage` URL built
  // from `file_path` hands the file to anybody who has the path — including
  // after the viewer's token is revoked or they leave the company.
  //
  // `file_path` and `stamped_file_path` stay on the model as metadata (they
  // name the stored file and drive the filename fallback), but they are not
  // URLs and must not be turned into one.

  /// `GET /documents/{id}/file` — the main uploaded/generated file.
  static String documentFileUrl(int documentId) =>
      '$baseUrl/documents/$documentId/file';

  /// `GET /documents/{id}/attachments/{attachmentId}/file`
  static String documentAttachmentFileUrl(int documentId, int attachmentId) =>
      '$baseUrl/documents/$documentId/attachments/$attachmentId/file';

  /// `GET /documents/{id}/stamped-pdf` — the incrementally stamped copy.
  static String documentStampedPdfUrl(int documentId) =>
      '$baseUrl/documents/$documentId/stamped-pdf';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Secure storage keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';

  // ── Upload limits ─────────────────────────────────────────────────
  //
  // The main document and its attachments have DIFFERENT ceilings on the
  // backend, and one shared constant silently let the larger of the two
  // through for both: StoreDocumentRequest caps `file` at `max:20480`
  // (20 MB) while `attachments.*` is `max:51200` (50 MB). Picking a 30 MB
  // document passed the client check and then came back as a 422 after the
  // whole upload had been sent.

  /// Main document file — mirrors `file => max:20480` on the backend.
  static const int maxDocumentBytes = 20 * 1024 * 1024;

  /// One attachment — mirrors `attachments.* => max:51200`.
  static const int maxAttachmentBytes = 50 * 1024 * 1024;

  // ── Document attachments (optional supporting files) ──
  /// Max number of attachment files per document — `attachments => max:10`.
  static const int maxAttachments = 10;

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
