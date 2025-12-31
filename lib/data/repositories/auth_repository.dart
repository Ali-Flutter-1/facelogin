import 'dart:convert';

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
        
        // SECURITY: Enforce one-user-per-device (device ownership)
        // Extract user ID from JWT token and check if user is the device owner
        String? currentUserId;
        try {
          if (accessToken != null) {
            final parts = accessToken!.split('.');
            if (parts.length == 3) {
              final payload = jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              );
              currentUserId = payload['sub']?.toString();
              debugPrint('🔐 [AUTH] Extracted user ID from token: $currentUserId');
            }
          }
        } catch (e) {
          debugPrint('🔐 [AUTH] Failed to extract user ID from token: $e');
        }
        
        // Check if user is the device owner (first user who signed up)
        if (currentUserId != null) {
          final existingOwner = await _e2eService.getDeviceOwnerUserId();
          
          // Check if this is a new user signup (registration)
          // We need to check this BEFORE the pairing check to get is_new_user value
          final loginDataCheck = result.data!.data;
          bool isNewUser = false;
          if (loginDataCheck != null && loginDataCheck is Map<String, dynamic>) {
            final isNewUserValue = loginDataCheck['is_new_user'];
            if (isNewUserValue is bool) {
              isNewUser = isNewUserValue;
            } else if (isNewUserValue is String) {
              isNewUser = isNewUserValue.toLowerCase() == 'true';
            } else if (isNewUserValue != null) {
              isNewUser = isNewUserValue.toString().toLowerCase() == 'true';
            }
          }
          
          debugPrint('🔐 [AUTH] is_new_user: $isNewUser, existingOwner: $existingOwner');
          
          // CRITICAL: Block new signups if device owner exists (unless explicitly new user)
          // This prevents different users from creating accounts on the same device
          if (existingOwner != null) {
            // Device owner exists - check if this is a new user signup
            if (isNewUser == true) {
              // New user signup on device with existing owner
              // This is allowed only if previous account was deleted
              debugPrint('🔐 [AUTH] New user signup detected - clearing old device owner');
              await _e2eService.clearDeviceOwner();
              await _e2eService.setDeviceOwner(currentUserId);
              debugPrint('🔐 [AUTH] New user $currentUserId set as device owner');
            } else {
              // Existing user login or signup without is_new_user flag
              // Check if they're the device owner
              final isOwner = await _e2eService.isDeviceOwner(currentUserId);
              if (!isOwner) {
                // Different user trying to login/signup - BLOCK them
                debugPrint('🔐 [AUTH] ⚠️ SECURITY: User $currentUserId is NOT the device owner');
                debugPrint('🔐 [AUTH] Device owner: $existingOwner, Attempting user: $currentUserId');
                debugPrint('🔐 [AUTH] Only the device owner can login on this device');
                return AuthResult.error(
                  'This device is already registered to another account.\n\n'
                  'Please use a different device'
                );
              }
              // User is the device owner - allow login
              debugPrint('🔐 [AUTH] User $currentUserId is the device owner - allowing login');
            }
          } else {
            // No device owner set yet - set current user as owner
            // This happens on first signup or after account deletion
            await _e2eService.setDeviceOwner(currentUserId);
            debugPrint('🔐 [AUTH] User $currentUserId set as device owner (first time)');
          }
        }
        
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
          final isPublicKeyMatchedValue = loginData['is_public_key_matched'];
          
          debugPrint('🔗 [AUTH] Raw is_new_user value: $isNewUserValue (type: ${isNewUserValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw pairingRequired value: $pairingRequiredValue (type: ${pairingRequiredValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw is_public_key_matched value: $isPublicKeyMatchedValue (type: ${isPublicKeyMatchedValue.runtimeType})');
          final e2eStatus = loginData['e2e_status']?.toString();
          final e2eReason = loginData['e2e_reason']?.toString();
          final e2eScenario = loginData['e2e_scenario']?.toString();
          final e2eMessage = loginData['e2e_message']?.toString();
          final pairingOtp = loginData['pairingOtp']?.toString();
          
          // Check is_public_key_matched FIRST - if false, pairing is required
          bool? isPublicKeyMatched;
          if (isPublicKeyMatchedValue is bool) {
            isPublicKeyMatched = isPublicKeyMatchedValue;
          } else if (isPublicKeyMatchedValue is String) {
            isPublicKeyMatched = isPublicKeyMatchedValue.toLowerCase() == 'true';
          } else if (isPublicKeyMatchedValue != null) {
            isPublicKeyMatched = isPublicKeyMatchedValue.toString().toLowerCase() == 'true';
          }
          
          debugPrint('🔗 [AUTH] Parsed is_public_key_matched: $isPublicKeyMatched (from raw: $isPublicKeyMatchedValue)');
          
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
          debugPrint('🔗 [AUTH] Login response - is_public_key_matched: $isPublicKeyMatched');
          debugPrint('🔗 [AUTH] Login response - e2e_status: $e2eStatus');
          debugPrint('🔗 [AUTH] Login response - e2e_reason: $e2eReason');
          debugPrint('🔗 [AUTH] Login response - e2e_scenario: $e2eScenario');
          debugPrint('🔗 [AUTH] Login response - pairingOtp: $pairingOtp');
          
          // Check if pairing is required: 
          // 1. Existing user (is_new_user=false) AND public key mismatch (is_public_key_matched=false)
          //    - This handles Android uninstall (keys deleted) or new device
          //    - iOS with persisted keys will have is_public_key_matched=true, so no pairing needed
          // 2. Explicit pairing signals from backend (e2e_reason or e2e_scenario)
          // 
          // IMPORTANT: If local keys exist (iOS Keychain persists after reinstall), 
          // skip early pairing and let bootstrap verify the keys
          final hasLocalKeys = await _e2eService.hasE2EKeys();
          debugPrint('🔗 [AUTH] Local E2E keys exist: $hasLocalKeys');
          
          // If local keys exist, skip pairing check - let bootstrap handle verification
          // This fixes iOS reinstall scenario where Keychain keys persist
          bool needsPairing = false;
          if (!hasLocalKeys) {
            // No local keys - check backend signals for pairing
            needsPairing = ((isNewUser == false && isPublicKeyMatched == false) ||
                            e2eReason == 'NEW_DEVICE_NEEDS_PAIRING' || 
                            e2eScenario == 'EXISTING_USER_NEEDS_PAIRING');
          }
          
          debugPrint('🔗 [AUTH] Needs pairing check: $needsPairing');
          debugPrint('🔗 [AUTH] Condition: hasLocalKeys=$hasLocalKeys, is_new_user=$isNewUser, is_public_key_matched=$isPublicKeyMatched, e2e_reason=$e2eReason, e2e_scenario=$e2eScenario');
          
          if (needsPairing) {
            // CRITICAL: Check device owner BEFORE allowing pairing
            // If different user tries to pair, block them
            if (currentUserId != null) {
              final existingOwner = await _e2eService.getDeviceOwnerUserId();
              if (existingOwner != null && existingOwner != currentUserId) {
                debugPrint('🔐 [AUTH] ⚠️ SECURITY: Different user trying to pair - BLOCKING');
                debugPrint('🔐 [AUTH] Device owner: $existingOwner, Attempting user: $currentUserId');
                return AuthResult.error(
                  'This device is already registered to another account.\n\n'
                  'Please use a different device'
                );
              }
            }
            
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
          final isPublicKeyMatchedRecheck = loginDataRecheck['is_public_key_matched'];
          
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
          
          // Re-check is_public_key_matched
          bool? isPublicKeyMatchedBool;
          if (isPublicKeyMatchedRecheck is bool) {
            isPublicKeyMatchedBool = isPublicKeyMatchedRecheck;
          } else if (isPublicKeyMatchedRecheck is String) {
            isPublicKeyMatchedBool = isPublicKeyMatchedRecheck.toLowerCase() == 'true';
          } else if (isPublicKeyMatchedRecheck != null) {
            isPublicKeyMatchedBool = isPublicKeyMatchedRecheck.toString().toLowerCase() == 'true';
          }
          
          debugPrint('🔗 [AUTH] Re-check parsed is_public_key_matched: $isPublicKeyMatchedBool (from raw: $isPublicKeyMatchedRecheck)');
          
          // Re-check: If public key doesn't match, pairing is required
          if (isPublicKeyMatchedBool == false) {
            debugPrint('🔗 [AUTH] ⚠️ Public key mismatch detected in RE-CHECK! Blocking direct login.');
            // CRITICAL: Check device owner BEFORE allowing pairing in re-check
            if (currentUserId != null) {
              final existingOwnerRecheck = await _e2eService.getDeviceOwnerUserId();
              if (existingOwnerRecheck != null && existingOwnerRecheck != currentUserId) {
                debugPrint('🔐 [AUTH] ⚠️ SECURITY: Different user trying to pair (re-check, public key mismatch) - BLOCKING');
                debugPrint('🔐 [AUTH] Device owner: $existingOwnerRecheck, Attempting user: $currentUserId');
                return AuthResult.error(
                  'This device is already registered to another account.\n\n'
                  'Please use a different device'
                );
              }
            }
            final e2eMessageRecheck = loginDataRecheck['e2e_message']?.toString();
            return AuthResult.pairingRequired(
              e2eMessageRecheck ?? 'Public key mismatch. Device pairing required. Please scan QR code or enter OTP.'
            );
          }
          
          final e2eReasonRecheck = loginDataRecheck['e2e_reason']?.toString();
          final e2eScenarioRecheck = loginDataRecheck['e2e_scenario']?.toString();
          final e2eMessageRecheck = loginDataRecheck['e2e_message']?.toString();
          
          // Re-check: existing user with public key mismatch OR explicit pairing signals
          // Same logic as initial check - if local keys exist, skip pairing (iOS fix)
          final hasLocalKeysRecheck = await _e2eService.hasE2EKeys();
          bool needsPairingRecheck = false;
          if (!hasLocalKeysRecheck) {
            needsPairingRecheck = ((isNewUserBool == false && isPublicKeyMatchedBool == false) ||
                                   e2eReasonRecheck == 'NEW_DEVICE_NEEDS_PAIRING' || 
                                   e2eScenarioRecheck == 'EXISTING_USER_NEEDS_PAIRING');
          }
          
          debugPrint('🔗 [AUTH] Re-check: hasLocalKeys=$hasLocalKeysRecheck, needsPairing=$needsPairingRecheck');
          
          if (needsPairingRecheck) {
            // CRITICAL: Check device owner BEFORE allowing pairing in re-check
            // If different user tries to pair, block them
            if (currentUserId != null) {
              final existingOwnerRecheck = await _e2eService.getDeviceOwnerUserId();
              if (existingOwnerRecheck != null && existingOwnerRecheck != currentUserId) {
                debugPrint('🔐 [AUTH] ⚠️ SECURITY: Different user trying to pair (re-check) - BLOCKING');
                debugPrint('🔐 [AUTH] Device owner: $existingOwnerRecheck, Attempting user: $currentUserId');
                return AuthResult.error(
                  'This device is already registered to another account.\n\n'
                  'Please use a different device'
                );
              }
            }
            
            debugPrint('🔗 [AUTH] ⚠️ Pairing required detected in RE-CHECK! Blocking direct login.');
            debugPrint('🔗 [AUTH] Re-check condition: is_new_user=$isNewUserBool, e2e_reason=$e2eReasonRecheck, e2e_scenario=$e2eScenarioRecheck');
            return AuthResult.pairingRequired(e2eMessageRecheck ?? 'Device pairing required');
          }
        }

        // E2E Encryption Bootstrap
        // CRITICAL: Check isNewUser from login response FIRST to determine flow
        // This prevents showing recovery phrase on new devices for existing users
        print('🔐 E2E Setup: Starting...');
        final hasExistingKeys = await _e2eService.hasE2EKeys();
        print('🔐 E2E Keys Present: $hasExistingKeys');
        
        // Get isNewUser from login response to determine if this is registration or pairing
        bool? isNewUserFromResponse;
        final loginDataForBootstrap = result.data!.data;
        if (loginDataForBootstrap != null && loginDataForBootstrap is Map<String, dynamic>) {
          final isNewUserValue = loginDataForBootstrap['is_new_user'];
          if (isNewUserValue is bool) {
            isNewUserFromResponse = isNewUserValue;
          } else if (isNewUserValue is String) {
            isNewUserFromResponse = isNewUserValue.toLowerCase() == 'true';
          } else if (isNewUserValue != null) {
            isNewUserFromResponse = isNewUserValue.toString().toLowerCase() == 'true';
          }
        }
        
        debugPrint('🔐 [AUTH] E2E Bootstrap Decision - isNewUser: $isNewUserFromResponse, hasExistingKeys: $hasExistingKeys');
        
        E2EBootstrapResult e2eResult;
        
        // Decision logic:
        // 1. If isNewUser == false (existing user), always use bootstrapForLogin (will detect pairing if needed)
        // 2. If isNewUser == true (new user), use bootstrapForRegistration
        // 3. If isNewUser is unknown, fall back to checking local keys
        if (isNewUserFromResponse == false) {
          // Existing user on new device - use login flow (will detect pairing requirement)
          // This prevents generating new recovery phrase for existing users
          print('🔐 E2E Flow: LOGIN (existing user, may need pairing)');
          debugPrint('🔐 [AUTH] Existing user detected - using login flow to prevent duplicate recovery phrase');
          e2eResult = await _e2eService.bootstrapForLogin(accessToken);
        } else if (isNewUserFromResponse == true) {
          // New user - registration flow (Phase 2: E2E Key Bootstrap)
          print('🔐 E2E Flow: REGISTRATION (new user)');
          e2eResult = await _e2eService.bootstrapForRegistration(accessToken);
        } else {
          // isNewUser is unknown - fall back to checking local keys
          if (hasExistingKeys) {
            // Existing user - login flow (Phase 3.4-3.6)
            // This will automatically fall back to registration if server says E2E_NOT_SETUP
            print('🔐 E2E Flow: LOGIN (fallback - local keys exist)');
            e2eResult = await _e2eService.bootstrapForLogin(accessToken);
          } else {
            // New user - registration flow (Phase 2: E2E Key Bootstrap)
            print('🔐 E2E Flow: REGISTRATION (fallback - no local keys)');
            e2eResult = await _e2eService.bootstrapForRegistration(accessToken);
          }
        }

        // CRITICAL: Check if pairing is required (E2E set up on another device)
        // This check MUST happen even if login response didn't have pairing fields
        // Bootstrap response is the authoritative source for pairing requirement
        if (e2eResult.needsPairing) {
          // CRITICAL: Check device owner BEFORE allowing pairing from bootstrap
          // If different user tries to pair, block them
          if (currentUserId != null) {
            final existingOwnerBootstrap = await _e2eService.getDeviceOwnerUserId();
            if (existingOwnerBootstrap != null && existingOwnerBootstrap != currentUserId) {
              debugPrint('🔐 [AUTH] ⚠️ SECURITY: Different user trying to pair (bootstrap) - BLOCKING');
              debugPrint('🔐 [AUTH] Device owner: $existingOwnerBootstrap, Attempting user: $currentUserId');
              return AuthResult.error(
                'This device is already registered to another account.\n\n'
                'Please use a different device'
              );
            }
          }
          
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
            if (loginData != null && loginData is Map<String, dynamic>) {
              final isNewUserValue = loginData['is_new_user'];
              bool? isNewUser;
              if (isNewUserValue is bool) {
                isNewUser = isNewUserValue;
              } else if (isNewUserValue is String) {
                isNewUser = isNewUserValue.toLowerCase() == 'true';
              }
              
              // If existing user but keys missing, force pairing
              if (isNewUser == false) {
                debugPrint('🔐 [AUTH] Existing user with missing keys - forcing pairing');
                return AuthResult.pairingRequired(
                  'E2E keys not found. Device pairing required. Please scan QR code or enter OTP.'
                );
              }
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
          if (!hasE2EKeys || !hasSessionKu) {
            debugPrint('🔐 [AUTH] ⚠️ SECURITY: Keys not properly stored after setup - blocking login');
            return AuthResult.error(
              'E2E keys setup incomplete. Please try logging in again.'
            );
          }
        }

        // Return success with recovery phrase if available (from registration)
        return AuthResult.success(result.data!, recoveryPhrase: e2eResult.recoveryPhrase);
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
  final String? recoveryPhrase;

  AuthResult.success(this.data, {this.recoveryPhrase}) 
      : error = null, 
        requiresPairing = false;
  
  AuthResult.error(this.error) 
      : data = null, 
        requiresPairing = false,
        recoveryPhrase = null;
  
  AuthResult.pairingRequired(this.error)
      : data = null,
        requiresPairing = true,
        recoveryPhrase = null;

  bool get isSuccess => data != null;
  bool get isError => error != null;
  bool get needsPairing => requiresPairing;
}

