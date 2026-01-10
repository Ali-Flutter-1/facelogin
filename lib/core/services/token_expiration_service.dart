import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/http_interceptor_service.dart';
import 'package:facelogin/screens/login/login_screen.dart';

/// Service to manage token expiration and auto-logout
class TokenExpirationService {
  static final TokenExpirationService _instance = TokenExpirationService._internal();
  factory TokenExpirationService() => _instance;
  TokenExpirationService._internal();

  Timer? _expirationTimer;
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Set navigator key for global navigation
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  /// Set token expiration time (1 hour from now)
  Future<void> setTokenExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    final expirationTime = DateTime.now().add(const Duration(hours: 1));
    await prefs.setInt('token_expires_at', expirationTime.millisecondsSinceEpoch);
    debugPrint('🔐 [Token Expiration] Set expiration time: ${expirationTime.toIso8601String()}');
    
    // Start checking expiration
    startExpirationCheck();
  }

  /// Get token expiration time
  Future<DateTime?> getTokenExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt('token_expires_at');
    if (expiresAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(expiresAt);
  }

  /// Clear token expiration (on logout)
  Future<void> clearTokenExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token_expires_at');
    _stopExpirationCheck();
    debugPrint('🔐 [Token Expiration] Cleared expiration time');
  }

  /// Check if token is expired
  Future<bool> isTokenExpired() async {
    final expirationTime = await getTokenExpiration();
    if (expirationTime == null) return true;
    return DateTime.now().isAfter(expirationTime);
  }

  /// Start periodic check for token expiration
  void startExpirationCheck() {
    _stopExpirationCheck(); // Stop any existing timer
    
    // Check every 30 seconds
    _expirationTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final isExpired = await isTokenExpired();
      if (isExpired) {
        debugPrint('🔐 [Token Expiration] Token expired - logging out');
        await _handleExpiration();
        timer.cancel();
      }
    });
  }

  /// Stop expiration check timer
  void _stopExpirationCheck() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
  }

  /// Handle token expiration - logout user
  Future<void> _handleExpiration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();

      // Clear tokens and expiration
      await prefs.remove(AppConstants.accessTokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
      await prefs.remove('token_expires_at');
      await secureStorage.delete(key: 'e2e_ku_session');
      
      debugPrint('🔐 [Token Expiration] Cleared tokens due to expiration');

      // Navigate to login screen
      final navigatorContext = navigatorKey?.currentContext;
      
      if (navigatorContext != null && navigatorContext.mounted) {
        // Close any open dialogs
        try {
          Navigator.of(navigatorContext).popUntil((route) => route.isFirst || !route.willHandlePopInternally);
        } catch (e) {
          debugPrint('🔐 [Token Expiration] Error closing dialogs: $e');
        }
        
        // Navigate to login screen
        Navigator.of(navigatorContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
          (route) => false,
        );
        debugPrint('🔐 [Token Expiration] Navigated to login screen');
      } else {
        debugPrint('🔐 [Token Expiration] No context available for navigation');
      }
    } catch (e) {
      debugPrint('🔐 [Token Expiration] Error during expiration logout: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _stopExpirationCheck();
  }
}
