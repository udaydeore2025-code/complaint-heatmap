import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../home/screens/home_feed_screen.dart';
import 'email_login_screen.dart';

class AuthGate extends StatefulWidget {
  final AuthRepository? authRepository;

  const AuthGate({super.key, this.authRepository});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthRepository _authRepository;
  UserProfile? _userProfile;
  bool _isLoadingProfile = true;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _checkInitialSession();
  }

  void _checkInitialSession() {
    final user = _authRepository.currentUser;
    if (user != null) {
      _loadUserProfile(user.id);
    } else {
      setState(() {
        _isLoadingProfile = false;
        _userProfile = null;
      });
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final profile = await _authRepository.fetchUserProfile(userId);
      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        _isLoadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileError = 'Unable to load profile. Please tap retry.';
        _isLoadingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authRepository.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? _authRepository.currentUser;

        // User is not signed in
        if (session == null && _authRepository.currentUser == null) {
          return EmailLoginScreen(
            authRepository: _authRepository,
            onAuthSuccess: () {
              final user = _authRepository.currentUser;
              if (user != null) {
                _loadUserProfile(user.id);
              }
            },
          );
        }

        // User is signed in, check profile loading
        if (_isLoadingProfile) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryColor),
                  SizedBox(height: 16),
                  Text(
                    'Loading CivicConnect profile...',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (_profileError != null || _userProfile == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppTheme.priorityCritical,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _profileError ?? 'Failed to load user profile.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        final user = _authRepository.currentUser;
                        if (user != null) {
                          _loadUserProfile(user.id);
                        }
                      },
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _authRepository.signOut(),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Secure database role routing:
        // Never rely on client-side state. Role is read strictly from profiles table.
        if (_userProfile!.isAdmin) {
          return AdminDashboardScreen(
            profile: _userProfile!,
            authRepository: _authRepository,
          );
        } else {
          return HomeFeedScreen(
            profile: _userProfile!,
            authRepository: _authRepository,
          );
        }
      },
    );
  }
}
