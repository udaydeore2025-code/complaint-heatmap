import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapLauncherService {
  /// Opens Google Maps with turn-by-turn navigation directly to the complaint hotspot.
  static Future<bool> navigateToCoordinates({
    required double latitude,
    required double longitude,
    String? title,
    BuildContext? context,
  }) async {
    bool launched = false;

    // 1. Try native Google Maps navigation URI scheme
    final nativeNavUri = Uri.parse('google.navigation:q=$latitude,$longitude&mode=d');
    try {
      if (await canLaunchUrl(nativeNavUri)) {
        launched = await launchUrl(nativeNavUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 2. Try standard geo intent scheme with label
    if (!launched) {
      final label = Uri.encodeComponent(title ?? 'Civic Hotspot');
      final geoUri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude($label)');
      try {
        if (await canLaunchUrl(geoUri)) {
          launched = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }

    // 3. Fallback to Google Maps Web Directions API
    if (!launched) {
      final webDirectionsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
      );
      try {
        if (await canLaunchUrl(webDirectionsUri)) {
          launched = await launchUrl(webDirectionsUri, mode: LaunchMode.externalApplication);
        } else {
          launched = await launchUrl(webDirectionsUri, mode: LaunchMode.platformDefault);
        }
      } catch (_) {}
    }

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch Google Maps. Please ensure Google Maps or a browser is installed.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }

    return launched;
  }

  /// Opens Google Maps centered on the hotspot location with a marker.
  static Future<bool> openInGoogleMaps({
    required double latitude,
    required double longitude,
    BuildContext? context,
  }) async {
    final searchUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    bool launched = false;
    try {
      if (await canLaunchUrl(searchUri)) {
        launched = await launchUrl(searchUri, mode: LaunchMode.externalApplication);
      } else {
        launched = await launchUrl(searchUri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {}

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Maps.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }

    return launched;
  }

  /// Opens OpenStreetMap centered on the hotspot coordinates.
  static Future<bool> openInOpenStreetMap({
    required double latitude,
    required double longitude,
    BuildContext? context,
  }) async {
    final osmUri = Uri.parse('https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=17/$latitude/$longitude');
    bool launched = false;
    try {
      if (await canLaunchUrl(osmUri)) {
        launched = await launchUrl(osmUri, mode: LaunchMode.externalApplication);
      } else {
        launched = await launchUrl(osmUri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {}

    if (!launched && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open OpenStreetMap in browser.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }

    return launched;
  }
}


