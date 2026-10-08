import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/complaint.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
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
  GoogleMapController? _mapController;

  List<Complaint> _allComplaints = [];
  Set<Marker> _markers = {};
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
        _buildMarkers();
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

  double _getMarkerHue(Complaint c) {
    if (c.status == 'SOLVED') return BitmapDescriptor.hueGreen;
    switch (c.priorityLevel.toUpperCase()) {
      case 'CRITICAL':
        return BitmapDescriptor.hueRed;
      case 'HIGH':
        return BitmapDescriptor.hueOrange;
      case 'MEDIUM':
        return BitmapDescriptor.hueYellow;
      case 'LOW':
      default:
        return BitmapDescriptor.hueAzure;
    }
  }

  void _buildMarkers() {
    final markers = <Marker>{};

    for (final c in _allComplaints) {
      final markerHue = _getMarkerHue(c);

      markers.add(
        Marker(
          markerId: MarkerId(c.id),
          position: LatLng(c.latitude, c.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
          infoWindow: InfoWindow(
            title: c.category.toUpperCase(),
            snippet: '${c.priorityLevel} Priority • ${c.status}',
            onTap: () => _openComplaintDetails(c),
          ),
          onTap: () {
            setState(() {
              _selectedComplaint = c;
            });
          },
        ),
      );
    }

    _markers = markers;
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
    if (_userPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_userPosition!.latitude, _userPosition!.longitude),
          15.5,
        ),
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
        title: const Text('Civic Map'),
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
          // Google Map View
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: 14.5,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: (_) {
              if (_selectedComplaint != null) {
                setState(() => _selectedComplaint = null);
              }
            },
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
                      Text('Loading map markers...', style: TextStyle(fontSize: 12)),
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
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _openComplaintDetails(_selectedComplaint!),
                          child: const Text('View Details'),
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

