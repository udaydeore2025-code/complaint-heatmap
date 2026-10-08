import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';
import '../models/complaint.dart';
import '../models/complaint_update.dart';
import '../models/location_group.dart';
import '../services/supabase_service.dart';

class AdminSummary {
  final int totalComplaints;
  final int pendingCount;
  final int verifiedCount;
  final int workInProgressCount;
  final int solvedCount;
  final int highPriorityCount;
  final int hotspotsCount;

  const AdminSummary({
    this.totalComplaints = 0,
    this.pendingCount = 0,
    this.verifiedCount = 0,
    this.workInProgressCount = 0,
    this.solvedCount = 0,
    this.highPriorityCount = 0,
    this.hotspotsCount = 0,
  });
}

class AdminRepository {
  final SupabaseClient? clientOverride;

  AdminRepository({this.clientOverride});

  SupabaseClient get client => clientOverride ?? SupabaseService.client;

  /// Fetches aggregate counts for the Admin Dashboard summary
  Future<AdminSummary> fetchDashboardSummary() async {
    try {
      final List<dynamic> complaintRows = await client
          .from(SupabaseConstants.complaintsTable)
          .select('status, priority_level');

      final List<dynamic> groupRows = await client
          .from(SupabaseConstants.locationGroupsTable)
          .select('hotspot_level');

      int pending = 0;
      int verified = 0;
      int wip = 0;
      int solved = 0;
      int highPriority = 0;

      for (final c in complaintRows) {
        final status = (c['status'] as String? ?? '').toUpperCase();
        final prio = (c['priority_level'] as String? ?? '').toUpperCase();

        if (status == 'PENDING') pending++;
        if (status == 'VERIFIED') verified++;
        if (status == 'WORK IN PROGRESS') wip++;
        if (status == 'SOLVED') solved++;

        if (prio == 'HIGH' || prio == 'CRITICAL') {
          highPriority++;
        }
      }

      int hotspots = 0;
      for (final g in groupRows) {
        final level = g['hotspot_level'] as String? ?? '';
        if (level == 'Hotspot' || level == 'High Activity Zone' || level == 'Complaint Zone') {
          hotspots++;
        }
      }

      return AdminSummary(
        totalComplaints: complaintRows.length,
        pendingCount: pending,
        verifiedCount: verified,
        workInProgressCount: wip,
        solvedCount: solved,
        highPriorityCount: highPriority,
        hotspotsCount: hotspots,
      );
    } catch (e) {
      debugPrint('Error fetching admin summary: $e');
      return const AdminSummary();
    }
  }

  /// Fetches complaints ordered from highest to lowest priority score
  Future<List<Complaint>> fetchPriorityQueue({String? statusFilter}) async {
    try {
      var query = client.from(SupabaseConstants.complaintsTable).select();

      if (statusFilter != null && statusFilter != 'ALL') {
        query = query.eq('status', statusFilter);
      }

      final List<dynamic> rows = await query.order('priority_score', ascending: false);
      if (rows.isEmpty) return [];

      final complaintIds = rows.map((r) => r['id'] as String).toList();

      // Fetch votes count
      final List<dynamic> voteRows = await client
          .from(SupabaseConstants.votesTable)
          .select('complaint_id, vote_type')
          .filter('complaint_id', 'in', complaintIds);

      // Fetch confirmation count
      final List<dynamic> confRows = await client
          .from(SupabaseConstants.confirmationsTable)
          .select('complaint_id')
          .filter('complaint_id', 'in', complaintIds);

      final Map<String, int> upvotesMap = {};
      final Map<String, int> downvotesMap = {};
      for (final v in voteRows) {
        final id = v['complaint_id'] as String;
        final type = v['vote_type'] as String;
        if (type == 'UPVOTE') upvotesMap[id] = (upvotesMap[id] ?? 0) + 1;
        if (type == 'DOWNVOTE') downvotesMap[id] = (downvotesMap[id] ?? 0) + 1;
      }

      final Map<String, int> confMap = {};
      for (final c in confRows) {
        final id = c['complaint_id'] as String;
        confMap[id] = (confMap[id] ?? 0) + 1;
      }

      return rows.map((r) {
        final id = r['id'] as String;
        final complaint = Complaint.fromJson(r as Map<String, dynamic>);
        return complaint.copyWith(
          upvoteCount: upvotesMap[id] ?? 0,
          downvoteCount: downvotesMap[id] ?? 0,
          confirmationCount: confMap[id] ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching priority queue: $e');
      return [];
    }
  }

  /// Updates status with audit trail recorded in complaint_updates
  Future<void> updateComplaintStatus({
    required String complaintId,
    required String oldStatus,
    required String newStatus,
    String? comment,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Admin not authenticated');

    // 1. Record update in complaint_updates audit table
    await client.from(SupabaseConstants.updatesTable).insert({
      'complaint_id': complaintId,
      'admin_id': user.id,
      'old_status': oldStatus,
      'new_status': newStatus,
      'comment': comment,
    });

    // 2. Update status in complaints table
    await client.from(SupabaseConstants.complaintsTable).update({
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', complaintId);
  }

  /// Fetches status history for admin
  Future<List<ComplaintUpdate>> fetchStatusHistory(String complaintId) async {
    try {
      final List<dynamic> rows = await client
          .from(SupabaseConstants.updatesTable)
          .select()
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: true);

      return rows.map((r) => ComplaintUpdate.fromJson(r as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching status history: $e');
      return [];
    }
  }

  /// Fetches all location groups / hotspot clusters
  Future<List<LocationGroup>> fetchLocationGroups() async {
    try {
      final List<dynamic> rows = await client
          .from(SupabaseConstants.locationGroupsTable)
          .select()
          .order('complaint_count', ascending: false);

      return rows.map((r) => LocationGroup.fromJson(r as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching location groups: $e');
      return [];
    }
  }
}

