import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/complaint.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_launcher_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../complaints/screens/complaint_details_screen.dart';

class ComplaintMapScreen extends StatefulWidget {
  final ComplaintRepository? complaintRepository;
  final UserPosition? initialPosition;

  const ComplaintMapScreen({
    super.key,
    this.complaintRepository,
    this.initialPosition,
  });

  @override
  State<ComplaintMapScreen> createState() => _ComplaintMapScreenState();
}

class _ComplaintMapScreenState extends State<ComplaintMapScreen> {
  late final ComplaintRepository _complaintRepo;
  final MapController _mapController = MapController();

  List<Complaint> _allComplaints = [];
  Complaint? _selectedComplaint;
  bool _isLoading = true;
  String _selectedCategory = 'ALL';
  UserPosition? _userPosition;

  static const LatLng _fallbackCenter = LatLng(18.5204, 73.8567); // Default civic center

  @override
  void initState() {
    super.initState();
    _complaintRepo = widget.complaintRepository ?? ComplaintRepository();
    _userPosition = widget.initialPosition;
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    _userPosition ??= await LocationService.getCurrentLocation();
    await _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    try {
      final list = await _complaintRepo.fetchComplaints(
        categoryFilter: _selectedCategory == 'ALL' ? null : _selectedCategory,
        userLocation: _userPosition,
      );

      if (!mounted) return;
      setState(() {
        _allComplaints = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load map complaints: $e')),
      );
    }
  }

  Color _getMarkerColor(Complaint c) {
    if (c.status == 'SOLVED') return const Color(0xFF16A34A);
    switch (c.priorityLevel.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFDC2626);
      case 'HIGH':
        return const Color(0xFFEA580C);
      case 'MEDIUM':
        return const Color(0xFFD97706);
      case 'LOW':
      default:
        return const Color(0xFF2563EB);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'pothole':
        return Icons.warning_amber_rounded;
      case 'garbage':
        return Icons.delete_outline;
      case 'water supply':
      case 'water':
        return Icons.water_drop_outlined;
      case 'streetlight':
        return Icons.lightbulb_outline;
      case 'drainage':
        return Icons.waves;
      case 'traffic':
        return Icons.traffic;
      default:
        return Icons.report_problem_outlined;
    }
  }

  void _openComplaintDetails(Complaint complaint) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ComplaintDetailsScreen(
          initialComplaint: complaint,
          complaintRepository: _complaintRepo,
          userLocation: _userPosition,
        ),
      ),
    ).then((_) => _loadComplaints());
  }

  void _recenterOnUser() {
    if (_userPosition != null) {
      _mapController.move(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        15.5,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current GPS position unavailable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _fallbackCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Civic Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('OpenStreetMap • Community Issues', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadComplaints,
          ),
        ],
      ),
      body: Stack(
        children: [
          // OpenStreetMap View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialTarget,
              initialZoom: 14.5,
              onTap: (tapPosition, point) {
                if (_selectedComplaint != null) {
                  setState(() => _selectedComplaint = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                maxZoom: 19,
              ),
              MarkerLayer(
                markers: _allComplaints.map((c) {
                  final color = _getMarkerColor(c);
                  final isSelected = _selectedComplaint?.id == c.id;

                  return Marker(
                    point: LatLng(c.latitude, c.longitude),
                    width: isSelected ? 48 : 40,
                    height: isSelected ? 48 : 40,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedComplaint = c);
                        _mapController.move(LatLng(c.latitude, c.longitude), 16.0);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Icon(
                          _getCategoryIcon(c.category),
                          color: Colors.white,
                          size: isSelected ? 22 : 18,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // OpenStreetMap Attribution badge
          Positioned(
            bottom: 4,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Color(0xFF475569)),
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading OpenStreetMap issues...', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          // Category filter pills
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: AppConstants.categories.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = index == 0 ? 'ALL' : AppConstants.categories[index - 1];
                  final isSelected = _selectedCategory == cat;

                  return FilterChip(
                    label: Text(
                      cat.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = cat;
                        _selectedComplaint = null;
                      });
                      _loadComplaints();
                    },
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primaryColor : const Color(0xFFCBD5E1),
                      ),
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),
          ),

          // Recenter GPS FAB
          Positioned(
            bottom: _selectedComplaint != null ? 190 : 20,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter_gps',
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryColor,
              onPressed: _recenterOnUser,
              child: const Icon(Icons.my_location),
            ),
          ),

          // Selected complaint bottom preview card
          if (_selectedComplaint != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedComplaint!.category.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_selectedComplaint!.priorityLevel} PRIORITY',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: () {
                            setState(() => _selectedComplaint = null);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedComplaint!.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_alt_outlined, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '${_selectedComplaint!.upvoteCount}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '${_selectedComplaint!.confirmationCount}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E40AF),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.navigation, size: 13),
                          label: const Text('GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            MapLauncherService.navigateToCoordinates(
                              latitude: _selectedComplaint!.latitude,
                              longitude: _selectedComplaint!.longitude,
                              title: '${_selectedComplaint!.category} Issue',
                              context: context,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _openComplaintDetails(_selectedComplaint!),
                          child: const Text('Details'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
