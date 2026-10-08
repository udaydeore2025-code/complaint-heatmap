import 'package:flutter/material.dart';
import '../core/models/complaint.dart';
import '../core/services/location_service.dart';
import '../core/theme/app_theme.dart';

class ComplaintCard extends StatelessWidget {
  final Complaint complaint;
  final VoidCallback? onTap;
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onConfirm;

  const ComplaintCard({
    super.key,
    required this.complaint,
    this.onTap,
    this.onUpvote,
    this.onDownvote,
    this.onConfirm,
  });

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFF59E0B); // Amber
      case 'VERIFIED':
        return const Color(0xFF0284C7); // Sky blue
      case 'WORK IN PROGRESS':
        return const Color(0xFF8B5CF6); // Purple
      case 'SOLVED':
        return const Color(0xFF10B981); // Emerald green
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _getPriorityColor(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':
        return AppTheme.priorityLow;
      case 'MEDIUM':
        return AppTheme.priorityMedium;
      case 'HIGH':
        return AppTheme.priorityHigh;
      case 'CRITICAL':
        return AppTheme.priorityCritical;
      default:
        return AppTheme.priorityLow;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Pothole':
        return Icons.warning_amber_rounded;
      case 'Garbage':
        return Icons.delete_outline;
      case 'Water Supply':
        return Icons.water_drop_outlined;
      case 'Drainage':
        return Icons.water_damage_outlined;
      case 'Streetlight':
        return Icons.lightbulb_outline;
      case 'Road Damage':
        return Icons.alt_route_outlined;
      case 'Public Area':
        return Icons.park_outlined;
      default:
        return Icons.report_problem_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(complaint.status);
    final priorityColor = _getPriorityColor(complaint.priorityLevel);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Category + Status Badge + Priority Level
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(complaint.category),
                          size: 15,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          complaint.category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Priority score & level
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: priorityColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${complaint.priorityLevel} (${complaint.priorityScore.toStringAsFixed(0)})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      complaint.status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Complaint photo (if present)
            if (complaint.imageUrl != null && complaint.imageUrl!.isNotEmpty)
              Container(
                height: 180,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFF1F5F9),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  complaint.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8)),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  },
                ),
              ),

            // Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                complaint.description,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                  height: 1.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Location & distance / address
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    complaint.distanceMeters != null
                        ? LocationService.formatDistance(complaint.distanceMeters!)
                        : 'Location recorded',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  if (complaint.relatedComplaintCount > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${complaint.relatedComplaintCount} related nearby',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Bottom Metrics Bar: Upvotes, Downvotes, Confirmations
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Upvote
                  InkWell(
                    onTap: onUpvote,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            complaint.currentUserVote == 'UPVOTE'
                                ? Icons.thumb_up
                                : Icons.thumb_up_alt_outlined,
                            size: 16,
                            color: complaint.currentUserVote == 'UPVOTE'
                                ? AppTheme.primaryColor
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${complaint.upvoteCount}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: complaint.currentUserVote == 'UPVOTE'
                                  ? AppTheme.primaryColor
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Downvote
                  InkWell(
                    onTap: onDownvote,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            complaint.currentUserVote == 'DOWNVOTE'
                                ? Icons.thumb_down
                                : Icons.thumb_down_alt_outlined,
                            size: 16,
                            color: complaint.currentUserVote == 'DOWNVOTE'
                                ? AppTheme.priorityCritical
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${complaint.downvoteCount}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: complaint.currentUserVote == 'DOWNVOTE'
                                  ? AppTheme.priorityCritical
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Confirmation count
                  InkWell(
                    onTap: onConfirm,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: complaint.isConfirmedByCurrentUser
                            ? const Color(0xFFDCFCE7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: complaint.isConfirmedByCurrentUser
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${complaint.confirmationCount} confirmed',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: complaint.isConfirmedByCurrentUser
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

