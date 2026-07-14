/// Domain model for a single notification from the backend.
///
/// JSON shape (from `GET /notifications`):
/// ```json
/// {
///   "id": 42,
///   "title": "تمت الموافقة على المستند",
///   "body": "تم اعتماد المستند #1234 من قبل المدير",
///   "type": "approval",
///   "data": { "document_id": 1234 },
///   "broadcast_id": null,
///   "read_at": null,
///   "created_at": "2026-05-17T10:30:00.000000Z"
/// }
/// ```
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.data = const {},
    this.broadcastId,
    this.readAt,
  });

  final int id;
  final String title;
  final String body;
  final NotificationType type;
  final Map<String, dynamic> data;

  /// Stable id of the admin broadcast this notification belongs to, or `null`
  /// for regular (non-broadcast) notifications. Present on both the FCM data
  /// payload and the `GET /notifications` list.
  final String? broadcastId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;
  bool get isUnread => readAt == null;

  /// True when this notification is an admin broadcast — identified by a
  /// non-null [broadcastId] (the added list field) or the `broadcast` type.
  bool get isBroadcast =>
      broadcastId != null || type == NotificationType.broadcast;

  /// Extracts `document_id` from the `data` map when the notification
  /// type is [NotificationType.document] or [NotificationType.approval].
  int? get documentId => _intFromData('document_id');

  /// Extracts `leave_request_id` from the `data` map — present on leave
  /// notifications so navigation can open the relevant request.
  int? get leaveRequestId => _intFromData('leave_request_id');

  int? _intFromData(String key) {
    final raw = data[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Returns a copy with [readAt] set to now (optimistic local update).
  AppNotification markAsRead() => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        data: data,
        broadcastId: broadcastId,
        readAt: readAt ?? DateTime.now(),
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: NotificationType.fromString(json['type'] as String?),
      data: (json['data'] as Map<String, dynamic>?) ?? const {},
      broadcastId: json['broadcast_id'] as String?,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Notification types returned by the backend.
enum NotificationType {
  document,
  approval,
  rejection,
  leave,
  attendanceCheckoutReminder,
  broadcast,
  general;

  static NotificationType fromString(String? raw) {
    switch (raw) {
      case 'document':
        return NotificationType.document;
      case 'approval':
        return NotificationType.approval;
      case 'rejection':
        return NotificationType.rejection;
      case 'leave':
      case 'leave_request':
        return NotificationType.leave;
      case 'attendance_checkout_reminder':
        return NotificationType.attendanceCheckoutReminder;
      case 'broadcast':
        return NotificationType.broadcast;
      case 'general':
        return NotificationType.general;
      default:
        return NotificationType.general;
    }
  }
}

/// Paginated response wrapper matching the Laravel pagination envelope.
class NotificationsPage {
  const NotificationsPage({
    required this.notifications,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<AppNotification> notifications;
  final int currentPage;
  final int lastPage;
  final int total;

  factory NotificationsPage.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as List?) ?? [];
    return NotificationsPage(
      notifications: data
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: json['current_page'] as int? ?? 1,
      lastPage: json['last_page'] as int? ?? 1,
      total: json['total'] as int? ?? 0,
    );
  }
}