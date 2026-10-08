import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/location_group.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_complaint_details_screen.dart';

class AdminMapScreen extends StatefulWidget {
  final AdminRepository? adminRepository;

  const AdminMapScreen({super.key, this.adminRepository});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  late final AdminRepository _adminRepo;
  GoogleMapController? _mapController;

  List<Complaint> _complaints = [];
  List<LocationGroup> _groups = [];
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  bool _isLoading = true;
  String _activeFilter = 'ALL'; // 'ALL', 'HOTSPOTS', 'CRITICAL'
  LocationGroup? _selectedGroup;
  Complaint? _selectedComplaint;

  static const LatLng _defaultCenter = LatLng(18.5204, 73.8567);

  @override
  void initState() {
    super.initState();
    _adminRepo = widget.adminRepository ?? AdminRepository();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    setState(() => _isLoading = true);
    try {
      final queue = await _adminRepo.fetchPriorityQueue();
      final groups = await _adminRepo.fetchLocationGroups();

      if (!mounted) return;
      setState(() {
        _complaints = queue;
        _groups = groups;
        _rebuildMapOverlays();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load admin map: $e')),
      );
    }
  }

  Color _getHotspotColor(String level) {
    switch (level) {
      case 'Hotspot':
        return const Color(0xFFDC2626);
      case 'High Activity Zone':
        return const Color(0xFFEA580C);
      case 'Complaint Zone':
        return const Color(0xFFEAB308);
      default:
        return const Color(0xFF2563EB);
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

  void _rebuildMapOverlays() {
    final markers = <Marker>{};
    final circles = <Circle>{};

    // 1. Build Hotspot Circles
    for (final g in _groups) {
      final color = _getHotspotColor(g.hotspotLevel);
      circles.add(
        Circle(
          circleId: CircleId(g.id),
          center: LatLng(g.centerLatitude, g.centerLongitude),
          radius: 75.0, // 75 meters visual radius for 50m cluster
          fillColor: color.withValues(alpha: 0.22),
          strokeColor: color,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () {
            setState(() {
              _selectedGroup = g;
              _selectedComplaint = null;
            });
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(g.centerLatitude, g.centerLongitude),
                16.0,
              ),
            );
          },
        ),
      );
    }

    // 2. Filter complaints based on active filter
    final filteredComplaints = _complaints.where((c) {
      if (_activeFilter == 'HOTSPOTS') {
        return c.locationGroupId != null;
      } else if (_activeFilter == 'CRITICAL') {
        return c.priorityLevel == 'CRITICAL' || c.priorityLevel == 'HIGH';
      }
      return true;
    }).toList();

    // 3. Build Complaint Markers
    for (final c in filteredComplaints) {
      final hue = _getMarkerHue(c);
      markers.add(
        Marker(
          markerId: MarkerId(c.id),
          position: LatLng(c.latitude, c.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: '${c.category.toUpperCase()} (${c.priorityLevel})',
            snippet: 'Score: ${c.priorityScore.toStringAsFixed(1)} • ${c.status}',
            onTap: () => _openDetails(c),
          ),
          onTap: () {
            setState(() {
              _selectedComplaint = c;
              _selectedGroup = null;
            });
          },
        ),
      );
    }

    _markers = markers;
    _circles = circles;
  }

  void _openDetails(Complaint c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AdminComplaintDetailsScreen(
          complaint: c,
          adminRepository: _adminRepo,
        ),
      ),
    ).then((_) => _loadMapData());
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = _complaints.isNotEmpty
        ? LatLng(_complaints.first.latitude, _complaints.first.longitude)
        : _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Hotspot Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Cluster Detection & Realtime Geography', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMapData,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14.0),
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (ctrl) => _mapController = ctrl,
            onTap: (_) {
              if (_selectedGroup != null || _selectedComplaint != null) {
                setState(() {
                  _selectedGroup = null;
                  _selectedComplaint = null;
                });
              }
            },
          ),

          // Loading overlay
          if (_isLoading)
            const Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Analyzing clusters & rendering...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Filter toggles
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _buildFilterPill('ALL', 'All Complaints'),
                const SizedBox(width: 8),
                _buildFilterPill('HOTSPOTS', 'Hotspot Zones'),
                const SizedBox(width: 8),
                _buildFilterPill('CRITICAL', 'High/Critical'),
              ],
            ),
          ),

          // Hotspot Cluster Information Card
          if (_selectedGroup != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            color: _getHotspotColor(_selectedGroup!.hotspotLevel),
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedGroup!.hotspotLevel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _getHotspotColor(_selectedGroup!.hotspotLevel),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _selectedGroup = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Complaints in Cluster: ${_selectedGroup!.complaintCount}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cluster Radius: 50m • Center: ${_selectedGroup!.centerLatitude.toStringAsFixed(4)}, ${_selectedGroup!.centerLongitude.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Selected Complaint Information Card
          if (_selectedComplaint != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                          Text(
                            'Score: ${_selectedComplaint!.priorityScore.toStringAsFixed(1)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          const Spacer(),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _selectedComplaint = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedComplaint!.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Status: ${_selectedComplaint!.status}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            ),
                            onPressed: () => _openDetails(_selectedComplaint!),
                            child: const Text('Admin Review', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String filterKey, String label) {
    final isSelected = _activeFilter == filterKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = filterKey;
            _selectedGroup = null;
            _selectedComplaint = null;
            _rebuildMapOverlays();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

