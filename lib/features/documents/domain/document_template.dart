/// A reusable document template with a dynamic field schema.
///
/// The Flutter form builder reads [fieldsSchema] to dynamically generate
/// form widgets. Each field descriptor has at minimum:
///   - `key`      (String) — unique identifier
///   - `label`    (String) — display label
///   - `type`     (String) — text | number | date | textarea | select | table
///   - `required` (bool)
///   - `options`  (List<String>?) — only for type=select
///   - `columns`  (List<String>?) — only for type=table
class DocumentTemplate {
  const DocumentTemplate({
    required this.id,
    required this.name,
    required this.slug,
    required this.type,
    required this.fieldsSchema,
    required this.layoutKey,
    this.description,
    this.version = 1,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String type;
  final List<Map<String, dynamic>> fieldsSchema;
  final String layoutKey;
  final int version;
  final bool isActive;

  factory DocumentTemplate.fromJson(Map<String, dynamic> json) {
    return DocumentTemplate(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      type: json['type'] as String,
      fieldsSchema: ((json['fields_schema'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      layoutKey: (json['layout_key'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}