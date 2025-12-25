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
        
        // Check for pairing requirement in login response FIRST (before saving tokens)
        // The server returns pairing info in the login response when pairing is needed
        // Structure: {success: true, data: {is_new_user: false, pairingRequired: true, ...}}
        final loginData = result.data!.data;
        debugPrint('🔗 [AUTH] Login data type: ${loginData.runtimeType}');
        debugPrint('🔗 [AUTH] Full login data: $loginData');
        
        if (loginData != null && loginData is Map<String, dynamic>) {
          // Handle boolean values that might come as strings or booleans
          final isNewUserValue = loginData['is_new_user'];
          final pairingRequiredValue = loginData['pairingRequired'];
          
          debugPrint('🔗 [AUTH] Raw is_new_user value: $isNewUserValue (type: ${isNewUserValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw pairingRequired value: $pairingRequiredValue (type: ${pairingRequiredValue.runtimeType})');
          final e2eStatus = loginData['e2e_status']?.toString();
          final e2eReason = loginData['e2e_reason']?.toString();
          final e2eScenario = loginData['e2e_scenario']?.toString();
          final e2eMessage = loginData['e2e_message']?.toString();
          final pairingOtp = loginData['pairingOtp']?.toString();
          
          // Convert to boolean (handle both bool and string "true"/"false")
          bool? isNewUser;
          if (isNewUserValue is bool) {
            isNewUser = isNewUserValue;
          } else if (isNewUserValue is String) {
            isNewUser = isNewUserValue.toLowerCase() == 'true';
          } else if (isNewUserValue != null) {
            // Handle other types (int: 0=false, 1=true)
            isNewUser = isNewUserValue.toString().toLowerCase() == 'true';
          }
          
          debugPrint('🔗 [AUTH] Parsed is_new_user: $isNewUser (from raw: $isNewUserValue, type: ${isNewUserValue.runtimeType})');
          
          bool? pairingRequired;
          if (pairingRequiredValue is bool) {
            pairingRequired = pairingRequiredValue;
          } else if (pairingRequiredValue is String) {
            pairingRequired = pairingRequiredValue.toLowerCase() == 'true';
          }
          
          debugPrint('🔗 [AUTH] Login response - is_new_user: $isNewUser (raw: $isNewUserValue)');
          debugPrint('🔗 [AUTH] Login response - pairingRequired: $pairingRequired (raw: $pairingRequiredValue)');
          debugPrint('🔗 [AUTH] Login response - e2e_status: $e2eStatus');
          debugPrint('🔗 [AUTH] Login response - e2e_reason: $e2eReason');
          debugPrint('🔗 [AUTH] Login response - e2e_scenario: $e2eScenario');
          debugPrint('🔗 [AUTH] Login response - pairingOtp: $pairingOtp');
          
          // Check if pairing is required: existing user (is_new_user=false) AND 
          // (e2e_reason="NEW_DEVICE_NEEDS_PAIRING" OR e2e_scenario="EXISTING_USER_NEEDS_PAIRING")
          final needsPairing = (isNewUser == false && 
              (e2eReason == 'NEW_DEVICE_NEEDS_PAIRING' || 
               e2eScenario == 'EXISTING_USER_NEEDS_PAIRING'));
          
          debugPrint('🔗 [AUTH] Needs pairing check: $needsPairing');
          debugPrint('🔗 [AUTH] Condition: is_new_user=$isNewUser, e2e_reason=$e2eReason, e2e_scenario=$e2eScenario');
          
          if (needsPairing) {
            debugPrint('🔗 [AUTH] ✅ Pairing required detected! Showing QR code dialog');
            // Save tokens first so we can use them for pairing request
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(AppConstants.accessTokenKey, accessToken!);
            await prefs.setString(AppConstants.refreshTokenKey, result.data!.refreshToken!);
            return AuthResult.pairingRequired(e2eMessage ?? 'Device pairing required');
          } else {
            debugPrint('🔗 [AUTH] ❌ Pairing NOT required in login response - continuing normal login');
          }
        } else {
          debugPrint('🔗 [AUTH] ⚠️ Login data is null or not a Map - will check bootstrap response');
        }
        
        // Save tokens to SharedPreferences (needed for bootstrap call)
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

        // DOUBLE CHECK: Re-check pairing requirement after token save (in case we missed it earlier)
        // This is a safety check to prevent direct login when pairing is required
        final loginDataRecheck = result.data!.data;
        if (loginDataRecheck != null && loginDataRecheck is Map<String, dynamic>) {
          final isNewUserRecheck = loginDataRecheck['is_new_user'];
          final pairingRequiredRecheck = loginDataRecheck['pairingRequired'];
          
          bool? isNewUserBool;
          if (isNewUserRecheck is bool) {
            isNewUserBool = isNewUserRecheck;
          } else if (isNewUserRecheck is String) {
            isNewUserBool = isNewUserRecheck.toLowerCase() == 'true';
          } else if (isNewUserRecheck != null) {
            // Handle other types (int: 0=false, 1=true)
            isNewUserBool = isNewUserRecheck.toString().toLowerCase() == 'true';
          }
          
          debugPrint('🔗 [AUTH] Re-check parsed is_new_user: $isNewUserBool (from raw: $isNewUserRecheck, type: ${isNewUserRecheck.runtimeType})');
          
          bool? pairingRequiredBool;
          if (pairingRequiredRecheck is bool) {
            pairingRequiredBool = pairingRequiredRecheck;
          } else if (pairingRequiredRecheck is String) {
            pairingRequiredBool = pairingRequiredRecheck.toLowerCase() == 'true';
          }
          
          final e2eReasonRecheck = loginDataRecheck['e2e_reason']?.toString();
          final e2eScenarioRecheck = loginDataRecheck['e2e_scenario']?.toString();
          final e2eMessageRecheck = loginDataRecheck['e2e_message']?.toString();
          
          // Re-check: existing user (is_new_user=false) AND needs pairing
          final needsPairingRecheck = (isNewUserBool == false && 
              (e2eReasonRecheck == 'NEW_DEVICE_NEEDS_PAIRING' || 
               e2eScenarioRecheck == 'EXISTING_USER_NEEDS_PAIRING'));
          
          if (needsPairingRecheck) {
            debugPrint('🔗 [AUTH] ⚠️ Pairing required detected in RE-CHECK! Blocking direct login.');
            debugPrint('🔗 [AUTH] Re-check condition: is_new_user=$isNewUserBool, e2e_reason=$e2eReasonRecheck, e2e_scenario=$e2eScenarioRecheck');
            return AuthResult.pairingRequired(e2eMessageRecheck ?? 'Device pairing required');
          }
        }

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

        // CRITICAL: Check if pairing is required (E2E set up on another device)
        // This check MUST happen even if login response didn't have pairing fields
        // Bootstrap response is the authoritative source for pairing requirement
        if (e2eResult.needsPairing) {
          print('🔗 E2E Pairing Required (from bootstrap response)');
          debugPrint('🔗 [AUTH] E2E encryption is set up on another device');
          debugPrint('🔗 [AUTH] E2E error message: ${e2eResult.error}');
          debugPrint('🔗 [AUTH] Bootstrap detected pairing requirement - blocking direct login');
          // Return special result indicating pairing is needed
          // This will trigger QR code dialog even if login response didn't have pairing fields
          return AuthResult.pairingRequired(e2eResult.error ?? 'Device pairing required');
        }

        // SECURITY: Verify E2E keys are properly set up before allowing login
        final hasE2EKeys = await _e2eService.hasE2EKeys();
        final hasSessionKu = await _e2eService.getSessionKu() != null;
        
        debugPrint('🔐 [AUTH] E2E Keys Check - SKd exists: $hasE2EKeys, Ku in session: $hasSessionKu');
        
        if (!e2eResult.isSuccess) {
          print('🔐 E2E Setup: Failed - ${e2eResult.error}');
          debugPrint('⚠️ [AUTH] E2E setup failed: ${e2eResult.error}');
          
          // SECURITY: Block login if keys are missing (user cleared cache or reinstalled app)
          if (!hasE2EKeys) {
            debugPrint('🔐 [AUTH] ⚠️ SECURITY: E2E keys missing - blocking login');
            debugPrint('🔐 [AUTH] User must complete E2E setup (registration or pairing)');
            
            // Check if this is a new user (should register) or existing user (needs pairing)
            final loginData = result.data!.data;
            bool? isNewUser;
            
            if (loginData != null && loginData is Map<String, dynamic>) {
              final isNewUserValue = loginData['is_new_user'];
              if (isNewUserValue is bool) {
                isNewUser = isNewUserValue;
              } else if (isNewUserValue is String) {
                isNewUser = isNewUserValue.toLowerCase() == 'true';
              }
              
              // Also check bootstrap response for pairing requirement
              if (e2eResult.needsPairing || 
                  (e2eResult.error?.contains('needs to be paired') ?? false)) {
                debugPrint('🔐 [AUTH] Bootstrap indicates pairing required - forcing pairing');
                return AuthResult.pairingRequired(
                  e2eResult.error ?? 'Device pairing required. Please scan QR code or enter OTP.'
                );
              }
              
              // If existing user but keys missing, force pairing
              if (isNewUser == false) {
                debugPrint('🔐 [AUTH] Existing user with missing keys - forcing pairing');
                return AuthResult.pairingRequired(
                  'E2E keys not found. Device pairing required. Please scan QR code or enter OTP.'
                );
              }
            }
            
            // If bootstrap says pairing needed, use that
            if (e2eResult.needsPairing) {
              debugPrint('🔐 [AUTH] Bootstrap response indicates pairing required');
              return AuthResult.pairingRequired(
                e2eResult.error ?? 'Device pairing required. Please scan QR code or enter OTP.'
              );
            }
            
            // New user or unknown - force registration
            debugPrint('🔐 [AUTH] Keys missing - forcing E2E registration');
            return AuthResult.error(
              'E2E encryption setup required. Please try logging in again to complete setup.'
            );
          }
          
          // Keys exist but bootstrap failed - this might be a temporary server issue
          // Still block login if session key (Ku) is missing
          if (!hasSessionKu) {
            debugPrint('🔐 [AUTH] ⚠️ SECURITY: Session key (Ku) missing - blocking login');
            return AuthResult.error(
              'E2E session not initialized. Please try logging in again.'
            );
          }
          
          debugPrint('⚠️ [AUTH] E2E bootstrap failed but keys exist - allowing login (non-critical)');
        } else {
          print('🔐 E2E Setup: Success ✓');
          debugPrint('✅ [AUTH] E2E encryption successfully initialized');
          print('🔐 E2E Keys: SKd (Device Key) stored locally, Ku (User Key) in session');
          print('🔐 E2E Security: Ku and SKd NEVER sent to server in plaintext');
          
          // Final verification: ensure both keys are present
          // Add small delay to avoid race condition (keys might be saving)
          await Future.delayed(const Duration(milliseconds: 100));
          
          // Re-check keys after delay
          final finalHasE2EKeys = await _e2eService.hasE2EKeys();
          final finalHasSessionKu = await _e2eService.getSessionKu() != null;
          
          if (!finalHasE2EKeys || !finalHasSessionKu) {
            debugPrint('🔐 [AUTH] ⚠️ SECURITY: Keys not properly stored after setup - blocking login');
            debugPrint('🔐 [AUTH] Final check - SKd: $finalHasE2EKeys, Ku: $finalHasSessionKu');
            return AuthResult.error(
              'E2E keys setup incomplete. Please try logging in again.'
            );
          }
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

