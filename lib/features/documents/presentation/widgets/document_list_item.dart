import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/user.dart';
import '../../domain/document.dart';
import '../../../../shared/widgets/status_chip.dart';

/// Card widget for each document in the inbox / sent list.
///
/// Layout:
///   ┌──────────────────────────────────┬───┐
///   │  StatusChip        DOC-2419      │ ▌ │  ← accent bar (status color)
///   │  Title of document …             │ ▌ │
///   │  👤 Creator  ·  🕐 Date          │ ▌ │
///   │                          ‹       │ ▌ │  ← chevron
///   └──────────────────────────────────┴───┘
class AlraqiDocCard extends StatelessWidget {
  const AlraqiDocCard({
    super.key,
    required this.document,
    required this.currentUser,
    required this.onTap,
  });

  final Document document;
  final User? currentUser;
  final VoidCallback onTap;

  Color get _statusColor => switch (document.status) {
        DocumentStatus.pending => AppColors.pending,
        DocumentStatus.approved => AppColors.approved,
        DocumentStatus.rejected => AppColors.rejected,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // ── Main content ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Content column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top: StatusChip + doc code
                          Row(
                            children: [
                              StatusChip(status: document.status, dense: true),
                              const Spacer(),
                              Text(
                                'DOC-${document.id}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: AppColors.text3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Title
                          Text(
                            document.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Meta row: creator + date
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 13,
                                color: AppColors.text2,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  document.creator.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.access_time,
                                size: 13,
                                color: AppColors.text2,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _formatDate(document.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Chevron — points left (→ inward in RTL)
                    const Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: AppColors.text3,
                    ),
                  ],
                ),
              ),

              // ── Accent bar on RIGHT edge ───────────────────────────
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعات';
    }
    if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} أيام';
    }
    return DateFormat('yyyy/MM/dd').format(date);
  }
}

/// Kept as a type alias so existing imports continue to compile.
typedef DocumentListItem = AlraqiDocCard;