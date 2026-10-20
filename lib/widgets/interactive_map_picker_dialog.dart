import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants/map_tile_styles.dart';
import '../core/services/location_service.dart';
import '../core/theme/app_theme.dart';

class InteractiveMapPickerDialog extends StatefulWidget {
  final LatLng? initialCenter;

  const InteractiveMapPickerDialog({
    super.key,
    this.initialCenter,
  });

  @override
  State<InteractiveMapPickerDialog> createState() => _InteractiveMapPickerDialogState();
}

class _InteractiveMapPickerDialogState extends State<InteractiveMapPickerDialog> {
  final MapController _mapController = MapController();
  late LatLng _currentCenter;
  MapTileStyle _currentStyle = MapTileStyle.standardOsm;
  bool _isLocating = false;

  static const LatLng _defaultFallback = LatLng(18.5204, 73.8567);

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialCenter ?? _defaultFallback;
  }

  Future<void> _recenterToCurrentGps() async {
    setState(() => _isLocating = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null && mounted) {
        final newCenter = LatLng(pos.latitude, pos.longitude);
        setState(() => _currentCenter = newCenter);
        _mapController.move(newCenter, 17.0);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLocating = false);
    }
  }

  void _cycleMapStyle() {
    setState(() {
      final idx = MapTileStyle.availableStyles.indexOf(_currentStyle);
      final nextIdx = (idx + 1) % MapTileStyle.availableStyles.length;
      _currentStyle = MapTileStyle.availableStyles[nextIdx];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pinpoint Issue Location', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Drag map to place the pin precisely on the problem', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch Map Style',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _cycleMapStyle,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Interactive OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 16.5,
              maxZoom: 19,
              minZoom: 10,
              onPositionChanged: (camera, hasGesture) {
                setState(() {
                  _currentCenter = camera.center;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _currentStyle.urlTemplate,
                userAgentPackageName: 'com.civicconnect.complaint_heatmap',
                maxZoom: 19,
              ),
            ],
          ),

          // Stationary Center Crosshair / Pin (Uber-style)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating Controls (Zoom & Recenter)
          Positioned(
            right: 14,
            bottom: 150,
            child: Column(
              children: [
                _buildFloatingButton(
                  icon: Icons.add,
                  tooltip: 'Zoom In',
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, zoom + 1);
                  },
                ),
                const SizedBox(height: 8),
                _buildFloatingButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom Out',
                  onTap: () {
                    final zoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, zoom - 1);
                  },
                ),
                const SizedBox(height: 8),
                _buildFloatingButton(
                  icon: _isLocating ? Icons.hourglass_top : Icons.my_location,
                  tooltip: 'Current GPS',
                  onTap: _recenterToCurrentGps,
                ),
              ],
            ),
          ),

          // Style Indicator Badge
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    _currentStyle.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Confirmation Card
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
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pin_drop, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Coordinates',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${_currentCenter.latitude.toStringAsFixed(6)}, ${_currentCenter.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text(
                      'CONFIRM THIS LOCATION',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () {
                      Navigator.pop(context, _currentCenter);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButton({
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
            padding: const EdgeInsets.all(10.0),
            child: Icon(icon, size: 20, color: const Color(0xFF0F172A)),
          ),
        ),
      ),
    );
  }
}

