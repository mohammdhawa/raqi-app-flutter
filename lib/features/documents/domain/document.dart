import '../../auth/domain/user.dart';

enum DocumentStatus {
  pending,
  approved,
  rejected;

  static DocumentStatus fromString(String? raw) => switch (raw) {
    'approved' => DocumentStatus.approved,
    'rejected' => DocumentStatus.rejected,
    _ => DocumentStatus.pending,
  };
}

enum WorkflowMode {
  sequential,
  parallel;

  static WorkflowMode fromString(String? raw) =>
      raw == 'parallel' ? WorkflowMode.parallel : WorkflowMode.sequential;

  String get apiValue => name;
}

enum WorkflowStepStatus {
  pending,
  approved,
  rejected;

  static WorkflowStepStatus fromString(String? raw) => switch (raw) {
    'approved' => WorkflowStepStatus.approved,
    'rejected' => WorkflowStepStatus.rejected,
    _ => WorkflowStepStatus.pending,
  };
}

enum LogAction {
  created,
  sent,
  approved,
  rejected,
  unknown;

  static LogAction fromString(String? raw) => switch (raw) {
    'created' => LogAction.created,
    'sent' => LogAction.sent,
    'approved' => LogAction.approved,
    'rejected' => LogAction.rejected,
    _ => LogAction.unknown,
  };
}

/// A single approver step in a document's workflow.
class WorkflowStep {
  const WorkflowStep({
    required this.id,
    required this.userId,
    required this.order,
    required this.status,
    required this.user,
    this.signedAt,
    this.note,
  });

  final int id;
  final int userId;
  final int order;
  final WorkflowStepStatus status;
  final User user;
  final DateTime? signedAt;
  final String? note;

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
    id: json['id'] as int,
    userId: json['user_id'] as int,
    order: (json['order'] as num?)?.toInt() ?? 0,
    status: WorkflowStepStatus.fromString(json['status'] as String?),
    user: json['user'] != null
        ? User.fromJson(json['user'] as Map<String, dynamic>)
        : User.empty(),
    signedAt: _parseDate(json['signed_at']),
    note: json['note'] as String?,
  );
}

/// A single audit log entry.
class DocumentLog {
  const DocumentLog({
    required this.id,
    required this.action,
    required this.doneBy,
    required this.createdAt,
    required this.user,
    this.note,
  });

  final int id;
  final LogAction action;
  final int doneBy;
  final DateTime createdAt;
  final User user;
  final String? note;

  factory DocumentLog.fromJson(Map<String, dynamic> json) => DocumentLog(
    id: json['id'] as int,
    action: LogAction.fromString(json['action'] as String?),
    doneBy: json['done_by'] as int,
    createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    user: User.fromJson(json['user'] as Map<String, dynamic>),
    note: json['note'] as String?,
  );
}

/// A document plus its workflow + logs. Returned by both the list
/// endpoint and the details endpoint (logs may be empty in lists).
class Document {
  const Document({
    required this.id,
    required this.title,
    required this.status,
    required this.workflowMode,
    required this.createdAt,
    required this.creator,
    required this.workflows,
    required this.logs,
    this.description,
    this.filePath,
    this.fileName,
    this.fileMime,
    this.fileSize,
    this.nextPendingUsers = const [],
  });

  final int id;
  final String title;
  final String? description;
  final String? filePath;
  final String? fileName;
  final String? fileMime;
  final int? fileSize;
  final DocumentStatus status;
  final WorkflowMode workflowMode;
  final DateTime createdAt;
  final User creator;
  final List<WorkflowStep> workflows;
  final List<DocumentLog> logs;

  /// Only populated by the details endpoint. Tells us who needs to act
  /// next — for sequential mode this is one user, for parallel it can
  /// be many.
  final List<User> nextPendingUsers;

  /// True if the given [user] is currently expected to act on this doc.
  /// Per the docs, this is the canonical "is it my turn?" check.
  bool isTurnOf(User? user) {
    if (user == null) return false;
    if (status != DocumentStatus.pending) return false;
    return nextPendingUsers.any((u) => u.id == user.id);
  }

  bool isImage() => (fileMime ?? '').startsWith('image/');
  bool isPdf() => fileMime == 'application/pdf';

  factory Document.fromJson(
    Map<String, dynamic> json, {
    List<User> nextPendingUsers = const [],
  }) {
    return Document(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      filePath: json['file_path'] as String?,
      fileName: json['file_name'] as String?,
      fileMime: json['file_mime'] as String?,
      fileSize: json['file_size'] as int?,
      status: DocumentStatus.fromString(json['status'] as String?),
      workflowMode: WorkflowMode.fromString(json['workflow_mode'] as String?),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      creator: json['creator'] != null
          ? User.fromJson(json['creator'] as Map<String, dynamic>)
          : User.empty(),
      workflows: ((json['workflows'] as List?) ?? [])
          .map((e) => WorkflowStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      logs: ((json['logs'] as List?) ?? [])
          .map((e) => DocumentLog.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextPendingUsers: nextPendingUsers,
    );
  }

  Document copyWith({
    List<User>? nextPendingUsers,
  }) => Document(
    id: id,
    title: title,
    description: description,
    filePath: filePath,
    fileName: fileName,
    fileMime: fileMime,
    fileSize: fileSize,
    status: status,
    workflowMode: workflowMode,
    createdAt: createdAt,
    creator: creator,
    workflows: workflows,
    logs: logs,
    nextPendingUsers: nextPendingUsers ?? this.nextPendingUsers,
  );
}

/// A page of documents with pagination metadata.
class DocumentsPage {
  const DocumentsPage({
    required this.documents,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<Document> documents;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  factory DocumentsPage.fromJson(Map<String, dynamic> json) {
    final paginator = json['documents'] as Map<String, dynamic>;
    return DocumentsPage(
      documents: ((paginator['data'] as List?) ?? [])
          .map((e) => Document.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: (paginator['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (paginator['last_page'] as num?)?.toInt() ?? 1,
      total: (paginator['total'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}
