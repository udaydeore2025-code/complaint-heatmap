class AppConstants {
  static const String appName = 'CivicConnect';
  static const String appTagline = 'Report. Verify. Resolve.';

  // Default nearby radius in meters (5 km)
  static const double defaultNearbyRadiusMeters = 5000.0;

  // Hotspot clustering radius in meters (50 m)
  static const double hotspotClusterRadiusMeters = 50.0;

  static const List<String> categories = [
    'Pothole',
    'Garbage',
    'Water Supply',
    'Drainage',
    'Streetlight',
    'Road Damage',
    'Public Area',
    'Other',
  ];
}

