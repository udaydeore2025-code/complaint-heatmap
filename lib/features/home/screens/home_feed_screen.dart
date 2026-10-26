 import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_logo.dart';
import '../../../widgets/complaint_card.dart';
import '../../complaints/screens/report_complaint_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../complaints/screens/complaint_details_screen.dart';
import '../../complaints/screens/my_complaints_screen.dart';
import '../../map/screens/complaint_map_screen.dart';
import '../../profile/screens/profile_screen.dart';

class HomeFeedScreen extends StatefulWidget {
  final UserProfile profile;
  final AuthRepository? authRepository;
  final ComplaintRepository? complaintRepository;
  final VoidCallback? onReportComplaintTap;

  const HomeFeedScreen({
    super.key,
    required this.profile,
    this.authRepository,
    this.complaintRepository,
    this.onReportComplaintTap,
  });

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  late final AuthRepository _authRepository;
  late final ComplaintRepository _complaintRepository;

  UserPosition? _currentLocation;
  bool _isLoading = true;
  String? _errorMessage;
  List<Complaint> _complaints = [];
  RealtimeChannel? _realtimeChannel;

  String _selectedCategory = 'All';
  ComplaintSortMode _sortMode = ComplaintSortMode.mostPriorityLikes;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _complaintRepository = widget.complaintRepository ?? ComplaintRepository();
    _initLocationAndFeed();
    _realtimeChannel = _complaintRepository.subscribeToComplaints(
      onUpdate: () {
        if (mounted) {
          _loadComplaints();
        }
      },
    );
  }

  @override
  void dispose() {
    _complaintRepository.unsubscribe(_realtimeChannel);
    super.dispose();
  }

  Future<void> _initLocationAndFeed() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 1. Fetch current GPS location
    final position = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentLocation = position;
        // If location is unavailable, fall back to sorting by latest
        if (position == null && _sortMode == ComplaintSortMode.nearMe) {
          _sortMode = ComplaintSortMode.latest;
        }
      });
    }

    // 2. Fetch complaints
    await _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    try {
      final list = await _complaintRepository.fetchComplaints(
        categoryFilter: _selectedCategory,
        userLocation: _currentLocation,
        sortMode: _sortMode,
      );
      if (!mounted) return;
      setState(() {
        _complaints = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load complaints. Please check network connection.';
        _isLoading = false;
      });
    }
  }

  String _getSortLabel(ComplaintSortMode mode) {
    switch (mode) {
      case ComplaintSortMode.mostPriorityLikes:
        return 'Most Priority Likes';
      case ComplaintSortMode.highestPriority:
        return 'Highest Priority';
      case ComplaintSortMode.mostUpvoted:
        return 'Most Upvoted';
      case ComplaintSortMode.latest:
        return 'Latest';
      case ComplaintSortMode.nearMe:
        return 'Near Me';
    }
  }

  Future<void> _confirmAndDelete(Complaint complaint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint?'),
        content: const Text(
          'Are you sure you want to delete this civic complaint? This will permanently remove the report, photo, and all community confirmations. This action cannot be undone.',
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

    final previousComplaints = List<Complaint>.from(_complaints);
    setState(() {
      _complaints.removeWhere((c) => c.id == complaint.id);
    });

    try {
      await _complaintRepository.deleteComplaint(complaint.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complaint deleted successfully.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      _loadComplaints();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _complaints = previousComplaints;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete complaint: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 8,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 30, showBadgeBackground: true),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppConstants.appName,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentLocation != null ? Icons.my_location : Icons.location_off_outlined,
                        size: 11,
                        color: _currentLocation != null ? AppTheme.primaryColor : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _currentLocation != null ? 'GPS active' : 'GPS inactive',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Civic Map',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ComplaintMapScreen(
                    complaintRepository: _complaintRepository,
                    initialPosition: _currentLocation,
                  ),
                ),
              ).then((_) => _loadComplaints());
            },
          ),
          IconButton(
            tooltip: 'My Reported Issues',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => MyComplaintsScreen(
                    complaintRepository: _complaintRepository,
                  ),
                ),
              ).then((_) => _loadComplaints());
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('Are you sure you want to sign out of CivicConnect?'),
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
                await _authRepository.signOut();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _loadComplaints,
        child: Column(
          children: [
            // Sorting & Filter bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Sort:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<ComplaintSortMode>(
                      value: _sortMode,
                      isDense: true,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                      items: ComplaintSortMode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(
                            _getSortLabel(mode),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newMode) {
                        if (newMode != null) {
                          setState(() {
                            _sortMode = newMode;
                          });
                          _loadComplaints();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_complaints.length} issues',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal Category Selector
            Container(
              color: Colors.white,
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ComplaintRepository.categories.length,
                itemBuilder: (context, index) {
                  final cat = ComplaintRepository.categories[index];
                  final isSelected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: const Color(0xFFF1F5F9),
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                          _loadComplaints();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primaryColor),
                          SizedBox(height: 16),
                          Text(
                            'Fetching community complaints...',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.cloud_off,
                                  size: 48,
                                  color: AppTheme.priorityCritical,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _loadComplaints,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _complaints.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryContainer.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_outline,
                                        size: 44,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _selectedCategory == 'All'
                                          ? 'No complaints reported yet'
                                          : 'No $_selectedCategory complaints found',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1E293B),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Be the first citizen to report a civic issue in your neighborhood!',
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _complaints.length,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, index) {
                                final complaint = _complaints[index];
                                return ComplaintCard(
                                  complaint: complaint,
                                  onTap: () async {
                                    final deleted = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ComplaintDetailsScreen(
                                          initialComplaint: complaint,
                                          userLocation: _currentLocation,
                                          complaintRepository: _complaintRepository,
                                          userProfile: widget.profile,
                                        ),
                                      ),
                                    );
                                    if (deleted == true) {
                                      if (mounted) {
                                        setState(() {
                                          _complaints.removeWhere((c) => c.id == complaint.id);
                                        });
                                      }
                                    }
                                    _loadComplaints();
                                  },
                                  onUpvote: () async {
                                    try {
                                      await _complaintRepository.toggleVote(
                                        complaintId: complaint.id,
                                        voteType: 'UPVOTE',
                                      );
                                      _loadComplaints();
                                    } catch (e) {
                                      debugPrint('Error voting: $e');
                                    }
                                  },
                                  onDownvote: () async {
                                    try {
                                      await _complaintRepository.toggleVote(
                                        complaintId: complaint.id,
                                        voteType: 'DOWNVOTE',
                                      );
                                      _loadComplaints();
                                    } catch (e) {
                                      debugPrint('Error voting: $e');
                                    }
                                  },
                                  onConfirm: () async {
                                    try {
                                      await _complaintRepository.toggleConfirmation(
                                        complaintId: complaint.id,
                                      );
                                      _loadComplaints();
                                    } catch (e) {
                                      debugPrint('Error confirming: $e');
                                    }
                                  },
                                  onDelete: (complaint.userId == widget.profile.id || widget.profile.role == 'ADMIN')
                                      ? () => _confirmAndDelete(complaint)
                                      : null,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text(
          'Report Complaint',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () async {
          if (widget.onReportComplaintTap != null) {
            widget.onReportComplaintTap!();
          } else {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReportComplaintScreen(
                  complaintRepository: _complaintRepository,
                ),
              ),
            );
            if (result == true) {
              _loadComplaints();
            }
          }
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        height: 64,
        onDestinationSelected: (idx) {
          if (idx == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ComplaintMapScreen(
                  complaintRepository: _complaintRepository,
                  initialPosition: _currentLocation,
                ),
              ),
            ).then((_) => _loadComplaints());
          } else if (idx == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => MyComplaintsScreen(
                  complaintRepository: _complaintRepository,
                ),
              ),
            ).then((_) => _loadComplaints());
          } else if (idx == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ProfileScreen(
                  profile: widget.profile,
                  authRepository: _authRepository,
                  complaintRepository: _complaintRepository,
                ),
              ),
            ).then((_) => _loadComplaints());
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.feed_outlined),
            selectedIcon: Icon(Icons.feed),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Civic Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_turned_in_outlined),
            selectedIcon: Icon(Icons.assignment_turned_in),
            label: 'My Issues',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
