import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/complaint.dart';
import '../../../core/models/location_group.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/services/map_launcher_service.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_complaint_details_screen.dart';

class AdminMapScreen extends StatefulWidget {
  final AdminRepository? adminRepository;
  final Complaint? initialComplaint;

  const AdminMapScreen({
    super.key,
    this.adminRepository,
    this.initialComplaint,
  });

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  late final AdminRepository _adminRepo;
  final MapController _mapController = MapController();

  List<Complaint> _complaints = [];
  List<LocationGroup> _groups = [];

  bool _isLoading = true;
  bool _isListView = false;
  String _activeFilter = 'ALL'; // 'ALL', 'HOTSPOTS', 'CRITICAL'
  LocationGroup? _selectedGroup;
  Complaint? _selectedComplaint;

  static const LatLng _defaultCenter = LatLng(18.5204, 73.8567);

  @override
  void initState() {
    super.initState();
    _adminRepo = widget.adminRepository ?? AdminRepository();
    if (widget.initialComplaint != null) {
      _selectedComplaint = widget.initialComplaint;
    }
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
        _isLoading = false;
      });

      if (widget.initialComplaint != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(
            LatLng(widget.initialComplaint!.latitude, widget.initialComplaint!.longitude),
            16.5,
          );
        });
      }
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
    final LatLng center = widget.initialComplaint != null
        ? LatLng(widget.initialComplaint!.latitude, widget.initialComplaint!.longitude)
        : (_complaints.isNotEmpty
            ? LatLng(_complaints.first.latitude, _complaints.first.longitude)
            : _defaultCenter);
    final double initialZoom = widget.initialComplaint != null ? 16.5 : 14.0;

    final filteredComplaints = _complaints.where((c) {
      if (_activeFilter == 'HOTSPOTS') {
        return c.locationGroupId != null;
      } else if (_activeFilter == 'CRITICAL') {
        return c.priorityLevel == 'CRITICAL' || c.priorityLevel == 'HIGH';
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Hotspot Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('OpenStreetMap • Realtime Hotspot Clusters', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _isListView ? 'Show Map View' : 'Show Hotspot List',
            icon: Icon(_isListView ? Icons.map_outlined : Icons.format_list_bulleted),
            onPressed: () {
              setState(() => _isListView = !_isListView);
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMapData,
          ),
        ],
      ),
      body: _isListView
          ? _buildListView(filteredComplaints)
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: initialZoom,
                    onTap: (tapPosition, point) {
                      if (_selectedGroup != null || _selectedComplaint != null) {
                        setState(() {
                          _selectedGroup = null;
                          _selectedComplaint = null;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                      maxZoom: 19,
                    ),
                    CircleLayer(
                      circles: _groups.map((g) {
                        final color = _getHotspotColor(g.hotspotLevel);
                        return CircleMarker(
                          point: LatLng(g.centerLatitude, g.centerLongitude),
                          radius: 65.0,
                          useRadiusInMeter: true,
                          color: color.withValues(alpha: 0.22),
                          borderColor: color,
                          borderStrokeWidth: 2.5,
                        );
                      }).toList(),
                    ),
                    MarkerLayer(
                      markers: [
                        // Cluster Center Markers with Complaint Count
                        ..._groups.map((g) {
                          final color = _getHotspotColor(g.hotspotLevel);
                          return Marker(
                            point: LatLng(g.centerLatitude, g.centerLongitude),
                            width: 38,
                            height: 38,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedGroup = g;
                                  _selectedComplaint = null;
                                });
                                _mapController.move(LatLng(g.centerLatitude, g.centerLongitude), 16.0);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${g.complaintCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        // Individual Complaint Markers
                        ...filteredComplaints.map((c) {
                          final color = _getMarkerColor(c);
                          final isSelected = _selectedComplaint?.id == c.id;
                          return Marker(
                            point: LatLng(c.latitude, c.longitude),
                            width: isSelected ? 48 : 40,
                            height: isSelected ? 48 : 40,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedComplaint = c;
                                  _selectedGroup = null;
                                });
                                _mapController.move(LatLng(c.latitude, c.longitude), 16.5);
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
                        }),
                      ],
                    ),
                  ],
                ),

                // OpenStreetMap Attribution chip
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

                // Zoom & Recenter Controls
                Positioned(
                  right: 14,
                  bottom: 90,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'osm_zoom_in',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom + 1);
                        },
                        child: const Icon(Icons.add, size: 20),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'osm_zoom_out',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom - 1);
                        },
                        child: const Icon(Icons.remove, size: 20),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'osm_recenter',
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        elevation: 3,
                        onPressed: () => _mapController.move(center, initialZoom),
                        child: const Icon(Icons.my_location, size: 18),
                      ),
                    ],
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

                // Loading overlay
                if (_isLoading)
                  const Positioned(
                    top: 60,
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
                              Text('Rendering OpenStreetMap clusters...', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
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
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFDC2626),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.navigation, size: 14),
                                    label: const Text('GPS Navigation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      MapLauncherService.navigateToCoordinates(
                                        latitude: _selectedGroup!.centerLatitude,
                                        longitude: _selectedGroup!.centerLongitude,
                                        title: '${_selectedGroup!.hotspotLevel} Cluster',
                                        context: context,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F172A),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.open_in_browser, size: 14),
                                  label: const Text('OpenStreetMap', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    MapLauncherService.openInOpenStreetMap(
                                      latitude: _selectedGroup!.centerLatitude,
                                      longitude: _selectedGroup!.centerLongitude,
                                      context: context,
                                    );
                                  },
                                ),
                              ],
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
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.navigation, size: 14),
                                    label: const Text('GPS Navigate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      MapLauncherService.navigateToCoordinates(
                                        latitude: _selectedComplaint!.latitude,
                                        longitude: _selectedComplaint!.longitude,
                                        title: '${_selectedComplaint!.category} Hotspot',
                                        context: context,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F172A),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.open_in_browser, size: 14),
                                  label: const Text('OSM Web', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    MapLauncherService.openInOpenStreetMap(
                                      latitude: _selectedComplaint!.latitude,
                                      longitude: _selectedComplaint!.longitude,
                                      context: context,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _openDetails(_selectedComplaint!),
                                  child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Persistent Summary Bar when no pin is actively selected
                if (_selectedGroup == null && _selectedComplaint == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.near_me, color: Color(0xFF1E40AF), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${filteredComplaints.length} Hotspots In Queue',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const Text(
                                    'Tap any pin/cluster, or switch to list',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.format_list_bulleted, size: 14),
                              label: const Text('List', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => setState(() => _isListView = true),
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

  Widget _buildListView(List<Complaint> complaints) {
    if (complaints.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
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
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No complaints match this filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.near_me, size: 16, color: Color(0xFF1E40AF)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${complaints.length} Hotspots ready for Turn-by-Turn GPS Navigation',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: complaints.length,
            itemBuilder: (ctx, index) {
              final c = complaints[index];
              final isHotspot = c.locationGroupId != null;
              final Color priorityColor;
              switch (c.priorityLevel.toUpperCase()) {
                case 'CRITICAL':
                  priorityColor = const Color(0xFFDC2626);
                  break;
                case 'HIGH':
                  priorityColor = const Color(0xFFEA580C);
                  break;
                case 'MEDIUM':
                  priorityColor = const Color(0xFFD97706);
                  break;
                default:
                  priorityColor = const Color(0xFF2563EB);
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: priorityColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.priorityLevel.toUpperCase(),
                              style: TextStyle(color: priorityColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.category.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                            ),
                          ),
                          if (isHotspot) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.local_fire_department, size: 12, color: Color(0xFFDC2626)),
                                  SizedBox(width: 2),
                                  Text(
                                    'HOTSPOT',
                                    style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            'Score: ${c.priorityScore.toStringAsFixed(1)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            c.userName ?? 'Citizen',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.pin_drop_outlined, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.navigation, size: 15),
                              label: const Text(
                                'Navigate (GPS)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                MapLauncherService.navigateToCoordinates(
                                  latitude: c.latitude,
                                  longitude: c.longitude,
                                  title: '${c.category} Hotspot',
                                  context: context,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.open_in_browser, size: 14),
                            label: const Text('OSM Web', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              MapLauncherService.openInOpenStreetMap(
                                latitude: c.latitude,
                                longitude: c.longitude,
                                context: context,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F172A),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 15),
                            label: const Text('Review', style: TextStyle(fontSize: 12)),
                            onPressed: () => _openDetails(c),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
