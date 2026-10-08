import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../complaints/screens/my_complaints_screen.dart';
import '../../map/screens/complaint_map_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final AuthRepository? authRepository;
  final ComplaintRepository? complaintRepository;

  const ProfileScreen({
    super.key,
    required this.profile,
    this.authRepository,
    this.complaintRepository,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthRepository _authRepo;
  late final ComplaintRepository _complaintRepo;
  UserCivicStats _stats = const UserCivicStats();
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _authRepo = widget.authRepository ?? AuthRepository();
    _complaintRepo = widget.complaintRepository ?? ComplaintRepository();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _complaintRepo.fetchUserStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Citizen Profile'),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('Are you sure you want to sign out from CivicConnect?'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // User Avatar Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    child: Text(
                      widget.profile.initials,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.profile.name ?? 'Civic Contributor',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.profile.email,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'VERIFIED CITIZEN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Contribution Statistics
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Civic Activity & Impact',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  _isLoadingStats
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        ))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('Reported', _stats.totalComplaints, Icons.campaign_outlined),
                            _buildStatItem('Resolved', _stats.totalResolved, Icons.check_circle_outline),
                            _buildStatItem('Confirmed', _stats.totalConfirmations, Icons.verified_outlined),
                            _buildStatItem('Upvotes', _stats.totalUpvotesReceived, Icons.thumb_up_outlined),
                          ],
                        ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Navigation Links
            Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.assignment_outlined, color: AppTheme.primaryColor),
                    title: const Text('My Reported Issues', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Track status of your submissions'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => MyComplaintsScreen(complaintRepository: _complaintRepo),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.map_outlined, color: Color(0xFF0284C7)),
                    title: const Text('Civic Map', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Explore neighborhood complaints on map'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => ComplaintMapScreen(complaintRepository: _complaintRepo),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // App Version Badge
            const Text(
              '${AppConstants.appName} • ${AppConstants.appTagline}',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Version 1.0 (No-AI Deterministic Engine)',
              style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: AppTheme.primaryColor),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

