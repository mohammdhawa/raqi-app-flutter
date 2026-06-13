import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_constants.dart';

/// A single attachment the user picked from their device, kept in memory
/// until the document is submitted.
class PickedAttachment {
  const PickedAttachment({
    required this.file,
    required this.name,
    required this.size,
  });

  final File file;
  final String name;
  final int size;
}

/// Result of a pick operation — the merged list to adopt plus an optional
/// Arabic error message to surface (e.g. too many files / file too large).
class AttachmentsPickResult {
  const AttachmentsPickResult(this.attachments, this.error);
  final List<PickedAttachment> attachments;
  final String? error;
}

/// Opens the system file picker (multi-select) and merges the chosen files
/// into [current], enforcing the max count and per-file size limits.
/// Returns the merged list and an error string when something was rejected.
Future<AttachmentsPickResult> pickAttachments(
  List<PickedAttachment> current,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: AppConstants.attachmentAllowedExtensions,
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) {
    return AttachmentsPickResult(current, null);
  }

  final merged = [...current];
  String? error;
  for (final picked in result.files) {
    if (picked.path == null) continue;
    if (merged.length >= AppConstants.maxAttachments) {
      error = 'يمكن إرفاق ${AppConstants.maxAttachments} ملفات كحد أقصى.';
      break;
    }
    if (picked.size > AppConstants.maxUploadBytes) {
      error = 'الملف "${picked.name}" يتجاوز الحد الأقصى (20 ميجابايت).';
      continue;
    }
    merged.add(PickedAttachment(
      file: File(picked.path!),
      name: picked.name,
      size: picked.size,
    ));
  }
  return AttachmentsPickResult(merged, error);
}

/// Renders the optional-attachments area: an empty dashed prompt when nothing
/// is selected, otherwise the list of selected files plus an "add more"
/// button. Section header + helper text are supplied by the host screen so
/// the styling matches each form.
class AttachmentsField extends StatelessWidget {
  const AttachmentsField({
    super.key,
    required this.attachments,
    required this.onPick,
    required this.onRemove,
  });

  final List<PickedAttachment> attachments;
  final VoidCallback onPick;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return _buildEmpty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < attachments.length; i++)
          _AttachmentRow(
            attachment: attachments[i],
            onRemove: () => onRemove(i),
          ),
        const SizedBox(height: 4),
        if (attachments.length < AppConstants.maxAttachments) _addMoreButton(),
      ],
    );
  }

  Widget _buildEmpty() {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.attach_file, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'إضافة مرفقات',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addMoreButton() {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('إضافة مرفق آخر'),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, required this.onRemove});

  final PickedAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ext = attachment.name.contains('.')
        ? attachment.name.split('.').last.toUpperCase()
        : 'FILE';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              ext,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatSize(attachment.size),
                  style: const TextStyle(fontSize: 11, color: AppColors.text2),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, size: 16, color: AppColors.text3),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
