import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../home/screens/home_feed_screen.dart';
import 'email_login_screen.dart';

class AuthGate extends StatefulWidget {
  final AuthRepository? authRepository;
  final ComplaintRepository? complaintRepository;

  const AuthGate({
    super.key,
    this.authRepository,
    this.complaintRepository,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthRepository _authRepository;
  UserProfile? _userProfile;
  bool _isLoadingProfile = true;
  String? _profileError;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _initAuthListener();
    _checkInitialSession();
  }

  void _initAuthListener() {
    _authSubscription = _authRepository.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session == null) {
        if (mounted) {
          setState(() {
            _userProfile = null;
            _isLoadingProfile = false;
            _profileError = null;
          });
        }
      } else {
        if (mounted && (_userProfile == null || _userProfile!.id != session.user.id)) {
          _loadUserProfile(session.user.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
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
      if (profile != null) {
        UserProfile effectiveProfile = profile;
        if (_authRepository.activePortalRole == 'citizen' && profile.isAdmin) {
          effectiveProfile = profile.copyWith(role: 'citizen');
        } else if (_authRepository.activePortalRole == 'admin' && !profile.isAdmin) {
          effectiveProfile = profile.copyWith(role: 'admin');
        }
        setState(() {
          _userProfile = effectiveProfile;
          _isLoadingProfile = false;
        });
      } else {
        final user = _authRepository.currentUser;
        if (user != null) {
          final effectiveRole = _authRepository.activePortalRole ??
              (user.userMetadata?['role'] as String?) ??
              'citizen';
          setState(() {
            _userProfile = UserProfile(
              id: user.id,
              email: user.email ?? '',
              name: user.userMetadata?['name'] as String? ??
                  (user.email != null ? user.email!.split('@').first : 'Citizen'),
              role: effectiveRole,
              createdAt: DateTime.now(),
            );
            _isLoadingProfile = false;
          });
        } else {
          setState(() {
            _profileError = 'Session expired. Please sign in again.';
            _isLoadingProfile = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      final user = _authRepository.currentUser;
      if (user != null) {
        final effectiveRole = _authRepository.activePortalRole ??
            (user.userMetadata?['role'] as String?) ??
            'citizen';
        setState(() {
          _userProfile = UserProfile(
            id: user.id,
            email: user.email ?? '',
            name: user.userMetadata?['name'] as String? ??
                (user.email != null ? user.email!.split('@').first : 'Citizen'),
            role: effectiveRole,
            createdAt: DateTime.now(),
          );
          _isLoadingProfile = false;
        });
      } else {
        setState(() {
          _profileError = 'Unable to load profile. Please tap retry.';
          _isLoadingProfile = false;
        });
      }
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
                    'Loading CivicConnect dashboard...',
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
                        } else {
                          _authRepository.signOut();
                        }
                      },
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await _authRepository.signOut();
                        if (!mounted) return;
                        setState(() {
                          _userProfile = null;
                          _profileError = null;
                          _isLoadingProfile = false;
                        });
                      },
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Individual Dashboard Routing:
        // Admin Login -> Municipal Admin Dashboard
        // Citizen Login -> Citizen Dashboard
        final isPortalAdmin = (_authRepository.activePortalRole == 'admin') ||
            (_authRepository.activePortalRole == null && _userProfile!.isAdmin);

        if (isPortalAdmin && _userProfile!.isAdmin) {
          return AdminDashboardScreen(
            profile: _userProfile!,
            authRepository: _authRepository,
          );
        } else {
          return HomeFeedScreen(
            profile: _userProfile!.copyWith(role: 'citizen'),
            authRepository: _authRepository,
            complaintRepository: widget.complaintRepository,
          );
        }
      },
    );
  }
}
