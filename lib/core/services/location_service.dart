import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class UserPosition {
  final double latitude;
  final double longitude;

  const UserPosition({required this.latitude, required this.longitude});
}

class LocationService {
  /// Checks and requests location permission, returning current user coordinates.
  /// Does NOT perform continuous tracking — one-shot fetch only.
  static Future<UserPosition?> getCurrentLocation() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        debugPrint('Location services are disabled on device.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied by user.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return UserPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      debugPrint('Failed to get current location: $e');
      return null;
    }
  }

  /// Calculates geodesic distance in meters between two coordinates.
  static double calculateDistanceMeters({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Formats distance into friendly text (e.g., "180 m away" or "1.4 km away").
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m away';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km away';
    }
  }
}

