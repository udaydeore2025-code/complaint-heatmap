import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/theme/app_theme.dart';

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
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid') || msg.contains('token')) {
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
    final str = error.toString().toLowerCase();
    if (str.contains('socket') || str.contains('network') || str.contains('failed host lookup')) {
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
                      Icon(Icons.shield_outlined, color: AppTheme.priorityCritical),
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
                            prefixIcon: Icon(Icons.key_outlined),
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
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Citizens cannot switch to administrative without official municipal staff clearance.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
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
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
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

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(isAdminMode ? 'CivicConnect • Admin Portal' : AppConstants.appName),
        backgroundColor: isAdminMode ? const Color(0xFF0F172A) : null,
        foregroundColor: isAdminMode ? Colors.white : null,
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
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
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
                                color: !isAdminMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: !isAdminMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
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
                                    color: !isAdminMode ? AppTheme.primaryColor : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Citizen Login',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: !isAdminMode ? AppTheme.primaryColor : const Color(0xFF64748B),
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
                                color: isAdminMode ? const Color(0xFF0F172A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: isAdminMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
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
                                    color: isAdminMode ? Colors.white : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Admin Login',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isAdminMode ? Colors.white : const Color(0xFF64748B),
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

                // Role Header Icon
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isAdminMode
                          ? const Color(0xFFFEE2E2)
                          : AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isAdminMode ? Icons.admin_panel_settings : Icons.mark_email_read_outlined,
                      color: isAdminMode ? AppTheme.priorityCritical : AppTheme.primaryColor,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Text(
                  _isOtpSent
                      ? 'Enter Verification Code'
                      : (isAdminMode ? 'Municipal Administrative Login' : 'Sign in with Email OTP'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: isAdminMode ? 'admin@civic.gov' : 'citizen@example.com',
                      prefixIcon: Icon(isAdminMode ? Icons.security : Icons.email_outlined),
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
                    const Text(
                      'Municipal Staff Passkey',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passkeyController,
                      obscureText: !_isPasskeyVisible,
                      decoration: InputDecoration(
                        hintText: 'Enter passkey (CIVIC-ADMIN-2026)',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasskeyVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _isPasskeyVisible = !_isPasskeyVisible),
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
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: Color(0xFFDC2626)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Staff Passkey: CIVIC-ADMIN-2026',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Send Button
                  ElevatedButton(
                    style: isAdminMode
                        ? ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                          )
                        : null,
                    onPressed: _isLoading ? null : _handleSendOtp,
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(isAdminMode ? 'SEND ADMIN OTP' : 'SEND OTP'),
                  ),
                ] else ...[
                  // OTP Input Field
                  const Text(
                    'Enter OTP',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: '______',
                      hintStyle: TextStyle(
                        letterSpacing: 8,
                        color: Color(0xFF94A3B8),
                      ),
                      counterText: '',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Verify Button
                  ElevatedButton(
                    style: isAdminMode
                        ? ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                          )
                        : null,
                    onPressed: _isLoading ? null : _handleVerifyOtp,
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
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
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text(
                              'Resend OTP',
                              style: TextStyle(fontWeight: FontWeight.w600),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Citizen Portal is dedicated to neighborhood reporting and community voting. Citizens cannot access municipal administrative functions.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                      label: const Text('Municipal Staff? Switch to Administrative Login'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: Color(0xFFDC2626)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Administrative Portal is strictly restricted to authorized municipal officers. Unauthorized citizen login attempts will be rejected.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Return to Citizen Login'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
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
