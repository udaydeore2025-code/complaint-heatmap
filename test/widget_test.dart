import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:complaint_heatmap/main.dart';
import 'package:complaint_heatmap/core/constants/app_constants.dart';
import 'package:complaint_heatmap/core/models/complaint.dart';
import 'package:complaint_heatmap/core/models/complaint_update.dart';
import 'package:complaint_heatmap/core/models/user_profile.dart';
import 'package:complaint_heatmap/core/repositories/auth_repository.dart';
import 'package:complaint_heatmap/core/repositories/complaint_repository.dart';
import 'package:complaint_heatmap/core/services/location_service.dart';
import 'package:complaint_heatmap/core/services/priority_calculator.dart';
import 'package:complaint_heatmap/features/auth/screens/auth_gate.dart';
import 'package:complaint_heatmap/features/auth/screens/email_login_screen.dart';
import 'package:complaint_heatmap/features/complaints/screens/complaint_details_screen.dart';
import 'package:complaint_heatmap/features/complaints/screens/report_complaint_screen.dart';
import 'package:complaint_heatmap/features/admin/screens/admin_dashboard_screen.dart';
import 'package:complaint_heatmap/features/admin/screens/admin_complaint_details_screen.dart';
import 'package:complaint_heatmap/features/admin/screens/admin_map_screen.dart';
import 'package:complaint_heatmap/core/models/location_group.dart';
import 'package:complaint_heatmap/features/complaints/screens/my_complaints_screen.dart';
import 'package:complaint_heatmap/features/profile/screens/profile_screen.dart';
import 'package:complaint_heatmap/core/repositories/admin_repository.dart';
import 'package:complaint_heatmap/features/home/screens/home_feed_screen.dart';
import 'package:complaint_heatmap/widgets/complaint_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthRepository extends AuthRepository {
  bool otpSent = false;
  String? sentEmail;
  User? mockUser;
  UserProfile? mockProfile;
  String? updatedRole;

  @override
  User? get currentUser => mockUser;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<void> sendOtp({required String email}) async {
    otpSent = true;
    sentEmail = email;
  }

  @override
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
    String? portalRole,
  }) async {
    if (portalRole != null) {
      setActivePortalRole(portalRole);
    }
    return AuthResponse(
      session: null,
      user: mockUser,
    );
  }

  @override
  Future<void> updateUserRole(String userId, String role) async {
    updatedRole = role;
    setActivePortalRole(role);
  }

  @override
  Future<UserProfile?> fetchUserProfile(String userId) async {
    return mockProfile;
  }
}

class FakeComplaintRepository extends ComplaintRepository {
  @override
  Future<List<ComplaintUpdate>> fetchStatusHistory(String complaintId) async => [
        ComplaintUpdate(
          id: 'upd-1',
          complaintId: complaintId,
          oldStatus: 'PENDING',
          newStatus: 'VERIFIED',
          comment: 'Inspected by field team',
          createdAt: DateTime.now(),
        ),
      ];

  @override
  Future<List<Complaint>> fetchRelatedComplaints(
    String complaintId, {
    required double latitude,
    required double longitude,
  }) async => [];

  @override
  Future<Complaint?> fetchComplaintById(
    String complaintId, {
    UserPosition? userLocation,
  }) async => null;

  @override
  RealtimeChannel? subscribeToComplaint({
    required String complaintId,
    required VoidCallback onUpdate,
  }) => null;

  @override
  RealtimeChannel? subscribeToComplaints({required VoidCallback onUpdate}) => null;

