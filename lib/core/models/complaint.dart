class Complaint {
  final String id;
  final String userId;
  final String category;
  final String description;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final String? address;
  final String severity; // 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
  final double priorityScore; // 0.0 to 100.0
  final String priorityLevel; // 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
  final String status; // 'PENDING', 'VERIFIED', 'WORK IN PROGRESS', 'SOLVED'
  final String? locationGroupId;
  final int relatedComplaintCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relational & calculated attributes
  final int upvoteCount;
  final int downvoteCount;
  final int confirmationCount;
  final double? distanceMeters;
  final String? currentUserVote; // 'UPVOTE', 'DOWNVOTE', or null
  final bool isConfirmedByCurrentUser;

  const Complaint({
    required this.id,
    required this.userId,
    required this.category,
    required this.description,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    this.address,
    this.severity = 'MEDIUM',
    this.priorityScore = 0.0,
    this.priorityLevel = 'LOW',
    this.status = 'PENDING',
    this.locationGroupId,
    this.relatedComplaintCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.upvoteCount = 0,
    this.downvoteCount = 0,
    this.confirmationCount = 0,
    this.distanceMeters,
    this.currentUserVote,
    this.isConfirmedByCurrentUser = false,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      imageUrl: json['image_url'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      severity: json['severity'] as String? ?? 'MEDIUM',
      priorityScore: (json['priority_score'] as num?)?.toDouble() ?? 0.0,
      priorityLevel: json['priority_level'] as String? ?? 'LOW',
      status: json['status'] as String? ?? 'PENDING',
      locationGroupId: json['location_group_id'] as String?,
      relatedComplaintCount: json['related_complaint_count'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      upvoteCount: json['upvote_count'] as int? ?? 0,
      downvoteCount: json['downvote_count'] as int? ?? 0,
      confirmationCount: json['confirmation_count'] as int? ?? 0,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      currentUserVote: json['current_user_vote'] as String?,
      isConfirmedByCurrentUser: json['is_confirmed_by_current_user'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'category': category,
      'description': description,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'severity': severity,
      'priority_score': priorityScore,
      'priority_level': priorityLevel,
      'status': status,
      'location_group_id': locationGroupId,
      'related_complaint_count': relatedComplaintCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Complaint copyWith({
    String? id,
    String? userId,
    String? category,
    String? description,
    String? imageUrl,
    double? latitude,
    double? longitude,
    String? address,
    String? severity,
    double? priorityScore,
    String? priorityLevel,
    String? status,
    String? locationGroupId,
    int? relatedComplaintCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? upvoteCount,
    int? downvoteCount,
    int? confirmationCount,
    double? distanceMeters,
    String? currentUserVote,
    bool? isConfirmedByCurrentUser,
  }) {
    return Complaint(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      severity: severity ?? this.severity,
      priorityScore: priorityScore ?? this.priorityScore,
      priorityLevel: priorityLevel ?? this.priorityLevel,
      status: status ?? this.status,
      locationGroupId: locationGroupId ?? this.locationGroupId,
      relatedComplaintCount: relatedComplaintCount ?? this.relatedComplaintCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      upvoteCount: upvoteCount ?? this.upvoteCount,
      downvoteCount: downvoteCount ?? this.downvoteCount,
      confirmationCount: confirmationCount ?? this.confirmationCount,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      currentUserVote: currentUserVote ?? this.currentUserVote,
      isConfirmedByCurrentUser: isConfirmedByCurrentUser ?? this.isConfirmedByCurrentUser,
    );
  }
}

