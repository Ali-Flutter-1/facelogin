import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/token_expiration_service.dart';
import 'package:facelogin/screens/login/login_screen.dart';

/// Global HTTP interceptor service that handles 401 errors
/// Automatically logs out user (clears tokens) but preserves E2E keys (SKd)
class HttpInterceptorService {
  static final HttpInterceptorService _instance = HttpInterceptorService._internal();
  factory HttpInterceptorService() => _instance;
  HttpInterceptorService._internal();

  bool _isHandling401 = false;
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Set navigator key for global navigation (call from main.dart)
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  /// Handle 401 error - logout user but keep E2E keys
  /// This can be called from anywhere in the app
  Future<void> handle401Error(BuildContext? context) async {
    // Prevent multiple simultaneous 401 handlers
    if (_isHandling401) {
      debugPrint('🔐 [401 Handler] Already handling 401, skipping...');
      return;
    }

    _isHandling401 = true;
    debugPrint('🔐 [401 Handler] Session expired - logging out (preserving E2E keys)');

    try {
      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();

      // Clear only auth tokens, preserve E2E keys (SKd) and device ID
      await prefs.remove(AppConstants.accessTokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
      await secureStorage.delete(key: 'e2e_ku_session'); // Clear session key only
      
      // Clear token expiration
      final tokenExpirationService = TokenExpirationService();
      await tokenExpirationService.clearTokenExpiration();
      
      // DO NOT delete: e2e_skd, device_id, device_owner_user_id
      debugPrint('🔐 [401 Handler] Cleared auth tokens and session key, kept device key (SKd)');

      // Close any open dialogs first (like loading dialogs)
      final navigatorContext = context ?? navigatorKey?.currentContext;
      
      if (navigatorContext != null && navigatorContext.mounted) {
        // Pop any open dialogs (like loading indicators)
        try {
          Navigator.of(navigatorContext).popUntil((route) => route.isFirst || !route.willHandlePopInternally);
        } catch (e) {
          debugPrint('🔐 [401 Handler] Error closing dialogs: $e');
        }
        
        // Navigate to login screen
        Navigator.of(navigatorContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
          (route) => false,
        );
        debugPrint('🔐 [401 Handler] Navigated to login screen');
      } else {
        debugPrint('🔐 [401 Handler] No context available for navigation');
      }
    } catch (e) {
      debugPrint('🔐 [401 Handler] Error during logout: $e');
    } finally {
      _isHandling401 = false;
    }
  }

  /// Check HTTP response for 401 and handle it
  /// Call this after any HTTP request
  Future<void> checkResponse(http.Response response, BuildContext? context) async {
    if (response.statusCode == 401) {
      debugPrint('🔐 [401 Handler] 401 Unauthorized detected in API response');
      await handle401Error(context);
    }
  }
}

/// Helper function to check and handle 401 errors
/// Use this after any HTTP response
Future<void> handle401IfNeeded(http.Response response, BuildContext? context) async {
  await HttpInterceptorService().checkResponse(response, context);
}