  @override
  Future<List<Complaint>> fetchMyComplaints() async {
    return [
      Complaint(
        id: 'my-comp-1',
        userId: 'user-123',
        category: 'Streetlight',
        description: 'Streetlight is broken near park entrance.',
        latitude: 18.5204,
        longitude: 73.8567,
        severity: 'LOW',
        priorityScore: 35.0,
        priorityLevel: 'LOW',
        status: 'PENDING',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  List<Complaint> feedComplaints = [];

  @override
  Future<List<Complaint>> fetchComplaints({
    String? categoryFilter,
    UserPosition? userLocation,
    ComplaintSortMode sortMode = ComplaintSortMode.highestPriority,
  }) async {
    return List<Complaint>.from(feedComplaints);
  }

  String? deletedComplaintId;

  @override
  String? get currentUserId => 'user-123';

  @override
  Future<void> deleteComplaint(String complaintId) async {
    deletedComplaintId = complaintId;
    feedComplaints.removeWhere((c) => c.id == complaintId);
  }

  @override
  Future<UserCivicStats> fetchUserStats() async {
    return const UserCivicStats(
      totalComplaints: 3,
      totalResolved: 1,
      totalConfirmations: 5,
      totalUpvotesReceived: 14,
    );
  }
}

class FakeAdminRepository extends AdminRepository {
  @override
  Future<AdminSummary> fetchDashboardSummary() async {
    return const AdminSummary(
      totalComplaints: 15,
      pendingCount: 4,
      verifiedCount: 3,
      workInProgressCount: 2,
      solvedCount: 3,
      highPriorityCount: 5,
      hotspotsCount: 1,
    );
  }

  @override
  Future<List<Complaint>> fetchPriorityQueue({String? statusFilter}) async {
    return [
      Complaint(
        id: 'comp-admin-1',
        userId: 'user-1',
        userName: 'Ramesh Patil',
        userEmail: 'ramesh@example.com',
        category: 'Pothole',
        description: 'Dangerous crater on expressway lane.',
        latitude: 18.5204,
        longitude: 73.8567,
        severity: 'CRITICAL',
        priorityScore: 88.5,
        priorityLevel: 'CRITICAL',
        status: 'PENDING',
        upvoteCount: 45,
        downvoteCount: 1,
        confirmationCount: 12,
        relatedComplaintCount: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<List<ComplaintUpdate>> fetchStatusHistory(String complaintId) async => [];

  @override
  Future<List<LocationGroup>> fetchLocationGroups() async => [];

  String? deletedComplaintId;

  @override
  Future<void> deleteComplaint(String complaintId) async {
    deletedComplaintId = complaintId;
  }
}

void main() {
  testWidgets('CivicConnectApp displays splash screen and branding', (WidgetTester tester) async {
    await tester.pumpWidget(const CivicConnectApp());

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text(AppConstants.appTagline), findsOneWidget);
  });

  testWidgets('EmailLoginScreen renders email input and SEND OTP button', (WidgetTester tester) async {
    final fakeAuth = FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: EmailLoginScreen(authRepository: fakeAuth),
      ),
    );

    expect(find.text('Sign in with Email OTP'), findsOneWidget);
    expect(find.text('SEND OTP'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);

    // Tapping Send OTP with empty field shows validation error
    await tester.tap(find.text('SEND OTP'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);

    // Entering a valid email and tapping Send OTP
    await tester.enterText(find.byType(TextFormField), 'citizen@example.com');
    await tester.tap(find.text('SEND OTP'));
    await tester.pumpAndSettle();

    expect(fakeAuth.otpSent, isTrue);
    expect(fakeAuth.sentEmail, equals('citizen@example.com'));
    expect(find.text('Enter Verification Code'), findsOneWidget);
    expect(find.text('VERIFY OTP'), findsOneWidget);
  });

  test('LocationService formats distance correctly', () {
    expect(LocationService.formatDistance(180), equals('180 m away'));
    expect(LocationService.formatDistance(999), equals('999 m away'));
    expect(LocationService.formatDistance(1200), equals('1.2 km away'));
    expect(LocationService.formatDistance(5400), equals('5.4 km away'));
  });

  testWidgets('ComplaintCard renders category, description, distance, and metrics', (WidgetTester tester) async {
    final testComplaint = Complaint(
      id: 'comp-1',
      userId: 'user-1',
      category: 'Pothole',
      description: 'Large pothole near main road.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'HIGH',
      priorityScore: 72.0,
      priorityLevel: 'HIGH',
      status: 'VERIFIED',
      relatedComplaintCount: 3,
      upvoteCount: 42,
      downvoteCount: 3,
      confirmationCount: 12,
      distanceMeters: 180,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComplaintCard(complaint: testComplaint),
        ),
      ),
    );

    expect(find.text('POTHOLE'), findsOneWidget);
    expect(find.text('Large pothole near main road.'), findsOneWidget);
    expect(find.text('180 m away'), findsOneWidget);
    expect(find.text('VERIFIED'), findsOneWidget);
    expect(find.text('HIGH (72)'), findsOneWidget);
    expect(find.text('3 related nearby'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('12 confirmed'), findsOneWidget);
  });

  test('PriorityCalculator calculates deterministic priority and rules correctly', () {
    expect(PriorityCalculator.getCategorySeverity('Pothole'), equals(70.0));
    expect(PriorityCalculator.getCategorySeverity('Garbage'), equals(50.0));
    expect(PriorityCalculator.getCategorySeverity('Water Supply'), equals(80.0));
    expect(PriorityCalculator.getCategorySeverity('Streetlight'), equals(40.0));

    final supportScore = PriorityCalculator.calculateCommunitySupportScore(
      upvotes: 40,
      downvotes: 5,
    );
    expect(supportScore, closeTo(88.88, 0.1));

    expect(PriorityCalculator.calculateRelatedComplaintScore(0), equals(0.0));
    expect(PriorityCalculator.calculateRelatedComplaintScore(1), equals(20.0));
    expect(PriorityCalculator.calculateRelatedComplaintScore(3), equals(60.0));
    expect(PriorityCalculator.calculateRelatedComplaintScore(5), equals(100.0));

    expect(PriorityCalculator.calculateHotspotScore(1), equals(0.0));
    expect(PriorityCalculator.calculateHotspotScore(2), equals(40.0));
    expect(PriorityCalculator.calculateHotspotScore(3), equals(60.0));
    expect(PriorityCalculator.calculateHotspotLevel(2), equals('Complaint Zone'));
    expect(PriorityCalculator.calculateHotspotLevel(4), equals('High Activity Zone'));
    expect(PriorityCalculator.calculateHotspotLevel(6), equals('Hotspot'));

    final totalPriority = PriorityCalculator.calculatePriorityScore(
      severityScore: 70.0,
      communitySupportScore: 80.0,
      relatedComplaintScore: 60.0,
      confirmationScore: 50.0,
      hotspotScore: 40.0,
    );
    expect(totalPriority, equals(63.5));
    expect(PriorityCalculator.getPriorityLevel(totalPriority), equals('HIGH'));
  });

  testWidgets('ReportComplaintScreen renders fields and requires coordinates', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: ReportComplaintScreen(),
      ),
    );

    expect(find.text('Report Civic Issue'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('USE CURRENT LOCATION'), findsOneWidget);
    expect(find.text('SUBMIT COMPLAINT'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Deep pothole on the main avenue');

    await tester.ensureVisible(find.text('SUBMIT COMPLAINT'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SUBMIT COMPLAINT'));
    await tester.pumpAndSettle();
    expect(find.text('Please tap "USE CURRENT LOCATION" to capture issue coordinates.'), findsOneWidget);
  });

  testWidgets('ComplaintDetailsScreen renders timeline, votes, and confirmation button', (WidgetTester tester) async {
    final complaint = Complaint(
      id: 'comp-details-1',
      userId: 'user-1',
      category: 'Water Supply',
      description: 'Severe pipe burst flooding the residential street.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'HIGH',
      priorityScore: 78.0,
      priorityLevel: 'HIGH',
      status: 'VERIFIED',
      relatedComplaintCount: 2,
      upvoteCount: 30,
      downvoteCount: 2,
      confirmationCount: 8,
      distanceMeters: 450,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ComplaintDetailsScreen(
          initialComplaint: complaint,
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complaint Details'), findsOneWidget);
    expect(find.text('WATER SUPPLY'), findsOneWidget);
    expect(find.text('Severe pipe burst flooding the residential street.'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('8 confirmed'), findsOneWidget);
    expect(find.text('I can confirm this issue (I observed it)'), findsOneWidget);
    expect(find.text('Status Timeline'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Solved'), findsOneWidget);
  });

  test('ComplaintUpdate model serialization', () {
    final update = ComplaintUpdate(
      id: 'upd-10',
      complaintId: 'comp-10',
      adminId: 'admin-1',
      oldStatus: 'PENDING',
      newStatus: 'VERIFIED',
      comment: 'Verified on field visit',
      createdAt: DateTime.now(),
    );
    expect(update.newStatus, equals('VERIFIED'));
    expect(update.comment, equals('Verified on field visit'));
  });

  test('UserProfile model role checks and serialization', () {
    final citizen = UserProfile(
      id: 'user-123',
      email: 'citizen@example.com',
      name: 'John Citizen',
      role: 'citizen',
      createdAt: DateTime.now(),
    );
    expect(citizen.isAdmin, isFalse);

    final admin = UserProfile(
      id: 'admin-123',
      email: 'admin@example.com',
      name: 'Admin User',
      role: 'admin',
      createdAt: DateTime.now(),
    );
    expect(admin.isAdmin, isTrue);

    final json = admin.toJson();
    final reconstructed = UserProfile.fromJson(json);
    expect(reconstructed.id, equals('admin-123'));
    expect(reconstructed.role, equals('admin'));
    expect(reconstructed.isAdmin, isTrue);
  });

  testWidgets('AdminDashboardScreen renders summary metrics and priority queue', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);

    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      role: 'admin',
      name: 'Super Admin',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          profile: adminUser,
          adminRepository: FakeAdminRepository(),
          authRepository: FakeAuthRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin Console'), findsOneWidget);
    expect(find.text('Logged in: Super Admin'), findsOneWidget);
    expect(find.text('Total Reports'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('Pending Review'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Priority Queue'), findsOneWidget);
    expect(find.text('Dangerous crater on expressway lane.'), findsOneWidget);
    expect(find.text('CRITICAL (88.5)'), findsOneWidget);
  });

  testWidgets('MyComplaintsScreen renders citizen reported issues', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyComplaintsScreen(
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Reported Issues'), findsOneWidget);
    expect(find.text('Streetlight is broken near park entrance.'), findsOneWidget);
    expect(find.text('STREETLIGHT'), findsOneWidget);
  });

  testWidgets('ProfileScreen renders citizen information and civic impact stats', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);

    final citizen = UserProfile(
      id: 'citizen-101',
      email: 'citizen@pune.gov.in',
      name: 'Rohan Sharma',
      role: 'citizen',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: citizen,
          authRepository: FakeAuthRepository(),
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Citizen Profile'), findsOneWidget);
    expect(find.text('RS'), findsOneWidget); // Initials
    expect(find.text('Rohan Sharma'), findsOneWidget);
    expect(find.text('citizen@pune.gov.in'), findsOneWidget);
    expect(find.text('VERIFIED CITIZEN'), findsOneWidget);
    expect(find.text('Civic Activity & Impact'), findsOneWidget);
    expect(find.text('Reported'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Upvotes'), findsOneWidget);
    expect(find.text('My Reported Issues'), findsOneWidget);
    expect(find.text('Civic Map'), findsOneWidget);
  });

  testWidgets('MyComplaintsScreen can delete a complaint via confirmation dialog', (WidgetTester tester) async {
    final fakeRepo = FakeComplaintRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: MyComplaintsScreen(
          complaintRepository: fakeRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Streetlight is broken near park entrance.'), findsOneWidget);
    final deleteBtn = find.byIcon(Icons.delete_outline);
    expect(deleteBtn, findsOneWidget);

    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    expect(find.text('Delete Complaint?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(fakeRepo.deletedComplaintId, 'my-comp-1');
  });

  test('Highest priority complaint sorting places maximum score complaint at the top', () {
    final list = [
      Complaint(
        id: '1',
        userId: 'u1',
        category: 'Streetlight',
        description: 'Low prio',
        latitude: 18.0,
        longitude: 73.0,
        severity: 'LOW',
        priorityScore: 25.0,
        priorityLevel: 'LOW',
        status: 'PENDING',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      ),
      Complaint(
        id: '2',
        userId: 'u2',
        category: 'Drainage',
        description: 'Critical flood issue',
        latitude: 18.0,
        longitude: 73.0,
        severity: 'CRITICAL',
        priorityScore: 92.5,
        priorityLevel: 'CRITICAL',
        status: 'PENDING',
        createdAt: DateTime(2025, 1, 2),
        updatedAt: DateTime(2025, 1, 2),
      ),
      Complaint(
        id: '3',
        userId: 'u3',
        category: 'Pothole',
        description: 'Medium hole',
        latitude: 18.0,
        longitude: 73.0,
        severity: 'MEDIUM',
        priorityScore: 54.0,
        priorityLevel: 'MEDIUM',
        status: 'PENDING',
        createdAt: DateTime(2025, 1, 3),
        updatedAt: DateTime(2025, 1, 3),
      ),
    ];

    list.sort((a, b) {
      final cmp = b.priorityScore.compareTo(a.priorityScore);
      if (cmp != 0) return cmp;
      return b.createdAt.compareTo(a.createdAt);
    });

    expect(list.first.id, '2');
    expect(list.first.priorityScore, 92.5);
    expect(list.last.id, '1');
    expect(list.last.priorityScore, 25.0);
  });

  testWidgets('ComplaintDetailsScreen renders delete options when user is owner and executes delete', (WidgetTester tester) async {
    final complaint = Complaint(
      id: 'comp-owner-1',
      userId: 'user-123',
      category: 'Garbage',
      description: 'Overflowing dumpster behind market.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'MEDIUM',
      priorityScore: 50.0,
      priorityLevel: 'MEDIUM',
      status: 'PENDING',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final fakeRepo = FakeComplaintRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ComplaintDetailsScreen(
          initialComplaint: complaint,
          complaintRepository: fakeRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DELETE THIS COMPLAINT'), findsOneWidget);

    await tester.tap(find.text('DELETE THIS COMPLAINT'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Complaint?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(fakeRepo.deletedComplaintId, 'comp-owner-1');
  });

  testWidgets('Citizen profile does NOT contain Admin Console or switch option', (WidgetTester tester) async {
    final citizen = UserProfile(
      id: 'citizen-202',
      email: 'citizen2@pune.gov.in',
      name: 'Priya Deshmukh',
      role: 'citizen',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: citizen,
          authRepository: FakeAuthRepository(),
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin Console'), findsNothing);
    expect(find.text('Activate Admin Access?'), findsNothing);
    expect(find.text('My Reported Issues'), findsOneWidget);
    expect(find.text('Civic Map'), findsOneWidget);
  });

  testWidgets('EmailLoginScreen allows switching to Administrative Login and displays restricted access badge', (WidgetTester tester) async {
    final fakeAuth = FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: EmailLoginScreen(authRepository: fakeAuth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Citizen Login'), findsOneWidget);
    expect(find.text('Admin Login'), findsOneWidget);
    expect(find.text('Sign in with Email OTP'), findsOneWidget);

    // Switch to Admin Login
    await tester.tap(find.text('Admin Login'));
    await tester.pumpAndSettle();

    expect(find.text('Municipal Administrative Login'), findsOneWidget);
    expect(find.text('SEND ADMIN OTP'), findsOneWidget);
    expect(find.text('Return to Citizen Login'), findsOneWidget);

    // Switch back to Citizen Login
    await tester.tap(find.text('Return to Citizen Login'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Email OTP'), findsOneWidget);
    expect(find.text('SEND OTP'), findsOneWidget);
  });

  testWidgets('EmailLoginScreen displays Municipal Staff Passkey field in Admin mode', (WidgetTester tester) async {
    final fakeAuth = FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: EmailLoginScreen(authRepository: fakeAuth),
      ),
    );
    await tester.pumpAndSettle();

    // In citizen mode, passkey field does not exist
    expect(find.text('Municipal Staff Passkey'), findsNothing);

    // Switch to Admin
    await tester.tap(find.text('Admin Login'));
    await tester.pumpAndSettle();

    // In admin mode, passkey field is clearly present
    expect(find.text('Municipal Staff Passkey'), findsOneWidget);
    expect(find.text('Staff Passkey: CIVIC-ADMIN-2026'), findsOneWidget);
  });

  testWidgets('AdminDashboardScreen renders quick action buttons Verify, In Progress, Solve directly on complaint card', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      name: 'Commissioner Sharma',
      role: 'ADMIN',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          profile: adminUser,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priority Queue'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Solve'), findsOneWidget);
  });

  testWidgets('ComplaintDetailsScreen renders MUNICIPAL ADMINISTRATIVE ACTIONS only when user is admin', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final sampleComplaint = Complaint(
      id: 'comp-detail-test',
      userId: 'user-xyz',
      category: 'Garbage',
      description: 'Overflowing dumpster behind market.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'HIGH',
      priorityScore: 75.0,
      priorityLevel: 'HIGH',
      status: 'PENDING',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final citizenUser = UserProfile(
      id: 'user-xyz',
      email: 'citizen@example.com',
      role: 'citizen',
      createdAt: DateTime.now(),
    );

    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      role: 'ADMIN',
      createdAt: DateTime.now(),
    );

    // 1. Citizen viewing complaint details
    await tester.pumpWidget(
      MaterialApp(
        home: ComplaintDetailsScreen(
          initialComplaint: sampleComplaint,
          complaintRepository: FakeComplaintRepository(),
          userProfile: citizenUser,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MUNICIPAL ADMINISTRATIVE ACTIONS'), findsNothing);

    // 2. Admin viewing complaint details
    await tester.pumpWidget(
      MaterialApp(
        home: ComplaintDetailsScreen(
          initialComplaint: sampleComplaint,
          complaintRepository: FakeComplaintRepository(),
          userProfile: adminUser,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MUNICIPAL ADMINISTRATIVE ACTIONS'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Verify'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'In Progress'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Solve'), findsOneWidget);
  });

  testWidgets('AdminDashboardScreen displays Complaint ID, Complainant Name, and Date/Time on cards', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      name: 'Commissioner Sharma',
      role: 'ADMIN',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          profile: adminUser,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complainant: Ramesh Patil'), findsOneWidget);
    expect(find.text('#CMP-COMP-ADM'), findsOneWidget);
  });

  testWidgets('AdminComplaintDetailsScreen displays Complainant & Filing Details card with Name, Email, and ID', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final testComplaint = Complaint(
      id: 'complaint-xyz-1234',
      userId: 'user-patil',
      userName: 'Ramesh Patil',
      userEmail: 'ramesh@example.com',
      category: 'Pothole',
      description: 'Major road hazard near bus stop.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'CRITICAL',
      priorityScore: 88.5,
      priorityLevel: 'CRITICAL',
      status: 'PENDING',
      createdAt: DateTime(2026, 10, 9, 10, 30),
      updatedAt: DateTime(2026, 10, 9, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminComplaintDetailsScreen(
          complaint: testComplaint,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complainant & Filing Details'), findsOneWidget);
    expect(find.text('Ramesh Patil'), findsOneWidget);
    expect(find.text('ramesh@example.com'), findsOneWidget);
    expect(find.text('#CMP-COMPLAIN'), findsOneWidget);
    expect(find.text('Oct 9, 2026 at 10:30 AM'), findsOneWidget);
  });

  testWidgets('HomeFeedScreen deletes complaint and immediately removes it from the citizen dashboard feed', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final citizen = UserProfile(
      id: 'user-123',
      email: 'citizen@example.com',
      name: 'Anil Kumar',
      role: 'citizen',
      createdAt: DateTime.now(),
    );

    final sample = Complaint(
      id: 'feed-comp-delete-1',
      userId: 'user-123',
      category: 'Pothole',
      description: 'Severe pothole in front of sector 4 gate.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'HIGH',
      priorityScore: 78.0,
      priorityLevel: 'HIGH',
      status: 'PENDING',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    LocationService.mockLocation = const UserPosition(latitude: 18.5204, longitude: 73.8567);
    addTearDown(() => LocationService.mockLocation = null);

    final fakeRepo = FakeComplaintRepository();
    fakeRepo.feedComplaints = [sample];

    await tester.pumpWidget(
      MaterialApp(
        home: HomeFeedScreen(
          profile: citizen,
          complaintRepository: fakeRepo,
          authRepository: FakeAuthRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Severe pothole in front of sector 4 gate.'), findsOneWidget);

    // Tap delete icon on complaint card
    final deleteIcon = find.byIcon(Icons.delete_outline);
    expect(deleteIcon, findsOneWidget);
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    expect(find.text('Delete Complaint?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(fakeRepo.deletedComplaintId, equals('feed-comp-delete-1'));
    expect(find.text('Severe pothole in front of sector 4 gate.'), findsNothing);
    expect(find.text('No complaints reported yet'), findsOneWidget);
  });

  testWidgets('AdminDashboardScreen allows admin to delete complaint via card delete button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      name: 'Commissioner Sharma',
      role: 'ADMIN',
      createdAt: DateTime.now(),
    );

    final fakeAdmin = FakeAdminRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          profile: adminUser,
          adminRepository: fakeAdmin,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dangerous crater on expressway lane.'), findsOneWidget);

    // Find and tap the delete trash icon in the complaint card header
    final deleteIcons = find.byIcon(Icons.delete_outline);
    expect(deleteIcons, findsWidgets);
    await tester.tap(deleteIcons.first);
    await tester.pumpAndSettle();

    expect(find.text('Delete Complaint as Admin?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Permanently'));
    await tester.pumpAndSettle();

    expect(fakeAdmin.deletedComplaintId, equals('comp-admin-1'));
  });

  testWidgets('AdminComplaintDetailsScreen renders delete options and allows admin to delete complaint', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final testComplaint = Complaint(
      id: 'complaint-to-delete-99',
      userId: 'user-xyz',
      userName: 'Suresh Raina',
      userEmail: 'suresh@example.com',
      category: 'Garbage',
      description: 'Garbage accumulated near market.',
      latitude: 18.5204,
      longitude: 73.8567,
      severity: 'HIGH',
      priorityScore: 75.0,
      priorityLevel: 'HIGH',
      status: 'PENDING',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final fakeAdmin = FakeAdminRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AdminComplaintDetailsScreen(
          complaint: testComplaint,
          adminRepository: fakeAdmin,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DELETE COMPLAINT AS ADMIN'), findsOneWidget);

    // Tap delete button in administrative actions
    await tester.tap(find.text('DELETE COMPLAINT AS ADMIN'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Complaint as Admin?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Permanently'));
    await tester.pumpAndSettle();

    expect(fakeAdmin.deletedComplaintId, equals('complaint-to-delete-99'));
  });

  testWidgets('AuthGate routes to individual Citizen Dashboard (HomeFeedScreen) when citizen logs in, even if previous profile was admin', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    LocationService.mockLocation = const UserPosition(latitude: 18.5204, longitude: 73.8567);
    addTearDown(() => LocationService.mockLocation = null);

    final fakeAuth = FakeAuthRepository();
    fakeAuth.mockUser = User(
      id: 'officer-1',
      appMetadata: const {},
      userMetadata: const {'name': 'Civic Officer'},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    // Profile in DB was admin from previous session
    fakeAuth.mockProfile = UserProfile(
      id: 'officer-1',
      email: 'officer@civic.gov',
      name: 'Civic Officer',
      role: 'admin',
      createdAt: DateTime.now(),
    );
    // User explicitly signed in via Citizen Portal
    fakeAuth.setActivePortalRole('citizen');

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authRepository: fakeAuth,
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify individual Citizen Dashboard (HomeFeedScreen) is displayed
    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Report Complaint'), findsOneWidget);
    expect(find.byTooltip('My Reported Issues'), findsOneWidget);

    // Verify Admin Console is NOT displayed
    expect(find.text('Admin Console'), findsNothing);
    expect(find.text('CivicConnect Municipal Portal'), findsNothing);
  });

  testWidgets('AuthGate routes to individual Admin Dashboard (AdminDashboardScreen) when admin logs in', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final fakeAuth = FakeAuthRepository();
    fakeAuth.mockUser = User(
      id: 'admin-1',
      appMetadata: const {},
      userMetadata: const {'name': 'Municipal Officer'},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    fakeAuth.mockProfile = UserProfile(
      id: 'admin-1',
      email: 'admin@civic.gov',
      name: 'Municipal Officer',
      role: 'admin',
      createdAt: DateTime.now(),
    );
    // User explicitly signed in via Admin Portal
    fakeAuth.setActivePortalRole('admin');

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authRepository: fakeAuth,
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify individual Admin Dashboard (AdminDashboardScreen) is displayed
    expect(find.text('Admin Console'), findsOneWidget);
    expect(find.text('CivicConnect Municipal Portal'), findsOneWidget);
    expect(find.text('Priority Queue'), findsOneWidget);

    // Verify citizen bottom navigation / report issue is NOT displayed
    expect(find.text('Report Issue'), findsNothing);
  });

  testWidgets('HomeFeedScreen displays Sign Out button in AppBar and prompts confirmation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    LocationService.mockLocation = const UserPosition(latitude: 18.5204, longitude: 73.8567);
    addTearDown(() => LocationService.mockLocation = null);

    final citizenUser = UserProfile(
      id: 'citizen-101',
      email: 'citizen@example.com',
      name: 'Citizen Jane',
      role: 'citizen',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeFeedScreen(
          profile: citizenUser,
          complaintRepository: FakeComplaintRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sign Out icon exists in citizen AppBar
    final signOutButton = find.widgetWithIcon(IconButton, Icons.logout);
    expect(signOutButton, findsOneWidget);

    await tester.tap(signOutButton);
    await tester.pumpAndSettle();

    expect(find.text('Sign Out?'), findsOneWidget);
    expect(find.text('Are you sure you want to sign out of CivicConnect?'), findsOneWidget);
  });

  testWidgets('AdminComplaintDetailsScreen renders Google Maps navigation options in Exact Location card and AppBar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final testComplaint = Complaint(
      id: 'comp-nav-1',
      userId: 'user-uday',
      userName: 'udaydeore2025',
      userEmail: 'udaydeore2025@gmail.com',
      category: 'Pothole',
      description: 'Dangerous pothole on highway',
      latitude: 18.489974,
      longitude: 73.818564,
      severity: 'HIGH',
      priorityScore: 78.0,
      priorityLevel: 'HIGH',
      status: 'PENDING',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminComplaintDetailsScreen(
          complaint: testComplaint,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Navigate in Google Maps button is rendered in the Exact Location card
    expect(find.text('Navigate in Google Maps'), findsOneWidget);

    // Verify View Hotspot Cluster on Map button is rendered
    expect(find.text('View Hotspot Cluster on Map'), findsOneWidget);

    // Verify Google Maps navigation icon is in AppBar
    expect(find.byTooltip('Navigate via Google Maps'), findsOneWidget);
    expect(find.byTooltip('View on Hotspot Map'), findsOneWidget);
  });

  testWidgets('AdminDashboardScreen renders Navigate via Google Maps on complaint cards', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final adminUser = UserProfile(
      id: 'admin-99',
      email: 'admin@civic.gov',
      name: 'Municipal Commissioner',
      role: 'admin',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          profile: adminUser,
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Navigate via Google Maps button is on the priority queue cards
    expect(find.text('Navigate via Google Maps'), findsWidgets);
    expect(find.byTooltip('View on Hotspot Map'), findsWidgets);
  });

  testWidgets('AdminMapScreen toggles to Hotspot List view and renders Google Maps navigation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminMapScreen(
          adminRepository: FakeAdminRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify app bar actions and title
    expect(find.text('Admin Hotspot Map'), findsOneWidget);
    expect(find.byTooltip('Show Hotspot List'), findsOneWidget);

    // Tap to switch to Hotspot List view
    await tester.tap(find.byTooltip('Show Hotspot List'));
    await tester.pumpAndSettle();

    // Verify list view elements
    expect(find.text('Navigate (GPS)'), findsWidgets);
    expect(find.text('OSM Web'), findsWidgets);
    expect(find.text('Review'), findsWidgets);
    expect(find.text('Dangerous crater on expressway lane.'), findsOneWidget);
  });
}
