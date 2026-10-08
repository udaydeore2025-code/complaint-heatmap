class ComplaintUpdate {
  final String id;
  final String complaintId;
  final String? adminId;
  final String? oldStatus;
  final String newStatus;
  final String? comment;
  final DateTime createdAt;

  const ComplaintUpdate({
    required this.id,
    required this.complaintId,
    this.adminId,
    this.oldStatus,
    required this.newStatus,
    this.comment,
    required this.createdAt,
  });

  factory ComplaintUpdate.fromJson(Map<String, dynamic> json) {
    return ComplaintUpdate(
      id: json['id'] as String,
      complaintId: json['complaint_id'] as String,
      adminId: json['admin_id'] as String?,
      oldStatus: json['old_status'] as String?,
      newStatus: json['new_status'] as String,
      comment: json['comment'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

