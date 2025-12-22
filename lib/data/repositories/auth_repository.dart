import 'dart:typed_data';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/data/models/login_response_model.dart';
import 'package:facelogin/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {
  final AuthService _authService;
  final E2EService _e2eService;

  AuthRepository({
    AuthService? authService,
    E2EService? e2eService,
  })  : _authService = authService ?? AuthService(),
        _e2eService = e2eService ?? E2EService();

  /// Login or register with face image
  /// Automatically handles E2E encryption bootstrap
  Future<AuthResult> loginOrRegister(Uint8List faceImageBytes) async {
    final result = await _authService.loginOrRegister(faceImageBytes);

    if (result.isSuccess && result.data != null) {
      try {
        final accessToken = result.data!.accessToken;
        
        // Save tokens to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        debugPrint('💾 Saving tokens to SharedPreferences...');
        
        final accessTokenSaved = await prefs.setString(
          AppConstants.accessTokenKey,
          accessToken!,
        );
        final refreshTokenSaved = await prefs.setString(
          AppConstants.refreshTokenKey,
          result.data!.refreshToken!,
        );

        debugPrint('💾 Token save results: accessToken=$accessTokenSaved, refreshToken=$refreshTokenSaved');

        if (!accessTokenSaved || !refreshTokenSaved) {
          debugPrint('❌ Failed to save tokens to SharedPreferences');
          return AuthResult.error(
            'Login successful but failed to save session. Please try again.',
          );
        }

        // Verify tokens were saved
        final savedAccessToken = prefs.getString(AppConstants.accessTokenKey);
        final savedRefreshToken = prefs.getString(AppConstants.refreshTokenKey);

        debugPrint('💾 Token verification: accessToken=${savedAccessToken != null && savedAccessToken.isNotEmpty}, refreshToken=${savedRefreshToken != null && savedRefreshToken.isNotEmpty}');

        if (savedAccessToken == null || savedAccessToken.isEmpty || 
            savedRefreshToken == null || savedRefreshToken.isEmpty) {
          debugPrint('❌ Token verification failed');
          return AuthResult.error(
            'Login successful but failed to save session. Please try again.',
          );
        }
        
        debugPrint('✅ Tokens saved and verified successfully');

        // E2E Encryption Bootstrap
        // Check if this is a new user (registration) or existing user (login)
        print('🔐 E2E Setup: Starting...');
        final hasExistingKeys = await _e2eService.hasE2EKeys();
        print('🔐 E2E Keys Present: $hasExistingKeys');
        
        E2EBootstrapResult e2eResult;
        if (hasExistingKeys) {
          // Existing user - login flow (Phase 3.4-3.6)
          // This will automatically fall back to registration if server says E2E_NOT_SETUP
          print('🔐 E2E Flow: LOGIN');
          e2eResult = await _e2eService.bootstrapForLogin(accessToken!);
        } else {
          // New user - registration flow (Phase 2: E2E Key Bootstrap)
          print('🔐 E2E Flow: REGISTRATION');
          e2eResult = await _e2eService.bootstrapForRegistration(accessToken!);
        }

        // Check if pairing is required (E2E set up on another device)
        if (e2eResult.needsPairing) {
          print('🔗 E2E Pairing Required');
          debugPrint('🔗 [AUTH] E2E encryption is set up on another device');
          // Return special result indicating pairing is needed
          return AuthResult.pairingRequired(e2eResult.error ?? 'Device pairing required');
        }

        if (!e2eResult.isSuccess) {
          print('🔐 E2E Setup: Failed - ${e2eResult.error}');
          debugPrint('⚠️ [AUTH] E2E setup failed: ${e2eResult.error}');
          debugPrint('⚠️ [AUTH] Continuing login anyway (E2E failure non-blocking)');
          // Continue anyway - E2E failure shouldn't block login
          // Common reasons: server error, network issues
        } else {
          print('🔐 E2E Setup: Success ✓');
          debugPrint('✅ [AUTH] E2E encryption successfully initialized');
          print('🔐 E2E Keys: SKd (Device Key) stored locally, Ku (User Key) in session');
          print('🔐 E2E Security: Ku and SKd NEVER sent to server in plaintext');
        }

        return AuthResult.success(result.data!);
      } catch (e) {
        debugPrint('❌ Error in loginOrRegister: $e');
        return AuthResult.error(
          'Login successful but failed to save session. Please try again.',
        );
      }
    } else {
      return AuthResult.error(result.error ?? 'Login failed');
    }
  }

  /// Get access token from storage
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.accessTokenKey);
  }

  /// Get refresh token from storage
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.refreshTokenKey);
  }

  /// Clear all stored tokens and E2E session keys
  /// IMPORTANT: This does NOT clear SKd (Device Private Key) or device ID
  /// Only clears: access token, refresh token, and session Ku
  /// SKd remains on device for future logins
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.accessTokenKey);
    await prefs.remove(AppConstants.refreshTokenKey);
    // Clear E2E session key (Ku) only - SKd stays on device
    await _e2eService.clearSessionKeys();
    debugPrint('🔐 Cleared auth tokens and session key, kept device key (SKd)');
  }

  /// Clear all data including E2E keys (ONLY for account deletion)
  /// WARNING: This permanently deletes SKd - device will need re-registration
  /// Should NOT be called during normal logout
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.accessTokenKey);
    await prefs.remove(AppConstants.refreshTokenKey);
    await _e2eService.clearAllKeys();
    debugPrint('⚠️ Cleared all data including E2E keys - device needs re-registration');
  }
}

/// Auth result class
class AuthResult {
  final LoginResponseModel? data;
  final String? error;
  final bool requiresPairing;

  AuthResult.success(this.data) 
      : error = null, 
        requiresPairing = false;
  
  AuthResult.error(this.error) 
      : data = null, 
        requiresPairing = false;
  
  AuthResult.pairingRequired(this.error)
      : data = null,
        requiresPairing = true;

  bool get isSuccess => data != null;
  bool get isError => error != null;
  bool get needsPairing => requiresPairing;
}

