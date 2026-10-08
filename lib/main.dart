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
