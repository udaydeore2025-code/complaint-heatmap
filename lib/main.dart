import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/auth_gate.dart';
import 'features/splash/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase initialization note: $e');
  }

  // Prevent silent blank white screen crashes in release mode
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Rendering Error',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  details.exceptionAsString(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  details.stack?.toString() ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  runApp(const CivicConnectApp());
}

class CivicConnectApp extends StatefulWidget {
  const CivicConnectApp({super.key});

  @override
  State<CivicConnectApp> createState() => _CivicConnectAppState();
}

class _CivicConnectAppState extends State<CivicConnectApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _showSplash
          ? SplashScreen(
              onFinished: () {
                if (mounted) {
                  setState(() {
                    _showSplash = false;
                  });
                }
              },
            )
          : const AuthGate(),
    );
  }
}
