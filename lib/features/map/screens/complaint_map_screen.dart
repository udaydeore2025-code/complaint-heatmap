import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/map_tile_styles.dart';
import '../../../core/models/complaint.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_launcher_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../complaints/screens/complaint_details_screen.dart';
import '../../complaints/screens/report_complaint_screen.dart';

class ComplaintMapScreen extends StatefulWidget {
  final ComplaintRepository? complaintRepository;
  final UserPosition? initialPosition;
  final Complaint? initialComplaint;

  const ComplaintMapScreen({
    super.key,
    this.complaintRepository,
    this.initialPosition,
    this.initialComplaint,
  });

  @override
  State<ComplaintMapScreen> createState() => _ComplaintMapScreenState();
}

class _ComplaintMapScreenState extends State<ComplaintMapScreen>
    with TickerProviderStateMixin {
  late final ComplaintRepository _complaintRepo;
  final MapController _mapController = MapController();

  List<Complaint> _allComplaints = [];
  Complaint? _selectedComplaint;
  LatLng? _droppedPin;
  bool _isLoading = true;

  // Filter states
  String _selectedCategory = 'ALL';
  String _selectedStatus = 'ALL'; // 'ALL', 'OPEN', 'SOLVED'
  double? _selectedRadiusKm; // null for All, or 1.0, 3.0, 5.0, 10.0

  MapTileStyle _activeMapStyle = MapTileStyle.standardOsm;
  UserPosition? _userPosition;

  static const LatLng _fallbackCenter = LatLng(18.5204, 73.8567);

  @override
  void initState() {
    super.initState();
    _complaintRepo = widget.complaintRepository ?? ComplaintRepository();
    _userPosition = widget.initialPosition;
    if (widget.initialComplaint != null) {
      _selectedComplaint = widget.initialComplaint;
    }
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    _userPosition ??= await LocationService.getCurrentLocation();
    await _loadComplaints();

    if (widget.initialComplaint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animatedMapMove(
          LatLng(widget.initialComplaint!.latitude, widget.initialComplaint!.longitude),
          16.5,
        );
      });
    }
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

  void _fitAllComplaints() {
    final visible = _filteredComplaints;
    if (visible.isEmpty) {
      _recenterOnUser();
      return;
    }

    if (visible.length == 1) {
      _animatedMapMove(LatLng(visible.first.latitude, visible.first.longitude), 16.0);
      return;
    }

    double minLat = visible.first.latitude;
    double maxLat = visible.first.latitude;
    double minLng = visible.first.longitude;
    double maxLng = visible.first.longitude;

    for (final c in visible) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Approximate zoom level based on bounding span
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

  void _recenterOnUser() {
    if (_userPosition != null) {
      _animatedMapMove(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        16.0,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current GPS position unavailable.')),
      );
    }
  }

  List<Complaint> get _filteredComplaints {
    return _allComplaints.where((c) {
      // 1. Category Filter
      if (_selectedCategory != 'ALL' &&
          c.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }

      // 2. Status Filter
      if (_selectedStatus == 'OPEN' && c.status == 'SOLVED') {
        return false;
      }
      if (_selectedStatus == 'SOLVED' && c.status != 'SOLVED') {
        return false;
      }

      // 3. Geofence / Radius Filter
      if (_selectedRadiusKm != null && _userPosition != null) {
        final distMeters = LocationService.calculateDistanceMeters(
          startLatitude: _userPosition!.latitude,
          startLongitude: _userPosition!.longitude,
          endLatitude: c.latitude,
          endLongitude: c.longitude,
        );
        if (distMeters / 1000.0 > _selectedRadiusKm!) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _handleQuickUpvote(Complaint complaint) async {
    try {
      await _complaintRepo.toggleVote(
        complaintId: complaint.id,
        voteType: 'UPVOTE',
      );

      final newCount = complaint.upvoteCount + 1;
      final updated = complaint.copyWith(
        upvoteCount: newCount,
        currentUserVote: 'UPVOTE',
      );

      setState(() {
        final idx = _allComplaints.indexWhere((item) => item.id == complaint.id);
        if (idx != -1) {
          _allComplaints[idx] = updated;
        }
        if (_selectedComplaint?.id == complaint.id) {
          _selectedComplaint = updated;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upvote recorded! Priority score updated.'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not register upvote: $e')),
      );
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
                  const Icon(Icons.layers, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'Interactive Map Styles',
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
                        ? AppTheme.primaryColor
                        : const Color(0xFFF1F5F9),
                    foregroundColor: isSelected ? Colors.white : const Color(0xFF475569),
                    child: Icon(style.icon, size: 20),
                  ),
                  title: Text(
                    style.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Text(style.description, style: const TextStyle(fontSize: 12)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppTheme.primaryColor)
                      : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.08),
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

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.initialComplaint != null
        ? LatLng(widget.initialComplaint!.latitude, widget.initialComplaint!.longitude)
        : (_userPosition != null
            ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
            : _fallbackCenter);

    final visibleComplaints = _filteredComplaints;

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
            tooltip: 'Switch Map Style',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _showLayerSelector,
          ),
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
              maxZoom: 19,
              minZoom: 9,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedComplaint = null;
                  _droppedPin = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _activeMapStyle.urlTemplate,
                userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                maxZoom: 19,
              ),

              // Interactive User Geofence / Radius circle
              if (_userPosition != null && _selectedRadiusKm != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                      radius: _selectedRadiusKm! * 1000.0,
                      useRadiusInMeter: true,
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderColor: const Color(0xFF2563EB),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // User Current Position Marker
              if (_userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              // Interactive Dropped Pin Marker
              if (_droppedPin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _droppedPin!,
                      width: 50,
                      height: 50,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, color: Color(0xFF7C3AED), size: 36),
                          CircleAvatar(backgroundColor: Color(0xFF7C3AED), radius: 3),
                        ],
                      ),
                    ),
                  ],
                ),

              // Complaint Markers Layer
              MarkerLayer(
                markers: visibleComplaints.map((c) {
                  final color = _getMarkerColor(c);
                  final isSelected = _selectedComplaint?.id == c.id;

                  return Marker(
                    point: LatLng(c.latitude, c.longitude),
                    width: isSelected ? 52 : 40,
                    height: isSelected ? 52 : 40,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedComplaint = c;
                          _droppedPin = null;
                        });
                        _animatedMapMove(LatLng(c.latitude, c.longitude), 16.5);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFFFDE047) : Colors.white,
                            width: isSelected ? 3.5 : 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? color.withValues(alpha: 0.6)
                                  : Colors.black38,
                              blurRadius: isSelected ? 10 : 4,
                              spreadRadius: isSelected ? 2 : 0,
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
              child: Text(
                '© ${_activeMapStyle.name}',
                style: const TextStyle(fontSize: 9, color: Color(0xFF475569)),
              ),
            ),
          ),

          // Top Control Overlay: Category & Radius Filters
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category Pills Row
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: AppConstants.categories.length + 1,
                    separatorBuilder: (context, index) => const SizedBox(width: 6),
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
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

                const SizedBox(height: 6),

                // Radius Geofence Pills Row
                SizedBox(
                  height: 32,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildRadiusPill(null, 'All City'),
                      const SizedBox(width: 6),
                      _buildRadiusPill(1.0, '1 km'),
                      const SizedBox(width: 6),
                      _buildRadiusPill(3.0, '3 km'),
                      const SizedBox(width: 6),
                      _buildRadiusPill(5.0, '5 km'),
                      const SizedBox(width: 6),
                      _buildRadiusPill(10.0, '10 km'),
                      const SizedBox(width: 10),
                      // Status toggle chip
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_selectedStatus == 'ALL') {
                              _selectedStatus = 'OPEN';
                            } else if (_selectedStatus == 'OPEN') {
                              _selectedStatus = 'SOLVED';
                            } else {
                              _selectedStatus = 'ALL';
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _selectedStatus == 'SOLVED'
                                    ? Icons.check_circle
                                    : Icons.filter_alt_outlined,
                                size: 14,
                                color: _selectedStatus == 'SOLVED'
                                    ? const Color(0xFF16A34A)
                                    : AppTheme.primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Status: $_selectedStatus',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Positioned(
              top: 96,
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

          // Count chip when radius is active
          if (_selectedRadiusKm != null)
            Positioned(
              top: 96,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${visibleComplaints.length} issues within ${_selectedRadiusKm!.toInt()} km',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // Floating Map Action Buttons (Right Side)
          Positioned(
            bottom: _selectedComplaint != null || _droppedPin != null ? 220 : 20,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapActionButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'Change Map Style',
                  onTap: _showLayerSelector,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.crop_free,
                  tooltip: 'Fit All Complaints',
                  onTap: _fitAllComplaints,
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.add,
                  tooltip: 'Zoom In',
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, zoom + 1);
                  },
                ),
                const SizedBox(height: 8),
                _buildMapActionButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom Out',
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, zoom - 1);
                  },
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter_gps',
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  onPressed: _recenterOnUser,
                  child: const Icon(Icons.my_location, size: 20),
                ),
              ],
            ),
          ),

          // Dropped Pin / Location Inspector Card
          if (_droppedPin != null && _selectedComplaint == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFF7C3AED), size: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'Selected Location',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _droppedPin = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Lat: ${_droppedPin!.latitude.toStringAsFixed(6)} • Long: ${_droppedPin!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                            label: const Text(
                              'Report Issue Here',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              final point = _droppedPin!;
                              setState(() => _droppedPin = null);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => ReportComplaintScreen(
                                    complaintRepository: _complaintRepo,
                                    initialLatitude: point.latitude,
                                    initialLongitude: point.longitude,
                                  ),
                                ),
                              ).then((_) => _loadComplaints());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.copy, size: 15),
                          label: const Text('Copy', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                              text: '${_droppedPin!.latitude}, ${_droppedPin!.longitude}',
                            ));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Coordinates copied to clipboard!'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Selected Complaint Bottom Preview Card
          if (_selectedComplaint != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Badges & Close Button
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getCategoryIcon(_selectedComplaint!.category),
                                size: 14,
                                color: AppTheme.primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _selectedComplaint!.category.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getMarkerColor(_selectedComplaint!).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_selectedComplaint!.priorityLevel} PRIORITY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _getMarkerColor(_selectedComplaint!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedComplaint!.status == 'SOLVED'
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedComplaint!.status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
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
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: () {
                            setState(() => _selectedComplaint = null);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Content Row: Description and Optional Photo Thumbnail
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
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (_selectedComplaint!.userName != null) ...[
                                    const Icon(Icons.person_outline, size: 13, color: Color(0xFF64748B)),
                                    const SizedBox(width: 3),
                                    Text(
                                      _selectedComplaint!.userName!,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  if (_selectedComplaint!.distanceMeters != null) ...[
                                    const Icon(Icons.near_me_outlined, size: 13, color: AppTheme.primaryColor),
                                    const SizedBox(width: 2),
                                    Text(
                                      LocationService.formatDistance(_selectedComplaint!.distanceMeters!),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_selectedComplaint!.imageUrl != null &&
                            _selectedComplaint!.imageUrl!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showImagePreviewDialog(
                              _selectedComplaint!.imageUrl!,
                              _selectedComplaint!.category,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Image.network(
                                    _selectedComplaint!.imageUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 60,
                                      height: 60,
                                      color: const Color(0xFFF1F5F9),
                                      child: const Icon(Icons.image, size: 24, color: Colors.grey),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.only(topLeft: Radius.circular(4)),
                                    ),
                                    child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Actions Row: Live Upvote, GPS Navigation, Details
                    Row(
                      children: [
                        // Live Upvote Button
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _handleQuickUpvote(_selectedComplaint!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedComplaint!.currentUserVote == 'UPVOTE'
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedComplaint!.currentUserVote == 'UPVOTE'
                                    ? AppTheme.primaryColor
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedComplaint!.currentUserVote == 'UPVOTE'
                                      ? Icons.thumb_up
                                      : Icons.thumb_up_alt_outlined,
                                  size: 14,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${_selectedComplaint!.upvoteCount}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Confirmation count badge
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF0F766E)),
                            const SizedBox(width: 4),
                            Text(
                              '${_selectedComplaint!.confirmationCount}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // GPS Navigation Button
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E40AF),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        // Details Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildRadiusPill(double? radiusKm, String label) {
    final isSelected = _selectedRadiusKm == radiusKm;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedRadiusKm = radiusKm);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildMapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, size: 20, color: const Color(0xFF1E293B)),
          ),
        ),
      ),
    );
  }
}
