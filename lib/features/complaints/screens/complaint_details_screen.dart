import 'package:flutter/material.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/complaint_update.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class ComplaintDetailsScreen extends StatefulWidget {
  final Complaint initialComplaint;
  final UserPosition? userLocation;
  final ComplaintRepository? complaintRepository;
  final UserProfile? userProfile;
  final AdminRepository? adminRepository;

  const ComplaintDetailsScreen({
    super.key,
    required this.initialComplaint,
    this.userLocation,
    this.complaintRepository,
    this.userProfile,
    this.adminRepository,
  });

  @override
  State<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends State<ComplaintDetailsScreen> {
  late final ComplaintRepository _complaintRepository;
  late final AdminRepository _adminRepository;
  late Complaint _complaint;

  List<ComplaintUpdate> _statusHistory = [];
  List<Complaint> _relatedComplaints = [];
  bool _isActionInProgress = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _complaint = widget.initialComplaint;
    _complaintRepository = widget.complaintRepository ?? ComplaintRepository();
    _adminRepository = widget.adminRepository ?? AdminRepository();
    _loadDetails();
    _realtimeChannel = _complaintRepository.subscribeToComplaint(
      complaintId: _complaint.id,
      onUpdate: () {
        if (mounted) {
          _loadDetails();
        }
      },
    );
  }

  @override
  void dispose() {
    _complaintRepository.unsubscribe(_realtimeChannel);
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final history = await _complaintRepository.fetchStatusHistory(_complaint.id);
    final related = await _complaintRepository.fetchRelatedComplaints(
      _complaint.id,
      latitude: _complaint.latitude,
      longitude: _complaint.longitude,
    );

    // Refresh complaint metrics
    final fresh = await _complaintRepository.fetchComplaintById(
      _complaint.id,
      userLocation: widget.userLocation,
    );

    if (!mounted) return;
    setState(() {
      _statusHistory = history;
      _relatedComplaints = related;
      if (fresh != null) {
        _complaint = fresh;
      }
    });
  }

  Future<void> _handleVote(String voteType) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      await _complaintRepository.toggleVote(
        complaintId: _complaint.id,
        voteType: voteType,
      );
      final fresh = await _complaintRepository.fetchComplaintById(
        _complaint.id,
        userLocation: widget.userLocation,
      );
      if (!mounted) return;
      setState(() {
        if (fresh != null) _complaint = fresh;
        _isActionInProgress = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cast vote: $e')),
      );
    }
  }

  Future<void> _handleConfirm() async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      await _complaintRepository.toggleConfirmation(complaintId: _complaint.id);
      final fresh = await _complaintRepository.fetchComplaintById(
        _complaint.id,
        userLocation: widget.userLocation,
      );
      if (!mounted) return;
      setState(() {
        if (fresh != null) _complaint = fresh;
        _isActionInProgress = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update confirmation: $e')),
      );
    }
  }

  Future<void> _promptAdminStatusUpdate(String targetStatus) async {
    final commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Status to $targetStatus?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update complaint status from ${_complaint.status} to $targetStatus.'),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Official Audit Remark (Optional)',
                hintText: 'e.g. Dispatched maintenance crew',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Update'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);

    try {
      await _adminRepository.updateComplaintStatus(
        complaintId: _complaint.id,
        oldStatus: _complaint.status,
        newStatus: targetStatus,
        comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $targetStatus'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );

      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint?'),
        content: const Text(
          'Are you sure you want to delete this civic complaint? This will permanently remove the report, associated photo, and votes. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.priorityCritical,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);

    try {
      await _complaintRepository.deleteComplaint(_complaint.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complaint deleted successfully.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete complaint: $e')),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFF59E0B);
      case 'VERIFIED':
        return const Color(0xFF0284C7);
      case 'WORK IN PROGRESS':
        return const Color(0xFF8B5CF6);
      case 'SOLVED':
        return const Color(0xFF10B981);
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

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year} at $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_complaint.status);
    final priorityColor = _getPriorityColor(_complaint.priorityLevel);
    final currentUserId = _complaintRepository.currentUserId;
    final isOwner = currentUserId != null && _complaint.userId == currentUserId;

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Complaint Details'),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Delete Complaint',
              icon: const Icon(Icons.delete_outline, color: AppTheme.priorityCritical),
              onPressed: _isActionInProgress ? null : _confirmAndDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Complaint Image
            if (_complaint.imageUrl != null && _complaint.imageUrl!.isNotEmpty)
              Container(
                height: 240,
                width: double.infinity,
                color: Colors.black,
                child: Image.network(
                  _complaint.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image, size: 48, color: Colors.white54),
                  ),
                ),
              )
            else
              Container(
                height: 140,
                color: AppTheme.primaryContainer.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.report_problem_outlined, size: 40, color: AppTheme.primaryColor),
                      const SizedBox(height: 6),
                      const Text(
                        'No photo attached with report',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category, Priority, and Status Badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _complaint.category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Priority Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: priorityColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${_complaint.priorityLevel} (${_complaint.priorityScore.toStringAsFixed(0)})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: priorityColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _complaint.status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Text(
                    _complaint.description,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Reported Date
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        'Reported ${_formatDateTime(_complaint.createdAt)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Municipal Administrative Actions Panel (If Admin)
                  if (widget.userProfile?.isAdmin == true) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.admin_panel_settings, color: Color(0xFF38BDF8), size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                'MUNICIPAL ADMINISTRATIVE ACTIONS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor, width: 0.8),
                                ),
                                child: Text(
                                  _complaint.status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Handle this complaint by updating its status with recorded audit trail:',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _complaint.status == 'VERIFIED'
                                        ? const Color(0xFF334155)
                                        : const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.verified, size: 16),
                                  label: const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: (_isActionInProgress || _complaint.status == 'VERIFIED')
                                      ? null
                                      : () => _promptAdminStatusUpdate('VERIFIED'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _complaint.status == 'WORK IN PROGRESS'
                                        ? const Color(0xFF334155)
                                        : const Color(0xFF8B5CF6),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.engineering_outlined, size: 16),
                                  label: const Text('In Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: (_isActionInProgress || _complaint.status == 'WORK IN PROGRESS')
                                      ? null
                                      : () => _promptAdminStatusUpdate('WORK IN PROGRESS'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _complaint.status == 'SOLVED'
                                        ? const Color(0xFF334155)
                                        : const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline, size: 16),
                                  label: const Text('Solve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: (_isActionInProgress || _complaint.status == 'SOLVED')
                                      ? null
                                      : () => _promptAdminStatusUpdate('SOLVED'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Reddit-Style Voting & Community Confirmation Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Upvote
                            InkWell(
                              onTap: () => _handleVote('UPVOTE'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _complaint.currentUserVote == 'UPVOTE'
                                      ? AppTheme.primaryColor.withValues(alpha: 0.15)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.thumb_up,
                                      size: 18,
                                      color: _complaint.currentUserVote == 'UPVOTE'
                                          ? AppTheme.primaryColor
                                          : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_complaint.upvoteCount}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _complaint.currentUserVote == 'UPVOTE'
                                            ? AppTheme.primaryColor
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Downvote
                            InkWell(
                              onTap: () => _handleVote('DOWNVOTE'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _complaint.currentUserVote == 'DOWNVOTE'
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.thumb_down,
                                      size: 18,
                                      color: _complaint.currentUserVote == 'DOWNVOTE'
                                          ? AppTheme.priorityCritical
                                          : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_complaint.downvoteCount}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _complaint.currentUserVote == 'DOWNVOTE'
                                            ? AppTheme.priorityCritical
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Community Confirmation Status
                            Text(
                              '${_complaint.confirmationCount} confirmed',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Community Confirmation Button (Phase 17)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _complaint.isConfirmedByCurrentUser
                                ? const Color(0xFFDCFCE7)
                                : Colors.white,
                            side: BorderSide(
                              color: _complaint.isConfirmedByCurrentUser
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.primaryColor,
                            ),
                          ),
                          onPressed: _handleConfirm,
                          icon: Icon(
                            _complaint.isConfirmedByCurrentUser
                                ? Icons.check_circle
                                : Icons.verified_outlined,
                            color: _complaint.isConfirmedByCurrentUser
                                ? const Color(0xFF16A34A)
                                : AppTheme.primaryColor,
                          ),
                          label: Text(
                            _complaint.isConfirmedByCurrentUser
                                ? 'You confirmed this issue (Tap to undo)'
                                : 'I can confirm this issue (I observed it)',
                            style: TextStyle(
                              color: _complaint.isConfirmedByCurrentUser
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Location & Geofencing Card
                  const Text(
                    'Location & Coordinates',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFFDC2626), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _complaint.address ?? 'GPS Pinpoint Recorded',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'Lat: ${_complaint.latitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Long: ${_complaint.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            ),
                          ],
                        ),
                        if (_complaint.distanceMeters != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.near_me_outlined, size: 14, color: AppTheme.primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                '${LocationService.formatDistance(_complaint.distanceMeters!)} from your current position',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Status Timeline (Phase 18)
                  const Text(
                    'Status Timeline',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _buildTimelineWidget(),
                  ),
                  const SizedBox(height: 24),

                  // Related Complaints Near Location (50m radius)
                  if (_relatedComplaints.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text(
                          'Related Complaints Near This Location',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_relatedComplaints.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _relatedComplaints.length,
                      itemBuilder: (context, index) {
                        final rel = _relatedComplaints[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.alt_route, color: AppTheme.primaryColor),
                            title: Text(
                              rel.category,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              rel.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Text(
                              rel.distanceMeters != null
                                  ? LocationService.formatDistance(rel.distanceMeters!)
                                  : 'Within 50m',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                if (isOwner) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.priorityCritical,
                        side: const BorderSide(color: AppTheme.priorityCritical),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(
                        'DELETE THIS COMPLAINT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _isActionInProgress ? null : _confirmAndDelete,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTimelineWidget() {
    final steps = ['PENDING', 'VERIFIED', 'WORK IN PROGRESS', 'SOLVED'];
    final currentStatusIndex = steps.indexOf(_complaint.status.toUpperCase());

    return Column(
      children: [
        // Stepper dots
        Row(
          children: List.generate(steps.length, (index) {
            final isCompleted = index <= currentStatusIndex;
            return Expanded(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: isCompleted ? AppTheme.primaryColor : const Color(0xFFCBD5E1),
                    child: Icon(
                      isCompleted ? Icons.check : Icons.circle,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  if (index < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 3,
                        color: index < currentStatusIndex
                            ? AppTheme.primaryColor
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // Step names
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Pending', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            Text('In Progress', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            Text('Solved', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
        if (_statusHistory.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _statusHistory.map((u) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 8, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Marked as ${u.newStatus}${u.comment != null ? ' - ${u.comment}' : ''} on ${_formatDateTime(u.createdAt)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
