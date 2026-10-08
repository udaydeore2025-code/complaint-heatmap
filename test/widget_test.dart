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
import 'package:complaint_heatmap/features/auth/screens/email_login_screen.dart';
import 'package:complaint_heatmap/features/complaints/screens/complaint_details_screen.dart';
import 'package:complaint_heatmap/features/complaints/screens/report_complaint_screen.dart';
import 'package:complaint_heatmap/features/admin/screens/admin_dashboard_screen.dart';
import 'package:complaint_heatmap/features/complaints/screens/my_complaints_screen.dart';
import 'package:complaint_heatmap/features/profile/screens/profile_screen.dart';
import 'package:complaint_heatmap/core/repositories/admin_repository.dart';
import 'package:complaint_heatmap/widgets/complaint_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthRepository extends AuthRepository {
  bool otpSent = false;
  String? sentEmail;

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<void> sendOtp({required String email}) async {
    otpSent = true;
    sentEmail = email;
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
}
