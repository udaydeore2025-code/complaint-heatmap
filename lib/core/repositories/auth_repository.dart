import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';

class AuthRepository {
  final SupabaseClient? clientOverride;

  AuthRepository({this.clientOverride});

  SupabaseClient get client => clientOverride ?? SupabaseService.client;

  Stream<AuthState> get onAuthStateChange => client.auth.onAuthStateChange;

  User? get currentUser => client.auth.currentUser;

  Future<void> sendOtp({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    await client.auth.signInWithOtp(
      email: cleanEmail,
      shouldCreateUser: true,
    );
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanToken = token.trim();

    // 1. Try OtpType.email (login OTP)
    try {
      final response = await client.auth.verifyOTP(
        email: cleanEmail,
        token: cleanToken,
        type: OtpType.email,
      );
      if (response.user != null) {
        await _ensureProfileExists(response.user!);
      }
      return response;
    } on AuthException catch (e) {
      debugPrint('verifyOtp OtpType.email attempt: ${e.message}');
    }

    // 2. Try OtpType.signup (new registration confirmation OTP)
    try {
      final response = await client.auth.verifyOTP(
        email: cleanEmail,
        token: cleanToken,
        type: OtpType.signup,
      );
      if (response.user != null) {
        await _ensureProfileExists(response.user!);
      }
      return response;
    } on AuthException catch (e) {
      debugPrint('verifyOtp OtpType.signup attempt: ${e.message}');
    }

    // 3. Fallback to OtpType.magiclink
    final response = await client.auth.verifyOTP(
      email: cleanEmail,
      token: cleanToken,
      type: OtpType.magiclink,
    );
    if (response.user != null) {
      await _ensureProfileExists(response.user!);
    }
    return response;
  }

  Future<void> _ensureProfileExists(User user) async {
    try {
      final existing = await client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existing == null) {
        await client.from(SupabaseConstants.profilesTable).insert({
          'id': user.id,
          'email': user.email ?? '',
          'name': user.email != null ? user.email!.split('@').first : 'Citizen',
          'role': 'citizen',
        });
      }
    } catch (e) {
      debugPrint('Error ensuring profile exists: $e');
    }
  }

  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final data = await client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) {
        // Fallback: create if missing
        final user = client.auth.currentUser;
        if (user != null && user.id == userId) {
          await _ensureProfileExists(user);
          return await fetchUserProfile(userId);
        }
        return null;
      }

      return UserProfile.fromJson(data);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<void> updateUserProfileName(String userId, String name) async {
    await client
        .from(SupabaseConstants.profilesTable)
        .update({'name': name.trim()})
        .eq('id', userId);
  }

  Future<void> updateUserRole(String userId, String role) async {
    await client
        .from(SupabaseConstants.profilesTable)
        .update({'role': role})
        .eq('id', userId);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
