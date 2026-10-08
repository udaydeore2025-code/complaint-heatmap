import 'package:flutter/material.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/complaint_update.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_theme.dart';

class AdminComplaintDetailsScreen extends StatefulWidget {
  final Complaint complaint;
  final AdminRepository? adminRepository;

  const AdminComplaintDetailsScreen({
    super.key,
    required this.complaint,
    this.adminRepository,
  });

  @override
  State<AdminComplaintDetailsScreen> createState() => _AdminComplaintDetailsScreenState();
}

class _AdminComplaintDetailsScreenState extends State<AdminComplaintDetailsScreen> {
  late final AdminRepository _adminRepository;
  late Complaint _complaint;

  List<ComplaintUpdate> _history = [];
  bool _isLoadingHistory = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
    _adminRepository = widget.adminRepository ?? AdminRepository();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await _adminRepository.fetchStatusHistory(_complaint.id);
    if (!mounted) return;
    setState(() {
      _history = list;
      _isLoadingHistory = false;
    });
  }

  Future<void> _promptStatusUpdate(String targetStatus) async {
    final commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Status to $targetStatus?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are updating status from ${_complaint.status} to $targetStatus.'),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Audit Remark / Note (Optional)',
                hintText: 'e.g. Assigned to Ward 4 crew',
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

    setState(() => _isUpdating = true);

    try {
      await _adminRepository.updateComplaintStatus(
        complaintId: _complaint.id,
        oldStatus: _complaint.status,
        newStatus: targetStatus,
        comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _complaint = _complaint.copyWith(status: targetStatus);
        _isUpdating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $targetStatus'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );

      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
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

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_complaint.status);
    final priorityColor = _getPriorityColor(_complaint.priorityLevel);

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Admin Review'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo if available
            if (_complaint.imageUrl != null && _complaint.imageUrl!.isNotEmpty)
              Container(
                height: 220,
                color: Colors.black,
                child: Image.network(
                  _complaint.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image, size: 48, color: Colors.white54),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      // Priority Score Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: priorityColor),
                        ),
                        child: Text(
                          '${_complaint.priorityLevel} (Score: ${_complaint.priorityScore.toStringAsFixed(1)})',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: priorityColor,
                            fontSize: 12,
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
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    _complaint.description,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Metrics Card: Upvotes, Downvotes, Confirmations, Related
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Upvotes', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                const SizedBox(height: 4),
                                Text('${_complaint.upvoteCount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Downvotes', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                const SizedBox(height: 4),
                                Text('${_complaint.downvoteCount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Confirmations', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                const SizedBox(height: 4),
                                Text('${_complaint.confirmationCount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Related Issues', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                const SizedBox(height: 4),
                                Text('${_complaint.relatedComplaintCount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Exact Location Pinpoint Card
                  const Text(
                    'Exact Location & Coordinates',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                            const Icon(Icons.location_on, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _complaint.address ?? 'GPS Coordinate Pinpoint',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Latitude: ${_complaint.latitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Longitude: ${_complaint.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Admin Action Buttons (Phase 20)
                  const Text(
                    'Administrative Actions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _isUpdating
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Verify button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _complaint.status == 'VERIFIED'
                                    ? null
                                    : () => _promptStatusUpdate('VERIFIED'),
                                icon: const Icon(Icons.verified),
                                label: const Text('MARK AS VERIFIED'),
                              ),
                              const SizedBox(height: 10),

                              // 2. Work In Progress button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B5CF6),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _complaint.status == 'WORK IN PROGRESS'
                                    ? null
                                    : () => _promptStatusUpdate('WORK IN PROGRESS'),
                                icon: const Icon(Icons.engineering_outlined),
                                label: const Text('MARK AS WORK IN PROGRESS'),
                              ),
                              const SizedBox(height: 10),

                              // 3. Solved button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _complaint.status == 'SOLVED'
                                    ? null
                                    : () => _promptStatusUpdate('SOLVED'),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('MARK AS SOLVED'),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Audit History Timeline
                  const Text(
                    'Status Change Audit Trail',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _isLoadingHistory
                        ? const Center(child: CircularProgressIndicator())
                        : _history.isEmpty
                            ? const Text(
                                'No previous status updates recorded yet.',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              )
                            : Column(
                                children: _history.map((u) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.history, size: 16, color: Color(0xFF0F766E)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Changed to ${u.newStatus}${u.comment != null ? ' ("${u.comment}")' : ''}',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
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

