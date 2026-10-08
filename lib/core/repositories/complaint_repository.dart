import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../constants/supabase_constants.dart';
import '../models/complaint.dart';
import '../models/complaint_update.dart';
import '../services/location_service.dart';
import '../services/priority_calculator.dart';
import '../services/supabase_service.dart';

enum ComplaintSortMode {
  nearMe,
  latest,
  mostUpvoted,
  highestPriority,
}

class ComplaintRepository {
  final SupabaseClient? clientOverride;

  ComplaintRepository({this.clientOverride});

  SupabaseClient get client => clientOverride ?? SupabaseService.client;

  String? get currentUserId {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static const List<String> categories = [
    'All',
    'Pothole',
    'Garbage',
    'Water Supply',
    'Drainage',
    'Streetlight',
    'Road Damage',
    'Public Area',
    'Other',
  ];

  static const List<String> reportableCategories = [
    'Pothole',
    'Garbage',
    'Water Supply',
    'Drainage',
    'Streetlight',
    'Road Damage',
    'Public Area',
    'Other',
  ];

  /// Uploads a photo to Supabase Storage and returns the public URL
  Future<String> uploadComplaintPhoto(XFile photo) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final bytes = await photo.readAsBytes();
    final ext = photo.name.contains('.') ? photo.name.split('.').last : 'jpg';
    final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await client.storage
        .from(SupabaseConstants.complaintImagesBucket)
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    final publicUrl = client.storage
        .from(SupabaseConstants.complaintImagesBucket)
        .getPublicUrl(fileName);

    return publicUrl;
  }

