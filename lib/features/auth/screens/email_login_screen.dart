import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_logo.dart';

class EmailLoginScreen extends StatefulWidget {
  final AuthRepository? authRepository;
  final VoidCallback? onAuthSuccess;

  const EmailLoginScreen({
    super.key,
    this.authRepository,
    this.onAuthSuccess,
  });

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  late final AuthRepository _authRepository;
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passkeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Mode: 'citizen' or 'admin'
  String _selectedRoleMode = 'citizen';

  bool _isPasskeyVisible = false;
  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Countdown timer for Resend OTP
  Timer? _resendTimer;
  int _secondsRemaining = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passkeyController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _canResend = true;
        });
      }
    });
  }

  String _formatErrorMessage(Object error) {
    final str = error.toString().toLowerCase();
    if (str.contains('failed host lookup') ||
        str.contains('socketexception') ||
        str.contains('no address associated with hostname') ||
        str.contains('clientexception')) {
      return 'Cannot reach Supabase backend (Failed host lookup). Free-tier Supabase projects are automatically paused after 7 days of inactivity. Please restore/unpause your project at https://supabase.com/dashboard or check your internet connection.';
    }
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('socketexception')) {
        return 'Cannot reach Supabase backend. Please restore/unpause your project in the Supabase dashboard.';
      } else if (msg.contains('invalid') || msg.contains('token')) {
        return 'Invalid OTP code. Please verify the code and try again.';
      } else if (msg.contains('expired')) {
        return 'OTP has expired. Please request a new code.';
      } else if (msg.contains('rate limit')) {
        return 'Email rate limit reached. Please wait a moment or configure custom SMTP in Supabase.';
      } else if (msg.contains('magic link') || msg.contains('unexpected_failure')) {
        return 'Supabase email service could not deliver OTP. Please check Supabase Auth SMTP settings or rate limits.';
      }
      return error.message;
    }
    if (str.contains('socket') || str.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authRepository.sendOtp(email: _emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isOtpSent = true;
        _isLoading = false;
      });
      _startResendCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _formatErrorMessage(e);
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final token = _otpController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the 6-digit OTP code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _authRepository.setActivePortalRole(_selectedRoleMode);

      await _authRepository.verifyOtp(
        email: _emailController.text.trim(),
        token: token,
        portalRole: _selectedRoleMode,
      );

      // If user selected Admin portal, enforce strict administrative authorization
      final currentUser = _authRepository.currentUser;
      if (currentUser != null) {
        if (_selectedRoleMode == 'admin') {
          if (_passkeyController.text.trim() == AppConstants.municipalAdminPasskey) {
            await _authRepository.updateUserRole(currentUser.id, 'admin');
          } else {
            final profile = await _authRepository.fetchUserProfile(currentUser.id);
            if (profile != null && profile.isAdmin) {
              await _authRepository.updateUserRole(currentUser.id, 'admin');
            } else if (mounted) {
              final passkeyController = TextEditingController();
              final passkeyFormKey = GlobalKey<FormState>();

              final isAuthorized = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppTheme.adminAtlasRed),
                      SizedBox(width: 8),
                      Text('Staff Clearance Required', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  content: Form(
                    key: passkeyFormKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account: ${currentUser.email}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'This account is registered as a Citizen. To access the Municipal Administrative Portal, enter the official Municipal Staff Passkey:',
                          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: passkeyController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Municipal Staff Passkey',
                            hintText: 'Enter passkey (CIVIC-ADMIN-2026)',
                            prefixIcon: Icon(Icons.key_outlined, color: AppTheme.adminAtlasRed),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Passkey is required';
                            }
                            if (val.trim() != AppConstants.municipalAdminPasskey) {
                              return 'Invalid municipal passkey';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.adminBisque,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.adminAtlasRed.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'Citizens cannot switch to administrative without official municipal staff clearance.',
                            style: TextStyle(fontSize: 11, color: AppTheme.adminAtlasRedDark, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.adminAtlasRed,
                        foregroundColor: AppTheme.adminBisque,
                      ),
                      onPressed: () {
                        if (passkeyFormKey.currentState!.validate()) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: const Text('Verify & Authorize'),
                    ),
                  ],
                ),
              );

              if (isAuthorized == true) {
                await _authRepository.updateUserRole(currentUser.id, 'admin');
              } else {
                // Strictly deny access and sign out
                await _authRepository.signOut();
                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                  _isOtpSent = false;
                  _errorMessage = 'Access Denied: This account is not authorized as a Municipal Administrator. Citizen accounts cannot access or switch to the administrative portal.';
                });
                return;
              }
            }
          }
        } else {
          // Explicit Citizen login: ALWAYS ensure citizen role and citizen portal
          await _authRepository.updateUserRole(currentUser.id, 'citizen');
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      widget.onAuthSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _formatErrorMessage(e);
      });
    }
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authRepository.sendOtp(email: _emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _startResendCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new OTP has been sent to your email.'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _formatErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdminMode = _selectedRoleMode == 'admin';

    // Dynamic Theme Color Mapping from user palettes:
    // Admin: Atlas Red (#82193A) & Bisque (#FEE3C5)
    // Citizen: Moonstone (#4C9DB0) & Vanilla (#FFEBAF)
    final primaryColor = isAdminMode ? AppTheme.adminAtlasRed : AppTheme.citizenMoonstone;
    final accentColor = isAdminMode ? AppTheme.adminBisque : AppTheme.citizenVanilla;
    final darkTextColor = isAdminMode ? AppTheme.adminAtlasRedDark : AppTheme.citizenMoonstoneDark;
    final scaffoldBg = isAdminMode ? const Color(0xFFFFFBF6) : const Color(0xFFFFFDF8);
    final buttonTextColor = isAdminMode ? AppTheme.adminBisque : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          isAdminMode ? 'CivicConnect • Admin Portal' : AppConstants.appName,
          style: TextStyle(
            color: isAdminMode ? AppTheme.adminBisque : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: primaryColor,
        foregroundColor: isAdminMode ? AppTheme.adminBisque : Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: _isOtpSent
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isOtpSent = false;
                    _errorMessage = null;
                    _otpController.clear();
                    _resendTimer?.cancel();
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Portal Switcher: Citizen vs Admin
                if (!_isOtpSent) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _selectedRoleMode = 'citizen'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isAdminMode ? AppTheme.citizenMoonstone : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !isAdminMode
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.citizenMoonstone.withValues(alpha: 0.25),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 18,
                                    color: !isAdminMode ? AppTheme.citizenVanilla : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Citizen Login',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: !isAdminMode ? AppTheme.citizenVanilla : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _selectedRoleMode = 'admin'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isAdminMode ? AppTheme.adminAtlasRed : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: isAdminMode
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.adminAtlasRed.withValues(alpha: 0.25),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.admin_panel_settings,
                                    size: 18,
                                    color: isAdminMode ? AppTheme.adminBisque : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Admin Login',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isAdminMode ? AppTheme.adminBisque : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // App Logo & Role Header
                Center(
                  child: Column(
                    children: [
                      const AppLogo(size: 96, showBadgeBackground: true),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: primaryColor,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAdminMode ? Icons.admin_panel_settings : Icons.verified_user_outlined,
                              size: 15,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isAdminMode ? 'MUNICIPAL ADMIN PORTAL' : 'CIVIC CITIZEN PORTAL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  _isOtpSent
                      ? 'Enter Verification Code'
                      : (isAdminMode ? 'Municipal Administrative Login' : 'Sign in with Email OTP'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isAdminMode ? AppTheme.adminAtlasRedDark : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  _isOtpSent
                      ? 'We sent a verification code to\n${_emailController.text.trim()}'
                      : (isAdminMode
                          ? 'Restricted municipal authority portal for department engineers and grievance officers.'
                          : 'Sign in to report, vote, and track neighborhood civic complaints in your city.'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Error Banner if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(
                        left: BorderSide(color: Color(0xFFDC2626), width: 4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFDC2626),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (!_isOtpSent) ...[
                  // Email Input Field
                  Text(
                    isAdminMode ? 'Administrator Email' : 'Email Address',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: darkTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: isAdminMode ? 'admin@civic.gov' : 'citizen@example.com',
                      prefixIcon: Icon(
                        isAdminMode ? Icons.security : Icons.email_outlined,
                        color: primaryColor,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFDC2626)),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegExp.hasMatch(val.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  if (isAdminMode) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Municipal Staff Passkey',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: darkTextColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passkeyController,
                      obscureText: !_isPasskeyVisible,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter passkey (CIVIC-ADMIN-2026)',
                        prefixIcon: const Icon(Icons.key_outlined, color: AppTheme.adminAtlasRed),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasskeyVisible ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.adminAtlasRed,
                          ),
                          onPressed: () => setState(() => _isPasskeyVisible = !_isPasskeyVisible),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppTheme.adminAtlasRed.withValues(alpha: 0.35)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.adminAtlasRed, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFDC2626)),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                        ),
                      ),
                      validator: (val) {
                        if (!isAdminMode) return null;
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter Municipal Staff Passkey';
                        }
                        if (val.trim() != AppConstants.municipalAdminPasskey) {
                          return 'Invalid passkey. Municipal clearance required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.adminBisque,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.adminAtlasRed.withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: AppTheme.adminAtlasRed),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Staff Passkey: CIVIC-ADMIN-2026',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.adminAtlasRed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Send Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: buttonTextColor,
                      minimumSize: const Size.fromHeight(50),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleSendOtp,
                    child: _isLoading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: buttonTextColor,
                            ),
                          )
                        : Text(isAdminMode ? 'SEND ADMIN OTP' : 'SEND OTP'),
                  ),
                ] else ...[
                  // OTP Input Field
                  Text(
                    'Enter OTP',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: darkTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: '______',
                      hintStyle: const TextStyle(
                        letterSpacing: 8,
                        color: Color(0xFF94A3B8),
                      ),
                      counterText: '',
                      prefixIcon: Icon(Icons.pin_outlined, color: primaryColor),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Verify Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: buttonTextColor,
                      minimumSize: const Size.fromHeight(50),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleVerifyOtp,
                    child: _isLoading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: buttonTextColor,
                            ),
                          )
                        : Text(isAdminMode ? 'VERIFY ADMIN OTP' : 'VERIFY OTP'),
                  ),
                  const SizedBox(height: 16),

                  // Resend countdown
                  Center(
                    child: _canResend
                        ? TextButton.icon(
                            onPressed: _isLoading ? null : _handleResendOtp,
                            icon: Icon(Icons.refresh, size: 18, color: primaryColor),
                            label: Text(
                              'Resend OTP',
                              style: TextStyle(fontWeight: FontWeight.w600, color: primaryColor),
                            ),
                          )
                        : Text(
                            'Resend code in ${_secondsRemaining}s',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!isAdminMode && !_isOtpSent) ...[
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                      label: const Text('Municipal Staff? Switch to Administrative Login'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.citizenMoonstoneDark,
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedRoleMode = 'admin';
                          _errorMessage = null;
                        });
                      },
                    ),
                  ),
                ],
                if (isAdminMode && !_isOtpSent) ...[
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Return to Citizen Login'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.adminAtlasRed,
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedRoleMode = 'citizen';
                          _errorMessage = null;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
