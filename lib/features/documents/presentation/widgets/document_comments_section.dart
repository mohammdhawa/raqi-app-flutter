import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/document.dart';
import '../providers/document_comments_controller.dart';

class DocumentCommentsSection extends ConsumerStatefulWidget {
  const DocumentCommentsSection({
    super.key,
    required this.documentId,
    this.onScrollToBottom,
  });

  final int documentId;
  final VoidCallback? onScrollToBottom;

  @override
  ConsumerState<DocumentCommentsSection> createState() =>
      _DocumentCommentsSectionState();
}

class _DocumentCommentsSectionState
    extends ConsumerState<DocumentCommentsSection> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(documentCommentsProvider(widget.documentId).notifier)
          .load(),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final controller =
        ref.read(documentCommentsProvider(widget.documentId).notifier);
    final created = await controller.addComment(
      comment: text,
      visibility: 'all',
    );

    if (!mounted) return;

    if (created != null) {
      _textController.clear();
      widget.onScrollToBottom?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.statusRejected,
          content: Text('حدث خطأ، حاول مرة أخرى'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentCommentsProvider(widget.documentId));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'التعليقات',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                if (state.comments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppColors.pill),
                    ),
                    child: Text(
                      '${state.comments.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Comment list
          _CommentListArea(state: state),
          // Compose bar
          _ComposeBar(
            controller: _textController,
            isPosting: state.isPosting,
            onSend: state.isPosting ? null : _onSend,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comment list area
// ---------------------------------------------------------------------------

class _CommentListArea extends StatelessWidget {
  const _CommentListArea({required this.state});
  final DocumentCommentsState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'لا توجد تعليقات بعد',
            style: TextStyle(color: AppColors.text2),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < state.comments.length; i++) ...[
            _CommentTile(comment: state.comments[i]),
            if (i < state.comments.length - 1)
              const Divider(
                color: AppColors.border,
                height: 1,
                thickness: 1,
              ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single comment row
// ---------------------------------------------------------------------------

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final DocumentComment comment;

  @override
  Widget build(BuildContext context) {
    final name = comment.user.name;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '؟';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar — appears on the right in RTL
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.10),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm  dd/MM/yyyy')
                          .format(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.comment,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compose bar
// ---------------------------------------------------------------------------

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({
    required this.controller,
    required this.isPosting,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isPosting;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.rMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isPosting,
              maxLines: 4,
              minLines: 1,
              maxLength: 2000,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.text,
              ),
              decoration: const InputDecoration(
                hintText: 'اكتب تعليقاً…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.text3,
                ),
                border: InputBorder.none,
                isDense: true,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            height: 36,
            child: isPosting
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: onSend,
                    icon: const Icon(
                      Icons.send,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
