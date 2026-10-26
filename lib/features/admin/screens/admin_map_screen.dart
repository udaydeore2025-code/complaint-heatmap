
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/map_tile_styles.dart';
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

class _AdminMapScreenState extends State<AdminMapScreen>
    with TickerProviderStateMixin {
  late final AdminRepository _adminRepo;
  final MapController _mapController = MapController();

  List<Complaint> _complaints = [];
  List<LocationGroup> _groups = [];

  bool _isLoading = true;
  bool _isListView = false;
  String _activeFilter = 'ALL'; // 'ALL', 'HOTSPOTS', 'CRITICAL'
  String _selectedCategory = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  MapTileStyle _activeMapStyle = MapTileStyle.standardOsm;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          _animatedMapMove(
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

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    final animation = CurvedAnimation(
      parent: animationController,
      curve: Curves.fastOutSlowIn,
    );

    animationController.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        animationController.dispose();
      }
    });

    animationController.forward();
  }

  void _fitAllHotspots() {
    final visible = _filteredComplaints;
    if (visible.isEmpty && _groups.isEmpty) {
      _animatedMapMove(_defaultCenter, 14.0);
      return;
    }

    final points = <LatLng>[];
    for (final c in visible) {
      points.add(LatLng(c.latitude, c.longitude));
    }
    for (final g in _groups) {
      points.add(LatLng(g.centerLatitude, g.centerLongitude));
    }

    if (points.length == 1) {
      _animatedMapMove(points.first, 16.0);
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = max(latDiff, lngDiff);

    double zoom = 14.0;
    if (maxDiff > 0.5) {
      zoom = 10.0;
    } else if (maxDiff > 0.2) {
      zoom = 11.5;
    } else if (maxDiff > 0.1) {
      zoom = 12.8;
    } else if (maxDiff > 0.05) {
      zoom = 14.0;
    } else if (maxDiff > 0.02) {
      zoom = 15.0;
    } else {
      zoom = 16.0;
    }

    _animatedMapMove(LatLng(centerLat, centerLng), zoom);
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

  void _showImagePreviewDialog(String imageUrl, String category) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(32),
                    color: Colors.white,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Photo could not be loaded.'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 16,
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showLayerSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers, color: Color(0xFF0F172A)),
                  const SizedBox(width: 8),
                  const Text(
                    'Admin Map Base Layers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...MapTileStyle.availableStyles.map((style) {
                final isSelected = style.id == _activeMapStyle.id;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    foregroundColor: isSelected ? Colors.white : const Color(0xFF475569),
                    child: Icon(style.icon, size: 20),
                  ),
                  title: Text(
                    style.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Text(style.description, style: const TextStyle(fontSize: 12)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF0F172A))
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  selected: isSelected,
                  selectedTileColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  onTap: () {
                    setState(() => _activeMapStyle = style);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showClusterComplaintsSheet(LocationGroup group) {
    final clusterComplaints = _complaints.where((c) => c.locationGroupId == group.id).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department, color: _getHotspotColor(group.hotspotLevel), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${group.hotspotLevel.toUpperCase()} CLUSTER',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _getHotspotColor(group.hotspotLevel),
                          ),
                        ),
                        Text(
                          '${clusterComplaints.length} issues grouped in this 50m radius',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (clusterComplaints.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No active complaints inside this cluster.')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: clusterComplaints.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final c = clusterComplaints[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: _getMarkerColor(c).withValues(alpha: 0.15),
                              child: Icon(_getCategoryIcon(c.category), color: _getMarkerColor(c), size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c.category} • Score ${c.priorityScore.toStringAsFixed(1)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    c.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openDetails(c);
                              },
                              child: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleQuickAdminStatusUpdate(Complaint complaint, String newStatus) async {
    try {
      await _adminRepo.updateComplaintStatus(
        complaintId: complaint.id,
        oldStatus: complaint.status,
        newStatus: newStatus,
        comment: 'Status updated from Admin Hotspot Map',
      );

      final updated = complaint.copyWith(status: newStatus);

      setState(() {
        final idx = _complaints.indexWhere((item) => item.id == complaint.id);
        if (idx != -1) {
          _complaints[idx] = updated;
        }
        if (_selectedComplaint?.id == complaint.id) {
          _selectedComplaint = updated;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Complaint status marked as $newStatus!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  List<Complaint> get _filteredComplaints {
    return _complaints.where((c) {
      // 1. Hotspot & Priority filter
      if (_activeFilter == 'HOTSPOTS' && c.locationGroupId == null) {
        return false;
      } else if (_activeFilter == 'CRITICAL' &&
          c.priorityLevel != 'CRITICAL' &&
          c.priorityLevel != 'HIGH') {
        return false;
      }

      // 2. Category filter
      if (_selectedCategory != 'ALL' &&
          c.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }

      // 3. Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchDesc = c.description.toLowerCase().contains(q);
        final matchCat = c.category.toLowerCase().contains(q);
        final matchId = c.formattedComplaintId.toLowerCase().contains(q);
        final matchUser = (c.userName ?? '').toLowerCase().contains(q);
        if (!matchDesc && !matchCat && !matchId && !matchUser) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = widget.initialComplaint != null
        ? LatLng(widget.initialComplaint!.latitude, widget.initialComplaint!.longitude)
        : (_complaints.isNotEmpty
            ? LatLng(_complaints.first.latitude, _complaints.first.longitude)
            : _defaultCenter);
    final double initialZoom = widget.initialComplaint != null ? 16.5 : 14.0;

    final filteredComplaints = _filteredComplaints;

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
            tooltip: 'Switch Map Style',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _showLayerSelector,
          ),
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
                    maxZoom: 19,
                    minZoom: 9,
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
                      urlTemplate: _activeMapStyle.urlTemplate,
                      userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                      maxZoom: 19,
                    ),
                    CircleLayer(
                      circles: _groups.map((g) {
                        final color = _getHotspotColor(g.hotspotLevel);
                        final isSelected = _selectedGroup?.id == g.id;
                        return CircleMarker(
                          point: LatLng(g.centerLatitude, g.centerLongitude),
                          radius: 65.0,
                          useRadiusInMeter: true,
                          color: color.withValues(alpha: isSelected ? 0.35 : 0.22),
                          borderColor: color,
                          borderStrokeWidth: isSelected ? 3.5 : 2.5,
                        );
                      }).toList(),
                    ),
                    MarkerLayer(
                      markers: [
                        // Cluster Center Markers with Complaint Count
                        ..._groups.map((g) {
                          final color = _getHotspotColor(g.hotspotLevel);
                          final isSelected = _selectedGroup?.id == g.id;
                          return Marker(
                            point: LatLng(g.centerLatitude, g.centerLongitude),
                            width: isSelected ? 46 : 38,
                            height: isSelected ? 46 : 38,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedGroup = g;
                                  _selectedComplaint = null;
                                });
                                _animatedMapMove(LatLng(g.centerLatitude, g.centerLongitude), 16.5);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFFDE047) : Colors.white,
                                    width: isSelected ? 3.5 : 2.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${g.complaintCount}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSelected ? 15 : 13,
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
                            width: isSelected ? 50 : 40,
                            height: isSelected ? 50 : 40,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedComplaint = c;
                                  _selectedGroup = null;
                                });
                                _animatedMapMove(LatLng(c.latitude, c.longitude), 16.5);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFFDE047) : Colors.white,
                                    width: isSelected ? 3.5 : 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected ? color.withValues(alpha: 0.6) : Colors.black38,
                                      blurRadius: isSelected ? 8 : 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getCategoryIcon(c.category),
                                  color: Colors.white,
                                  size: isSelected ? 24 : 18,
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
                    child: Text(
                      '© ${_activeMapStyle.name}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF475569)),
                    ),
                  ),
                ),

                // Zoom, Fit All & Recenter Controls
                Positioned(
                  right: 14,
                  bottom: _selectedGroup != null || _selectedComplaint != null ? 240 : 90,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'osm_layers',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        tooltip: 'Map Base Layers',
                        onPressed: _showLayerSelector,
                        child: const Icon(Icons.layers_outlined, size: 20),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'osm_fit_all',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        tooltip: 'Fit All Hotspots',
                        onPressed: _fitAllHotspots,
                        child: const Icon(Icons.crop_free, size: 20),
                      ),
                      const SizedBox(height: 8),
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
                        onPressed: () => _animatedMapMove(center, initialZoom),
                        child: const Icon(Icons.my_location, size: 18),
                      ),
                    ],
                  ),
                ),

                // Top Controls: Search Bar & Filter toggles
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search field
                      Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search complaints by keyword, ID, or category...',
                            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (val) {
                            setState(() => _searchQuery = val.trim());
                          },
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Category Pills Row
                      SizedBox(
                        height: 30,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: AppConstants.categories.length + 1,
                          separatorBuilder: (context, index) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final cat = index == 0 ? 'ALL' : AppConstants.categories[index - 1];
                            final isSelected = _selectedCategory == cat;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = cat;
                                  _selectedGroup = null;
                                  _selectedComplaint = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                                  ],
                                ),
                                child: Text(
                                  cat.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Filter Pills Row
                      Row(
                        children: [
                          _buildFilterPill('ALL', 'All Complaints'),
                          const SizedBox(width: 8),
                          _buildFilterPill('HOTSPOTS', 'Hotspot Zones'),
                          const SizedBox(width: 8),
                          _buildFilterPill('CRITICAL', 'High/Critical'),
                        ],
                      ),
                    ],
                  ),
                ),

                // Loading overlay
                if (_isLoading)
                  const Positioned(
                    top: 110,
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
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F172A),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.list, size: 14),
                                  label: const Text('Issues', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _showClusterComplaintsSheet(_selectedGroup!),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Selected Complaint Information Card with Quick Admin Actions
                if (_selectedComplaint != null)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 20,
                    child: Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
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
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _getMarkerColor(_selectedComplaint!).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_selectedComplaint!.priorityLevel} (${_selectedComplaint!.priorityScore.toStringAsFixed(1)})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: _getMarkerColor(_selectedComplaint!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _selectedComplaint!.status == 'SOLVED'
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _selectedComplaint!.status,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      color: _selectedComplaint!.status == 'SOLVED'
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF475569),
                                    ),
                                  ),
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

                            // Description and optional thumbnail
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedComplaint!.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: ${_selectedComplaint!.formattedComplaintId} • ${_selectedComplaint!.userName ?? 'Citizen'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_selectedComplaint!.imageUrl != null &&
                                    _selectedComplaint!.imageUrl!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _showImagePreviewDialog(
                                      _selectedComplaint!.imageUrl!,
                                      _selectedComplaint!.category,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _selectedComplaint!.imageUrl!,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          width: 52,
                                          height: 52,
                                          color: const Color(0xFFF1F5F9),
                                          child: const Icon(Icons.image, size: 20, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Direct Administrative Action Quick Buttons
                            if (_selectedComplaint!.status != 'SOLVED') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Text('Quick Action: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                    if (_selectedComplaint!.status == 'PENDING') ...[
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF16A34A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        icon: const Icon(Icons.check, size: 12),
                                        label: const Text('Verify'),
                                        onPressed: () => _handleQuickAdminStatusUpdate(_selectedComplaint!, 'VERIFIED'),
                                      ),
                                    ] else if (_selectedComplaint!.status == 'VERIFIED') ...[
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2563EB),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        icon: const Icon(Icons.build, size: 12),
                                        label: const Text('Start Work'),
                                        onPressed: () => _handleQuickAdminStatusUpdate(_selectedComplaint!, 'WORK IN PROGRESS'),
                                      ),
                                    ] else if (_selectedComplaint!.status == 'WORK IN PROGRESS') ...[
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF059669),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        icon: const Icon(Icons.done_all, size: 12),
                                        label: const Text('Mark Solved'),
                                        onPressed: () => _handleQuickAdminStatusUpdate(_selectedComplaint!, 'SOLVED'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            // Navigation & Review Buttons
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
