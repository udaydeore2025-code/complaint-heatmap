class LocationGroup {
  final String id;
  final double centerLatitude;
  final double centerLongitude;
  final int complaintCount;
  final String hotspotLevel;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocationGroup({
    required this.id,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.complaintCount,
    required this.hotspotLevel,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationGroup.fromJson(Map<String, dynamic> json) {
    return LocationGroup(
      id: json['id'] as String,
      centerLatitude: (json['center_latitude'] as num).toDouble(),
      centerLongitude: (json['center_longitude'] as num).toDouble(),
      complaintCount: (json['complaint_count'] as int?) ?? 1,
      hotspotLevel: (json['hotspot_level'] as String?) ?? 'Normal',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'center_latitude': centerLatitude,
      'center_longitude': centerLongitude,
      'complaint_count': complaintCount,
      'hotspot_level': hotspotLevel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