  /// Creates a new civic complaint with deterministic initial priority scoring
  /// and geographical clustering/hotspot detection (without AI).
  Future<Complaint> createComplaint({
    required String category,
    required String description,
    required double latitude,
    required double longitude,
    String? address,
    XFile? photo,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // 1. Upload photo if provided
    String? imageUrl;
    if (photo != null) {
      imageUrl = await uploadComplaintPhoto(photo);
    }

    // 2. Query existing complaints to detect nearby complaints (within 50m)
    final List<dynamic> existingRows = await client
        .from(SupabaseConstants.complaintsTable)
        .select('id, latitude, longitude, location_group_id, related_complaint_count');

    final List<Map<String, dynamic>> nearbyComplaints = [];
    String? matchedLocationGroupId;

    for (final r in existingRows) {
      final lat = (r['latitude'] as num).toDouble();
      final lon = (r['longitude'] as num).toDouble();
      final dist = LocationService.calculateDistanceMeters(
        startLatitude: latitude,
        startLongitude: longitude,
        endLatitude: lat,
        endLongitude: lon,
      );

      if (dist <= AppConstants.hotspotClusterRadiusMeters) {
        nearbyComplaints.add(r as Map<String, dynamic>);
        if (r['location_group_id'] != null && matchedLocationGroupId == null) {
          matchedLocationGroupId = r['location_group_id'] as String;
        }
      }
    }

    final int relatedCount = nearbyComplaints.length;
    final int groupTotalCount = relatedCount + 1;

    // 3. Handle location group / cluster (Phase 23)
    if (relatedCount >= 1) {
      if (matchedLocationGroupId == null) {
        // Create new location group
        final hotspotLevel = PriorityCalculator.calculateHotspotLevel(groupTotalCount);
        final groupRes = await client
            .from(SupabaseConstants.locationGroupsTable)
            .insert({
              'center_latitude': latitude,
              'center_longitude': longitude,
              'complaint_count': groupTotalCount,
              'hotspot_level': hotspotLevel,
            })
            .select()
            .single();

        matchedLocationGroupId = groupRes['id'] as String;

        // Update previously created nearby complaints to belong to this new group
        final nearbyIds = nearbyComplaints.map((c) => c['id'] as String).toList();
        if (nearbyIds.isNotEmpty) {
          await client
              .from(SupabaseConstants.complaintsTable)
              .update({
                'location_group_id': matchedLocationGroupId,
                'related_complaint_count': groupTotalCount,
              })
              .filter('id', 'in', nearbyIds);
        }
      } else {
        // Update existing location group count and hotspot level
        final hotspotLevel = PriorityCalculator.calculateHotspotLevel(groupTotalCount);
        await client
            .from(SupabaseConstants.locationGroupsTable)
            .update({
              'complaint_count': groupTotalCount,
              'hotspot_level': hotspotLevel,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', matchedLocationGroupId);

        // Update all existing nearby complaints count
        final nearbyIds = nearbyComplaints.map((c) => c['id'] as String).toList();
        if (nearbyIds.isNotEmpty) {
          await client
              .from(SupabaseConstants.complaintsTable)
              .update({'related_complaint_count': groupTotalCount})
              .filter('id', 'in', nearbyIds);
        }
      }
    }

    // 4. Calculate deterministic priority score (Phase 21)
    final severityScore = PriorityCalculator.getCategorySeverity(category);
    final severityLevel = PriorityCalculator.mapScoreToSeverityLevel(severityScore);
    final relatedScore = PriorityCalculator.calculateRelatedComplaintScore(relatedCount);
    final hotspotScore = PriorityCalculator.calculateHotspotScore(groupTotalCount);

    final priorityScore = PriorityCalculator.calculatePriorityScore(
      severityScore: severityScore,
      communitySupportScore: 0.0,
      relatedComplaintScore: relatedScore,
      confirmationScore: 0.0,
      hotspotScore: hotspotScore,
    );
    final priorityLevel = PriorityCalculator.getPriorityLevel(priorityScore);

    // 5. Insert new complaint row
    final insertData = {
      'user_id': user.id,
      'category': category,
      'description': description.trim(),
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'severity': severityLevel,
      'priority_score': priorityScore,
      'priority_level': priorityLevel,
      'status': 'PENDING',
      'location_group_id': matchedLocationGroupId,
      'related_complaint_count': relatedCount,
    };

    final newRow = await client
        .from(SupabaseConstants.complaintsTable)
        .insert(insertData)
        .select()
        .single();

    return Complaint.fromJson(newRow);
  }

  /// Deletes a complaint (allowed for creator or admin)
  Future<void> deleteComplaint(String complaintId) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // 1. Fetch image URL if any to delete from storage
    try {
      final row = await client
          .from(SupabaseConstants.complaintsTable)
          .select('image_url')
          .eq('id', complaintId)
          .maybeSingle();

      if (row != null && row['image_url'] != null) {
        final imageUrl = row['image_url'] as String;
        final uri = Uri.tryParse(imageUrl);
        if (uri != null && uri.pathSegments.contains(SupabaseConstants.complaintImagesBucket)) {
          final bucketIdx = uri.pathSegments.indexOf(SupabaseConstants.complaintImagesBucket);
          if (bucketIdx != -1 && bucketIdx + 1 < uri.pathSegments.length) {
            final fileName = uri.pathSegments.sublist(bucketIdx + 1).join('/');
            await client.storage.from(SupabaseConstants.complaintImagesBucket).remove([fileName]);
          }
        }
      }
    } catch (e) {
      debugPrint('Notice: Error cleaning up image on delete: $e');
    }

    // 2. Delete complaint record (cascades to votes, confirmations, and updates)
    await client
        .from(SupabaseConstants.complaintsTable)
        .delete()
        .eq('id', complaintId);
  }

  Future<List<Complaint>> fetchComplaints({
    String? categoryFilter,
    UserPosition? userLocation,
    ComplaintSortMode sortMode = ComplaintSortMode.highestPriority,
  }) async {
    try {
      final currentUserId = client.auth.currentUser?.id;

      // 1. Fetch complaints rows
      var query = client.from(SupabaseConstants.complaintsTable).select();
      if (categoryFilter != null && categoryFilter != 'All') {
        query = query.eq('category', categoryFilter);
      }

      final List<dynamic> complaintRows = await query.order('created_at', ascending: false);
      if (complaintRows.isEmpty) return [];

      final complaintIds = complaintRows.map((r) => r['id'] as String).toList();

      // 2. Fetch votes for these complaints
      final List<dynamic> voteRows = await client
          .from(SupabaseConstants.votesTable)
          .select('complaint_id, user_id, vote_type')
          .filter('complaint_id', 'in', complaintIds);

      // 3. Fetch confirmations for these complaints
      final List<dynamic> confirmationRows = await client
          .from(SupabaseConstants.confirmationsTable)
          .select('complaint_id, user_id')
          .filter('complaint_id', 'in', complaintIds);

      // Map metrics by complaint_id
      final Map<String, int> upvotesMap = {};
      final Map<String, int> downvotesMap = {};
      final Map<String, String?> userVotesMap = {};
      for (final v in voteRows) {
        final cId = v['complaint_id'] as String;
        final type = v['vote_type'] as String;
        final uId = v['user_id'] as String;

        if (type == 'UPVOTE') {
          upvotesMap[cId] = (upvotesMap[cId] ?? 0) + 1;
        } else if (type == 'DOWNVOTE') {
          downvotesMap[cId] = (downvotesMap[cId] ?? 0) + 1;
        }

        if (currentUserId != null && uId == currentUserId) {
          userVotesMap[cId] = type;
        }
      }

      final Map<String, int> confirmationsMap = {};
      final Map<String, bool> userConfirmationsMap = {};
      for (final c in confirmationRows) {
        final cId = c['complaint_id'] as String;
        final uId = c['user_id'] as String;
        confirmationsMap[cId] = (confirmationsMap[cId] ?? 0) + 1;

        if (currentUserId != null && uId == currentUserId) {
          userConfirmationsMap[cId] = true;
        }
      }

      // 4. Construct Complaint objects & calculate distances
      List<Complaint> complaints = complaintRows.map((row) {
        final id = row['id'] as String;
        final lat = (row['latitude'] as num).toDouble();
        final lon = (row['longitude'] as num).toDouble();

        double? distance;
        if (userLocation != null) {
          distance = LocationService.calculateDistanceMeters(
            startLatitude: userLocation.latitude,
            startLongitude: userLocation.longitude,
            endLatitude: lat,
            endLongitude: lon,
          );
        }

        final complaint = Complaint.fromJson(row);
        return complaint.copyWith(
          upvoteCount: upvotesMap[id] ?? 0,
          downvoteCount: downvotesMap[id] ?? 0,
          confirmationCount: confirmationsMap[id] ?? 0,
          distanceMeters: distance,
          currentUserVote: userVotesMap[id],
          isConfirmedByCurrentUser: userConfirmationsMap[id] ?? false,
        );
      }).toList();

      // 5. Apply selected sort mode
      switch (sortMode) {
        case ComplaintSortMode.nearMe:
          complaints.sort((a, b) {
            if (a.distanceMeters == null && b.distanceMeters == null) return 0;
            if (a.distanceMeters == null) return 1;
            if (b.distanceMeters == null) return -1;
            return a.distanceMeters!.compareTo(b.distanceMeters!);
          });
          break;
        case ComplaintSortMode.latest:
          complaints.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
        case ComplaintSortMode.mostUpvoted:
          complaints.sort((a, b) {
            final scoreA = a.upvoteCount - a.downvoteCount;
            final scoreB = b.upvoteCount - b.downvoteCount;
            return scoreB.compareTo(scoreA);
          });
          break;
        case ComplaintSortMode.highestPriority:
          complaints.sort((a, b) {
            final cmp = b.priorityScore.compareTo(a.priorityScore);
            if (cmp != 0) return cmp;
            return b.createdAt.compareTo(a.createdAt);
          });
          break;
      }

      return complaints;
    } catch (e) {
      debugPrint('Error fetching complaints: $e');
      rethrow;
    }
  }

  /// Fetches a single complaint by its ID with full live metrics
  Future<Complaint?> fetchComplaintById(
    String complaintId, {
    UserPosition? userLocation,
  }) async {
    try {
      final currentUserId = client.auth.currentUser?.id;

      final row = await client
          .from(SupabaseConstants.complaintsTable)
          .select()
          .eq('id', complaintId)
          .maybeSingle();

      if (row == null) return null;

      final voteRows = await client
          .from(SupabaseConstants.votesTable)
          .select('user_id, vote_type')
          .eq('complaint_id', complaintId);

      final confRows = await client
          .from(SupabaseConstants.confirmationsTable)
          .select('user_id')
          .eq('complaint_id', complaintId);

      int upvotes = 0;
      int downvotes = 0;
      String? currentUserVote;
      for (final v in voteRows) {
        final type = v['vote_type'] as String;
        final uId = v['user_id'] as String;
        if (type == 'UPVOTE') upvotes++;
        if (type == 'DOWNVOTE') downvotes++;
        if (currentUserId != null && uId == currentUserId) {
          currentUserVote = type;
        }
      }

      int confirmations = confRows.length;
      bool isConfirmed = false;
      if (currentUserId != null) {
        isConfirmed = confRows.any((c) => c['user_id'] == currentUserId);
      }

      double? dist;
      if (userLocation != null) {
        final lat = (row['latitude'] as num).toDouble();
        final lon = (row['longitude'] as num).toDouble();
        dist = LocationService.calculateDistanceMeters(
          startLatitude: userLocation.latitude,
          startLongitude: userLocation.longitude,
          endLatitude: lat,
          endLongitude: lon,
        );
      }

      final complaint = Complaint.fromJson(row);
      return complaint.copyWith(
        upvoteCount: upvotes,
        downvoteCount: downvotes,
        confirmationCount: confirmations,
        distanceMeters: dist,
        currentUserVote: currentUserVote,
        isConfirmedByCurrentUser: isConfirmed,
      );
    } catch (e) {
      debugPrint('Error fetching complaint by ID: $e');
      return null;
    }
  }

  /// Toggles or updates a Reddit-style vote ('UPVOTE' or 'DOWNVOTE').
  /// - If user clicks same vote again: removes the vote.
  /// - If user clicks opposite vote: switches the vote.
  /// - If user hasn't voted: creates the vote.
  /// Automatically recalculates and updates the complaint priority score.
  Future<void> toggleVote({
    required String complaintId,
    required String voteType, // 'UPVOTE' or 'DOWNVOTE'
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final existing = await client
        .from(SupabaseConstants.votesTable)
        .select()
        .eq('complaint_id', complaintId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      final currentType = existing['vote_type'] as String;
      if (currentType == voteType) {
        // Remove vote
        await client
            .from(SupabaseConstants.votesTable)
            .delete()
            .eq('id', existing['id']);
      } else {
        // Switch vote
        await client
            .from(SupabaseConstants.votesTable)
            .update({'vote_type': voteType})
            .eq('id', existing['id']);
      }
    } else {
      // Cast new vote
      await client.from(SupabaseConstants.votesTable).insert({
        'complaint_id': complaintId,
        'user_id': user.id,
        'vote_type': voteType,
      });
    }

    // Deterministically update complaint priority score in database
    await _recalculateAndSavePriority(complaintId);
  }

  /// Toggles community confirmation ("I can confirm this issue").
  /// A citizen can confirm an issue once. Tapping again removes confirmation.
  Future<void> toggleConfirmation({required String complaintId}) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final existing = await client
        .from(SupabaseConstants.confirmationsTable)
        .select()
        .eq('complaint_id', complaintId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      // Remove confirmation
      await client
          .from(SupabaseConstants.confirmationsTable)
          .delete()
          .eq('id', existing['id']);
    } else {
      // Add confirmation
      await client.from(SupabaseConstants.confirmationsTable).insert({
        'complaint_id': complaintId,
        'user_id': user.id,
      });
    }

    // Deterministically update complaint priority score in database
    await _recalculateAndSavePriority(complaintId);
  }

  /// Fetches status history audit trail from complaint_updates
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

  /// Fetches related complaints within the 50-meter radius
  Future<List<Complaint>> fetchRelatedComplaints(
    String complaintId, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      final List<dynamic> rows = await client
          .from(SupabaseConstants.complaintsTable)
          .select()
          .neq('id', complaintId);

      final List<Complaint> related = [];
      for (final r in rows) {
        final lat = (r['latitude'] as num).toDouble();
        final lon = (r['longitude'] as num).toDouble();
        final dist = LocationService.calculateDistanceMeters(
          startLatitude: latitude,
          startLongitude: longitude,
          endLatitude: lat,
          endLongitude: lon,
        );

        if (dist <= AppConstants.hotspotClusterRadiusMeters) {
          final c = Complaint.fromJson(r as Map<String, dynamic>);
          related.add(c.copyWith(distanceMeters: dist));
        }
      }

      return related;
    } catch (e) {
      debugPrint('Error fetching related complaints: $e');
      return [];
    }
  }

  /// Recalculates and updates the priority score in PostgreSQL
  Future<void> _recalculateAndSavePriority(String complaintId) async {
    try {
      final complaintRow = await client
          .from(SupabaseConstants.complaintsTable)
          .select()
          .eq('id', complaintId)
          .maybeSingle();

      if (complaintRow == null) return;

      final voteRows = await client
          .from(SupabaseConstants.votesTable)
          .select('vote_type')
          .eq('complaint_id', complaintId);

      int up = 0;
      int down = 0;
      for (final v in voteRows) {
        if (v['vote_type'] == 'UPVOTE') up++;
        if (v['vote_type'] == 'DOWNVOTE') down++;
      }

      final confRows = await client
          .from(SupabaseConstants.confirmationsTable)
          .select('id')
          .eq('complaint_id', complaintId);
      final int confCount = confRows.length;

      final category = complaintRow['category'] as String;
      final int relatedCount = (complaintRow['related_complaint_count'] as int?) ?? 0;
      final int groupCount = relatedCount + 1;

      final severityScore = PriorityCalculator.getCategorySeverity(category);
      final communitySupportScore = PriorityCalculator.calculateCommunitySupportScore(
        upvotes: up,
        downvotes: down,
      );
      final relatedScore = PriorityCalculator.calculateRelatedComplaintScore(relatedCount);
      final confScore = PriorityCalculator.calculateConfirmationScore(confCount);
      final hotspotScore = PriorityCalculator.calculateHotspotScore(groupCount);

      final double newScore = PriorityCalculator.calculatePriorityScore(
        severityScore: severityScore,
        communitySupportScore: communitySupportScore,
        relatedComplaintScore: relatedScore,
        confirmationScore: confScore,
        hotspotScore: hotspotScore,
      );
      final String newLevel = PriorityCalculator.getPriorityLevel(newScore);

      await client.from(SupabaseConstants.complaintsTable).update({
        'priority_score': newScore,
        'priority_level': newLevel,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', complaintId);
    } catch (e) {
      debugPrint('Error recalculating priority score: $e');
    }
  }

  /// Subscribes to realtime Postgres updates across complaints, votes, and confirmations
  RealtimeChannel? subscribeToComplaints({required VoidCallback onUpdate}) {
    try {
      final channel = client.channel('public:complaints_feed_${DateTime.now().millisecondsSinceEpoch}');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: SupabaseConstants.complaintsTable,
            callback: (payload) => onUpdate(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: SupabaseConstants.votesTable,
            callback: (payload) => onUpdate(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: SupabaseConstants.confirmationsTable,
            callback: (payload) => onUpdate(),
          )
          .subscribe();
      return channel;
    } catch (e) {
      debugPrint('Error subscribing to realtime complaints: $e');
      return null;
    }
  }

  /// Subscribes to realtime updates for a single complaint (votes, confirmations, status history)
  RealtimeChannel? subscribeToComplaint({
    required String complaintId,
    required VoidCallback onUpdate,
  }) {
    try {
      final channel = client.channel('complaint_detail_${complaintId}_${DateTime.now().millisecondsSinceEpoch}');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: SupabaseConstants.complaintsTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: complaintId,
            ),
            callback: (payload) => onUpdate(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: SupabaseConstants.updatesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'complaint_id',
              value: complaintId,
            ),
            callback: (payload) => onUpdate(),
          )
          .subscribe();
      return channel;
    } catch (e) {
      debugPrint('Error subscribing to complaint details: $e');
      return null;
    }
  }

  /// Unsubscribes from a realtime channel
  void unsubscribe(RealtimeChannel? channel) {
    if (channel != null) {
      try {
        client.removeChannel(channel);
      } catch (e) {
        debugPrint('Error removing realtime channel: $e');
      }
    }
  }

  /// Fetches complaints filed by the current logged-in user
  Future<List<Complaint>> fetchMyComplaints() async {
    final user = client.auth.currentUser;
    if (user == null) return [];

    try {
      final List<dynamic> complaintRows = await client
          .from(SupabaseConstants.complaintsTable)
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (complaintRows.isEmpty) return [];

      final complaintIds = complaintRows.map((r) => r['id'] as String).toList();

      final List<dynamic> voteRows = await client
          .from(SupabaseConstants.votesTable)
          .select('complaint_id, vote_type')
          .filter('complaint_id', 'in', complaintIds);

      final List<dynamic> confirmationRows = await client
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
      for (final c in confirmationRows) {
        final id = c['complaint_id'] as String;
        confMap[id] = (confMap[id] ?? 0) + 1;
      }

      final list = complaintRows.map((r) {
        final id = r['id'] as String;
        final complaint = Complaint.fromJson(r as Map<String, dynamic>);
        return complaint.copyWith(
          upvoteCount: upvotesMap[id] ?? 0,
          downvoteCount: downvotesMap[id] ?? 0,
          confirmationCount: confMap[id] ?? 0,
        );
      }).toList();

      list.sort((a, b) {
        final cmp = b.priorityScore.compareTo(a.priorityScore);
        if (cmp != 0) return cmp;
        return b.createdAt.compareTo(a.createdAt);
      });

      return list;
    } catch (e) {
      debugPrint('Error fetching my complaints: $e');
      return [];
    }
  }

  /// Fetches citizen activity statistics
  Future<UserCivicStats> fetchUserStats() async {
    final user = client.auth.currentUser;
    if (user == null) return const UserCivicStats();

    try {
      final List<dynamic> myComplaints = await client
          .from(SupabaseConstants.complaintsTable)
          .select('id, status')
          .eq('user_id', user.id);

      final int total = myComplaints.length;
      final int resolved = myComplaints.where((c) => (c['status'] as String? ?? '').toUpperCase() == 'SOLVED').length;

      final List<dynamic> confirmations = await client
          .from(SupabaseConstants.confirmationsTable)
          .select('id')
          .eq('user_id', user.id);

      final myIds = myComplaints.map((c) => c['id'] as String).toList();
      int totalUpvotes = 0;
      if (myIds.isNotEmpty) {
        final List<dynamic> myVotes = await client
            .from(SupabaseConstants.votesTable)
            .select('vote_type')
            .filter('complaint_id', 'in', myIds)
            .eq('vote_type', 'UPVOTE');
        totalUpvotes = myVotes.length;
      }

      return UserCivicStats(
        totalComplaints: total,
        totalResolved: resolved,
        totalConfirmations: confirmations.length,
        totalUpvotesReceived: totalUpvotes,
      );
    } catch (e) {
      debugPrint('Error fetching user stats: $e');
      return const UserCivicStats();
    }
  }
}

class UserCivicStats {
  final int totalComplaints;
  final int totalResolved;
  final int totalConfirmations;
  final int totalUpvotesReceived;

  const UserCivicStats({
    this.totalComplaints = 0,
    this.totalResolved = 0,
    this.totalConfirmations = 0,
    this.totalUpvotesReceived = 0,
  });
}


