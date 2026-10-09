import 'package:flutter/material.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_complaint_details_screen.dart';
import 'admin_map_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final UserProfile profile;
  final AuthRepository? authRepository;
  final AdminRepository? adminRepository;

  const AdminDashboardScreen({
    super.key,
    required this.profile,
    this.authRepository,
    this.adminRepository,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AuthRepository _authRepo;
  late final AdminRepository _adminRepo;

  AdminSummary _summary = const AdminSummary();
  List<Complaint> _priorityQueue = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL';

  final List<String> _filters = [
    'ALL',
    'PENDING',
    'VERIFIED',
    'WORK IN PROGRESS',
    'SOLVED',
  ];

  @override
  void initState() {
    super.initState();
    _authRepo = widget.authRepository ?? AuthRepository();
    _adminRepo = widget.adminRepository ?? AdminRepository();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _adminRepo.fetchDashboardSummary();
      final queue = await _adminRepo.fetchPriorityQueue(
        statusFilter: _selectedFilter == 'ALL' ? null : _selectedFilter,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _priorityQueue = queue;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load dashboard: $e')),
      );
    }
  }

  void _onFilterChanged(String filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
    _loadDashboardData();
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

  Widget _buildMetricCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Console',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'CivicConnect Municipal Portal',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Hotspot Map',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => AdminMapScreen(adminRepository: _adminRepo),
                ),
              ).then((_) => _loadDashboardData());
            },
          ),
          IconButton(
            tooltip: 'Refresh Data',
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('Are you sure you want to end your administrative session?'),
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
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _authRepo.signOut();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  // Admin identity badge
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: const Color(0xFF1E293B),
                      child: Row(
                        children: [
                          const Icon(Icons.shield, color: AppTheme.priorityCritical, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Logged in: ${widget.profile.name ?? widget.profile.email}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.priorityCritical.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.priorityCritical, width: 0.8),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                color: AppTheme.priorityCritical,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Metrics header
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Operational Overview',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),

                  // Grid of summary metric cards
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        _buildMetricCard(
                          label: 'Total Reports',
                          count: _summary.totalComplaints,
                          icon: Icons.assignment_outlined,
                          color: const Color(0xFF0F172A),
                        ),
                        _buildMetricCard(
                          label: 'Pending Review',
                          count: _summary.pendingCount,
                          icon: Icons.hourglass_empty,
                          color: const Color(0xFFF59E0B),
                        ),
                        _buildMetricCard(
                          label: 'Verified Issues',
                          count: _summary.verifiedCount,
                          icon: Icons.verified,
                          color: const Color(0xFF0284C7),
                        ),
                        _buildMetricCard(
                          label: 'Work In Progress',
                          count: _summary.workInProgressCount,
                          icon: Icons.engineering_outlined,
                          color: const Color(0xFF8B5CF6),
                        ),
                        _buildMetricCard(
                          label: 'Resolved Issues',
                          count: _summary.solvedCount,
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF10B981),
                        ),
                        _buildMetricCard(
                          label: 'High/Critical Prio',
                          count: _summary.highPriorityCount,
                          icon: Icons.warning_amber_rounded,
                          color: AppTheme.priorityCritical,
                        ),
                      ],
                    ),
                  ),

                  // Priority Queue section title
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.format_list_numbered, color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Priority Queue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_priorityQueue.length} issues',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Filter chips row
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 48,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final f = _filters[index];
                          final isSelected = _selectedFilter == f;
                          return ChoiceChip(
                            label: Text(f),
                            selected: isSelected,
                            onSelected: (_) => _onFilterChanged(f),
                            selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppTheme.primaryColor : const Color(0xFF475569),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 8),
                  ),

                  // Priority queue items
                  _priorityQueue.isEmpty
                      ? const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF94A3B8)),
                                  SizedBox(height: 12),
                                  Text(
                                    'No complaints in this queue',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final complaint = _priorityQueue[index];
                                final prioColor = _getPriorityColor(complaint.priorityLevel);
                                final statusColor = _getStatusColor(complaint.status);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (ctx) => AdminComplaintDetailsScreen(
                                            complaint: complaint,
                                            adminRepository: _adminRepo,
                                          ),
                                        ),
                                      );
                                      // Refresh upon return to reflect status updates
                                      _loadDashboardData();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Row 1: Priority score + Category + Status
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: prioColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: prioColor, width: 0.8),
                                                ),
                                                child: Text(
                                                  '${complaint.priorityLevel} (${complaint.priorityScore.toStringAsFixed(1)})',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11,
                                                    color: prioColor,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  complaint.category.toUpperCase(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 11,
                                                    color: Color(0xFF334155),
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  complaint.status,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),

                                          // Description
                                          Text(
                                            complaint.description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 8),

                                          // Location address if available
                                          if (complaint.address != null && complaint.address!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 8.0),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.place_outlined,
                                                    size: 14,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      complaint.address!,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(0xFF64748B),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Metrics row: Upvotes, Downvotes, Confirmations, Related
                                          Row(
                                            children: [
                                              const Icon(Icons.thumb_up_alt_outlined, size: 14, color: Color(0xFF64748B)),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${complaint.upvoteCount}',
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                              ),
                                              const SizedBox(width: 14),
                                              const Icon(Icons.thumb_down_alt_outlined, size: 14, color: Color(0xFF64748B)),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${complaint.downvoteCount}',
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                              ),
                                              const SizedBox(width: 14),
                                              const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF64748B)),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${complaint.confirmationCount}',
                                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                              ),
                                              if (complaint.relatedComplaintCount > 0) ...[
                                                const SizedBox(width: 14),
                                                const Icon(Icons.layers_outlined, size: 14, color: Color(0xFF0F766E)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${complaint.relatedComplaintCount} related',
                                                  style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                              const Spacer(),
                                              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                          const SizedBox(height: 8),

                                          // Quick Admin Handling Buttons
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFF0284C7),
                                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  icon: const Icon(Icons.verified, size: 14),
                                                  label: const Text('Verify', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                  onPressed: complaint.status == 'VERIFIED'
                                                      ? null
                                                      : () async {
                                                          await _adminRepo.updateComplaintStatus(
                                                            complaintId: complaint.id,
                                                            oldStatus: complaint.status,
                                                            newStatus: 'VERIFIED',
                                                            comment: 'Verified by municipal officer',
                                                          );
                                                          _loadDashboardData();
                                                        },
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFF8B5CF6),
                                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  icon: const Icon(Icons.engineering_outlined, size: 14),
                                                  label: const Text('In Progress', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                  onPressed: complaint.status == 'WORK IN PROGRESS'
                                                      ? null
                                                      : () async {
                                                          await _adminRepo.updateComplaintStatus(
                                                            complaintId: complaint.id,
                                                            oldStatus: complaint.status,
                                                            newStatus: 'WORK IN PROGRESS',
                                                            comment: 'Assigned to field maintenance crew',
                                                          );
                                                          _loadDashboardData();
                                                        },
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFF10B981),
                                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  icon: const Icon(Icons.check_circle_outline, size: 14),
                                                  label: const Text('Solve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                  onPressed: complaint.status == 'SOLVED'
                                                      ? null
                                                      : () async {
                                                          await _adminRepo.updateComplaintStatus(
                                                            complaintId: complaint.id,
                                                            oldStatus: complaint.status,
                                                            newStatus: 'SOLVED',
                                                            comment: 'Resolved by municipal authority',
                                                          );
                                                          _loadDashboardData();
                                                        },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _priorityQueue.length,
                            ),
                          ),
                        ),
                ],
              ),
      ),
    );
  }
}
