import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants/map_tile_styles.dart';
import '../core/services/map_launcher_service.dart';

class InteractiveOsmCard extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String title;
  final String? category;
  final String? priorityLevel;
  final double? geofenceRadiusMeters;
  final double height;
  final VoidCallback? onExpandFullMap;

  const InteractiveOsmCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.category,
    this.priorityLevel,
    this.geofenceRadiusMeters,
    this.height = 230,
    this.onExpandFullMap,
  });

  @override
  State<InteractiveOsmCard> createState() => _InteractiveOsmCardState();
}

class _InteractiveOsmCardState extends State<InteractiveOsmCard> {
  final MapController _mapController = MapController();
  MapTileStyle _currentStyle = MapTileStyle.standardOsm;

  Color _getMarkerColor() {
    switch (widget.priorityLevel?.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFDC2626);
      case 'HIGH':
        return const Color(0xFFEA580C);
      case 'MEDIUM':
        return const Color(0xFFD97706);
      case 'LOW':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFFDC2626);
    }
  }

  IconData _getCategoryIcon() {
    switch (widget.category?.toLowerCase()) {
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
        return Icons.location_on;
    }
  }

  void _cycleMapStyle() {
    setState(() {
      final idx = MapTileStyle.availableStyles.indexOf(_currentStyle);
      final nextIdx = (idx + 1) % MapTileStyle.availableStyles.length;
      _currentStyle = MapTileStyle.availableStyles[nextIdx];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Map Style: ${_currentStyle.name}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(widget.latitude, widget.longitude);
    final markerColor = _getMarkerColor();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map View Container
          SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: target,
                    initialZoom: 16.5,
                    maxZoom: 19,
                    minZoom: 10,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _currentStyle.urlTemplate,
                      userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                      maxZoom: 19,
                    ),
                    if (widget.geofenceRadiusMeters != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: target,
                            radius: widget.geofenceRadiusMeters!,
                            useRadiusInMeter: true,
                            color: markerColor.withValues(alpha: 0.2),
                            borderColor: markerColor,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: target,
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: markerColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              _getCategoryIcon(),
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Top Floating Badges
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app, size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          _currentStyle.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Interactive Map Action Buttons (Top Right)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Column(
                    children: [
                      // Style switcher button
                      _buildFloatingAction(
                        icon: Icons.layers_outlined,
                        tooltip: 'Switch Map Style (${_currentStyle.name})',
                        onTap: _cycleMapStyle,
                      ),
                      const SizedBox(height: 6),
                      // Recenter button
                      _buildFloatingAction(
                        icon: Icons.my_location,
                        tooltip: 'Center on Pin',
                        onTap: () => _mapController.move(target, 16.5),
                      ),
                      const SizedBox(height: 6),
                      // Zoom In
                      _buildFloatingAction(
                        icon: Icons.add,
                        tooltip: 'Zoom In',
                        onTap: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom + 1);
                        },
                      ),
                      const SizedBox(height: 6),
                      // Zoom Out
                      _buildFloatingAction(
                        icon: Icons.remove,
                        tooltip: 'Zoom Out',
                        onTap: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom - 1);
                        },
                      ),
                    ],
                  ),
                ),

                // Bottom Left: Open Fullscreen / Civic Map (if callback provided)
                if (widget.onExpandFullMap != null)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.open_in_full, size: 14),
                      label: const Text('Open in Civic Map'),
                      onPressed: widget.onExpandFullMap,
                    ),
                  ),

                // OpenStreetMap attribution
                Positioned(
                  bottom: 2,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '© OSM',
                      style: TextStyle(fontSize: 8, color: Color(0xFF475569)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action Toolbar below Map
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E40AF),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.navigation, size: 15),
                    label: const Text('Navigate (GPS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      MapLauncherService.navigateToCoordinates(
                        latitude: widget.latitude,
                        longitude: widget.longitude,
                        title: widget.title,
                        context: context,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.open_in_browser, size: 15),
                  label: const Text('OSM Web', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    MapLauncherService.openInOpenStreetMap(
                      latitude: widget.latitude,
                      longitude: widget.longitude,
                      context: context,
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Copy Coordinates',
                  icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF64748B)),
                  onPressed: () {
                    final coords = '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}';
                    Clipboard.setData(ClipboardData(text: coords));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied coordinates: $coords'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(7.0),
            child: Icon(icon, size: 18, color: const Color(0xFF1E293B)),
          ),
        ),
      ),
    );
  }
}

