/// Authenticated user. Returned by the login endpoint and embedded in
/// document/workflow responses.
class User {
  const User({
    required this.id,
    required this.name,
    this.email,
    this.role,
    this.departmentId,
    this.sectionId,
  });

  final int id;
  final String name;
  final String? email;
  final String? role; // 'admin', 'manager', or 'chief'
  final int? departmentId;
  final int? sectionId;

  bool get isAdmin => role == 'admin';
  bool get isChief => role == 'chief';

  factory User.empty() => const User(
    id: 0,
    name: '',
    email: '',
    role: 'manager',
  );

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String?,      // ← safe nullable cast
    role: (json['role'] as String?) ?? 'manager',
    departmentId: json['department_id'] as int?,
    sectionId: json['section_id'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'department_id': departmentId,
    'section_id': sectionId,
  };
}