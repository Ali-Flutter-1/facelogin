import 'dart:convert';

import 'package:facelogin/screens/login/login_screen.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main/main_screen.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _secureStorage = const FlutterSecureStorage(); // For E2E keys only

  @override
  void initState() {
    super.initState();
    _checkTokenAndNavigate();
  }

  Future<void> _checkTokenAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString("access_token");

    await Future.delayed(const Duration(seconds: 4)); // smooth transition

      if (accessToken != null && accessToken.isNotEmpty) {
        final isExpired = _isTokenExpired(accessToken);
        if (!isExpired) {
          // SECURITY: Verify E2E keys are set up before allowing navigation
          // This prevents bypassing pairing by restarting the app
          final e2eService = E2EService();
          final hasE2EKeys = await e2eService.hasE2EKeys();
          final hasSessionKu = await e2eService.getSessionKu() != null;

          debugPrint('🔐 [SPLASH] E2E Keys Check - SKd: $hasE2EKeys, Ku: $hasSessionKu');

          if (hasE2EKeys && hasSessionKu) {
            // Both keys present - verify device owner matches and check if pairing is needed
            try {
              // Extract user ID from token
              final parts = accessToken.split('.');
              if (parts.length == 3) {
                final payload = jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                );
                final currentUserId = payload['sub']?.toString();
                
                if (currentUserId != null) {
                  final deviceOwner = await e2eService.getDeviceOwnerUserId();
                  if (deviceOwner != null && deviceOwner != currentUserId) {
                    // Different user - clear tokens and force login
                    debugPrint('🔐 [SPLASH] ⚠️ SECURITY: Token user ($currentUserId) != device owner ($deviceOwner)');
                    debugPrint('🔐 [SPLASH] Clearing tokens and forcing login');
                    await prefs.remove('access_token');
                    await prefs.remove('refresh_token');
                    await _secureStorage.delete(key: 'e2e_ku_session');
                    // Navigate to login
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
                    );
                    return;
                  }
                  
                  // Verify with server that pairing/recovery is not needed
                  // Call bootstrap to check if device needs pairing
                  final bootstrapResult = await e2eService.bootstrapForLogin(accessToken);
                  
                  if (bootstrapResult.needsPairing) {
                    // Device needs pairing - clear session and force login flow
                    debugPrint('🔐 [SPLASH] Device needs pairing - forcing login flow');
                    await _secureStorage.delete(key: 'e2e_ku_session'); // Clear session key
                    // Keep tokens but clear session - login will handle pairing
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
                    );
                    return;
                  }
                  
                  if (!bootstrapResult.isSuccess) {
                    // Bootstrap failed - might need recovery, force login
                    debugPrint('🔐 [SPLASH] Bootstrap check failed - forcing login flow');
                    await _secureStorage.delete(key: 'e2e_ku_session');
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
                    );
                    return;
                  }
                }
              }
            } catch (e) {
              debugPrint('🔐 [SPLASH] Error checking device status: $e');
              // On error, force login to be safe
              await _secureStorage.delete(key: 'e2e_ku_session');
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
              );
              return;
            }
            
            // Both keys present, device owner matches, and server confirms no pairing needed
            // Safe to navigate to profile
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainScreen()),
            );
            return;
          } else {
            // E2E keys missing - clear tokens and force login (which will trigger pairing)
            debugPrint('🔐 [SPLASH] ⚠️ SECURITY: E2E keys missing - clearing tokens and forcing login');
            debugPrint('🔐 [SPLASH] This prevents bypassing pairing by restarting app');
            await prefs.remove('access_token');
            await prefs.remove('refresh_token');
            await _secureStorage.delete(key: 'e2e_ku_session'); // Clear session key
            // Note: SKd might exist from incomplete pairing - that's OK, will be overwritten
          }
        } else {
          // Token expired - clear only auth tokens, preserve E2E keys (SKd) and device ID
          await prefs.remove('access_token');
          await prefs.remove('refresh_token');
          await _secureStorage.delete(key: 'e2e_ku_session'); // Clear session key only
          // DO NOT delete: e2e_skd, device_id, device_owner_user_id
        }
      }


    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
    );
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );

      final exp = payload['exp'];
      if (exp == null) return true;

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      debugPrint("JWT decode error: $e");
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0A0E21),
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/valydlogo.png',
                width: 150,
                height: 150,
              ),


              const SizedBox(height: 30),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  "The AI era is drowning in noise",
                  style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 10),

              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 12.0),
                child: Text(
                  "Valyd verifies identity,credentials, and responses—instantly—so you can trust every insight and eliminate friction",
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}