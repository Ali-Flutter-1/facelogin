import 'dart:convert';
import 'dart:typed_data';

import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/device_service.dart' as device_id_service;
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/core/services/token_expiration_service.dart';
import 'package:facelogin/data/models/login_response_model.dart';
import 'package:facelogin/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {
  final AuthService _authService;
  final E2EService _e2eService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  AuthRepository({
    AuthService? authService,
    E2EService? e2eService,
  })  : _authService = authService ?? AuthService(),
        _e2eService = e2eService ?? E2EService();

  /// Derive device public key (PKd) from stored private key seed (SKd)
  /// If no local SKd exists (Android uninstall scenario), generate a new temporary key pair
  /// GLOBAL RULE: Ensure device keypair exists and return public key
  /// On every login attempt:
  /// - Check if local keypair exists → use it
  /// - If missing → generate new keypair and store it securely
  /// - Always return the public key to send with login request
  Future<String?> _deriveDevicePublicKey() async {
    try {
      // Use E2EService method that ensures keypair exists
      final publicKey = await _e2eService.ensureDeviceKeypairExists();
      if (publicKey != null) {
        debugPrint('🔐 [AUTH] Device public key ready: ${publicKey.substring(0, 20)}...');
      } else {
        debugPrint('🔐 [AUTH] Failed to ensure device keypair exists');
      }
      return publicKey;
    } catch (e) {
      debugPrint('🔐 [AUTH] Error deriving device public key: $e');
      return null;
    }
  }
  
  /// Convert BigInt to fixed-length bytes
  Uint8List _bigIntToBytes(BigInt bigInt, int length) {
    final bytes = <int>[];
    var value = bigInt;
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xff)).toInt());
      value = value >> 8;
    }
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes.length > length ? bytes.sublist(bytes.length - length) : bytes);
  }

  /// Login or register with face image
  /// Automatically handles E2E encryption bootstrap
  Future<AuthResult> loginOrRegister(Uint8List faceImageBytes) async {
    // Get device ID (REQUIRED for login - fail if missing)
    final deviceService = device_id_service.DeviceService();
    String? deviceId;
    try {
      deviceId = await deviceService.getDeviceId();
      if (deviceId != null && deviceId.isNotEmpty) {
        debugPrint('📱 [AUTH] Device ID retrieved: ${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}...');
      } else {
        debugPrint('❌ [AUTH] Device ID is empty after retrieval');
        return AuthResult.error('Failed to retrieve device ID. Please try again.');
      }
    } catch (e) {
      debugPrint('❌ [AUTH] Failed to get device ID: $e');
      return AuthResult.error('Failed to retrieve device ID. Please try again.');
    }
    
    // Derive device_public_key from local SKd if exists (for iOS reinstall verification)
    final devicePublicKey = await _deriveDevicePublicKey();
    
    final result = await _authService.loginOrRegister(faceImageBytes, devicePublicKey: devicePublicKey, deviceId: deviceId);

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
        
        // Parse backend fields - default to false if null
        bool parseBool(dynamic value) {
          if (value == null) return false;
          if (value is bool) return value;
          if (value is String) return value.toLowerCase() == 'true';
          if (value is int) return value != 0;
          return value.toString().toLowerCase() == 'true';
        }
        
        // Initialize variables with default values (accessible outside if block)
        bool isPublicKeyMatched = false;
        bool isNewUser = false;
        bool isDeviceFound = false;
        bool isDeviceLinkedWithUser = false;
        bool pairingRequired = false;
        
        if (loginData != null && loginData is Map<String, dynamic>) {
          // Handle boolean values that might come as strings or booleans
          final isNewUserValue = loginData['is_new_user'];
          final pairingRequiredValue = loginData['pairingRequired'];
          final isPublicKeyMatchedValue = loginData['is_public_key_matched'];
          final isDeviceFoundValue = loginData['is_device_found'];
          
          debugPrint('🔗 [AUTH] Raw is_new_user value: $isNewUserValue (type: ${isNewUserValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw pairingRequired value: $pairingRequiredValue (type: ${pairingRequiredValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw is_public_key_matched value: $isPublicKeyMatchedValue (type: ${isPublicKeyMatchedValue.runtimeType})');
          debugPrint('🔗 [AUTH] Raw is_device_found value: $isDeviceFoundValue (type: ${isDeviceFoundValue.runtimeType})');
          final e2eStatus = loginData['e2e_status']?.toString();
          final e2eReason = loginData['e2e_reason']?.toString();
          final e2eScenario = loginData['e2e_scenario']?.toString();
          final e2eMessage = loginData['e2e_message']?.toString();
          final pairingOtp = loginData['pairingOtp']?.toString();
          
          // Parse is_public_key_matched (default to false if null)
          isPublicKeyMatched = parseBool(isPublicKeyMatchedValue);
          
          // Parse is_new_user (default to false if null)
          isNewUser = parseBool(isNewUserValue);
          
          // Parse is_device_found (default to false if null)
          isDeviceFound = parseBool(isDeviceFoundValue);
          
          // Parse is_device_linked_with_user (default to false if null)
          final isDeviceLinkedWithUserValue = loginData['is_device_linked_with_user'] ?? loginData['isDeviceLinkedWithUser'];
          isDeviceLinkedWithUser = parseBool(isDeviceLinkedWithUserValue);
          
          // Parse pairingRequired (default to false if null)
          pairingRequired = parseBool(pairingRequiredValue);
          
          debugPrint('🔗 [AUTH] Parsed backend response (nulls default to false):');
          debugPrint('🔗 [AUTH]   - is_new_user: $isNewUser');
          debugPrint('🔗 [AUTH]   - is_device_found: $isDeviceFound');
          debugPrint('🔗 [AUTH]   - is_device_linked_with_user: $isDeviceLinkedWithUser');
          debugPrint('🔗 [AUTH]   - is_public_key_matched: $isPublicKeyMatched');
          debugPrint('🔗 [AUTH]   - pairingRequired: $pairingRequired');
          
          // ============================================
          // DECISION LOGIC (SIMPLIFIED)
          // ============================================
          
          // Save tokens first (needed for all flows including pairing)
          final prefs = await SharedPreferences.getInstance();
          debugPrint('💾 Saving tokens to SharedPreferences (before decision logic)...');
          
          final accessTokenSaved = await prefs.setString(AppConstants.accessTokenKey, accessToken!);
          final refreshTokenSaved = await prefs.setString(AppConstants.refreshTokenKey, result.data!.refreshToken!);
          
          debugPrint('💾 Token save results: accessToken=$accessTokenSaved, refreshToken=$refreshTokenSaved');

          if (!accessTokenSaved || !refreshTokenSaved) {
            debugPrint('❌ Failed to save tokens to SharedPreferences');
            return AuthResult.error(
              'Login successful but failed to save session. Please try again.',
            );
          }
          
          // Set token expiration to 1 hour from now
          final tokenExpirationService = TokenExpirationService();
          await tokenExpirationService.setTokenExpiration();
          
          // 1. If is_device_found = false
          if (!isDeviceFound) {
            debugPrint('🔗 [AUTH] Decision: is_device_found = false');
            
            // Check if user is new
            if (isNewUser) {
              debugPrint('🔗 [AUTH]   → is_new_user = true → Proceed to normal login/registration');
              // Continue with normal flow (bootstrap/complete will be called)
            } else {
              // User exists but device not found
              // This could mean:
              // 1. User has E2E keys on another device → needs pairing
              // 2. User was just created but has no E2E keys yet → needs bootstrap/complete (registration)
              // We can't determine this from login response alone, so let bootstrap flow decide
              debugPrint('🔗 [AUTH]   → is_new_user = false → User exists but device not found');
              debugPrint('🔗 [AUTH]   → Letting bootstrap flow determine: pairing or registration');
              // Continue with normal flow - bootstrap will check if user has E2E keys
              // If user has no E2E keys, bootstrap will proceed with registration
              // If user has E2E keys, bootstrap will detect pairing requirement
            }
          }
          // 2. If is_device_found = true
          else {
            debugPrint('🔗 [AUTH] Decision: is_device_found = true');
            
            // 2.1 Check if device is linked with user
            if (!isDeviceLinkedWithUser) {
              debugPrint('🔗 [AUTH]   → is_device_linked_with_user = false → Access denied');
              return AuthResult.error(
                'This device belongs to another user. Access denied.'
              );
            }
            
            // 2.2 Device is linked with user - validate public key
            debugPrint('🔗 [AUTH]   → is_device_linked_with_user = true → Validating public key');
            
            // 3. Validate public key
            if (isPublicKeyMatched) {
              debugPrint('🔗 [AUTH]     → is_public_key_matched = true → Direct login');
              // Continue with normal flow (direct login)
            } else {
              debugPrint('🔗 [AUTH]     → is_public_key_matched = false → Show pairing screen first (generate QR code)');
              // Return early to show pairing screen immediately
              // Pairing screen will generate QR code first, then poll bootstrap
              // CRITICAL: Check device owner BEFORE allowing pairing
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
              return AuthResult.pairingRequired(
                'Device pairing required. Your device keys were reset. Please scan QR code or enter OTP to pair your device.'
              );
            }
          }
          
          // If we reach here, continue with normal login flow
          debugPrint('🔗 [AUTH] Decision: Continuing with normal login flow');
        } else {
          debugPrint('🔗 [AUTH] ⚠️ Login data is null or not a Map - will check bootstrap response');
          
          // Save tokens even if login data is null (needed for bootstrap)
          final prefs = await SharedPreferences.getInstance();
          debugPrint('💾 Saving tokens to SharedPreferences (login data null)...');
          
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
          
          // Set token expiration to 1 hour from now
          final tokenExpirationService = TokenExpirationService();
          await tokenExpirationService.setTokenExpiration();
        }

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
            // CRITICAL: If is_new_user is false (existing user) and is_public_key_matched is false OR null,
            // this indicates Android reinstall scenario (keys deleted) - pairing is required
            final publicKeyMismatchRecheck = isPublicKeyMatchedBool == false || 
                                            (isNewUserBool == false && isPublicKeyMatchedBool == null);
            needsPairingRecheck = ((isNewUserBool == false && publicKeyMismatchRecheck) ||
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
        // 1. If isNewUser == true (explicitly new user), use bootstrapForRegistration
        // 2. If isNewUser == false (existing user), always use bootstrapForLogin (will detect pairing if needed)
        // 3. If isNewUser is unknown (null), default to LOGIN flow (safer - will detect pairing or fall back to registration)
        //    This fixes: existing user clears data → is_new_user=null → should still trigger pairing
        if (isNewUserFromResponse == true) {
          // New user - registration flow (Phase 2: E2E Key Bootstrap)
          print('🔐 E2E Flow: REGISTRATION (new user)');
          e2eResult = await _e2eService.bootstrapForRegistration(accessToken);
        } else if (isNewUserFromResponse == false) {
          // Existing user on new device - use login flow (will detect pairing requirement)
          // This prevents generating new recovery phrase for existing users
          print('🔐 E2E Flow: LOGIN (existing user, may need pairing)');
          debugPrint('🔐 [AUTH] Existing user detected - using login flow to prevent duplicate recovery phrase');
          e2eResult = await _e2eService.bootstrapForLogin(accessToken);
        } else {
          // isNewUser is unknown (null) - need to determine flow
          // If no local keys, try REGISTRATION first (likely new user)
          // If registration fails (user exists), fall back to login/pairing
          if (hasExistingKeys) {
            // Has local keys - definitely use login flow
            print('🔐 E2E Flow: LOGIN (fallback - local keys exist)');
            e2eResult = await _e2eService.bootstrapForLogin(accessToken);
          } else {
            // No local keys and isNewUser unknown - try REGISTRATION first
            // This handles first-time registration where backend returns is_new_user=null
            // If registration fails (user already has E2E), fall back to login/pairing
            print('🔐 E2E Flow: REGISTRATION (fallback - isNewUser unknown, no local keys, trying registration first)');
            debugPrint('🔐 [AUTH] Unknown user status, no local keys - trying registration first');
            e2eResult = await _e2eService.bootstrapForRegistration(accessToken);
            
            // If registration fails with "already exists" error, fall back to login
            if (!e2eResult.isSuccess && 
                (e2eResult.error?.toLowerCase().contains('already') == true ||
                 e2eResult.error?.toLowerCase().contains('exists') == true)) {
              print('🔐 E2E Flow: Registration failed (user exists) - falling back to LOGIN');
              debugPrint('🔐 [AUTH] Registration failed, user already has E2E - using login flow');
              e2eResult = await _e2eService.bootstrapForLogin(accessToken);
            }
          }
        }

        // CRITICAL: Check if recovery is required (keys mismatch - is_public_key_matched = false)
        // This takes priority over pairing - user must recover account using recovery phrase
        if (e2eResult.needsRecovery) {
          print('🔗 E2E Recovery Required (from bootstrap response)');
          debugPrint('🔗 [AUTH] E2E keys mismatch - recovery required');
          debugPrint('🔗 [AUTH] E2E error message: ${e2eResult.error}');
          debugPrint('🔗 [AUTH] Bootstrap detected recovery requirement - user must use recovery phrase');
          
          // Save tokens first so recovery can use them
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(AppConstants.accessTokenKey, accessToken!);
          await prefs.setString(AppConstants.refreshTokenKey, result.data!.refreshToken!);
          
          return AuthResult.recoveryRequired(
            e2eResult.error ?? 'Account recovery required. Please use your recovery phrase to restore access.'
          );
        }
        
        // CRITICAL: Check if pairing is required (E2E set up on another device OR public key mismatch)
        // This check MUST happen even if login response didn't have pairing fields
        // Bootstrap response is the authoritative source for pairing requirement
        // Also check if is_public_key_matched = false from login response
        final needsPairingFromBootstrap = e2eResult.needsPairing;
        final needsPairingFromLogin = (!isPublicKeyMatched && isDeviceFound && isDeviceLinkedWithUser);
        
        if (needsPairingFromBootstrap || needsPairingFromLogin) {
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
          
          print('🔗 E2E Pairing Required (from bootstrap response or public key mismatch)');
          debugPrint('🔗 [AUTH] Pairing needed - bootstrap: $needsPairingFromBootstrap, login: $needsPairingFromLogin');
          debugPrint('🔗 [AUTH] E2E error message: ${e2eResult.error}');
          debugPrint('🔗 [AUTH] Bootstrap will continue running while pairing screen is shown');
          // Return special result indicating pairing is needed
          // This will trigger QR code dialog and bootstrap will continue polling
          return AuthResult.pairingRequired(e2eResult.error ?? 'Device pairing required. Please scan QR code or enter OTP to pair your device.');
        }

        // SECURITY: Verify E2E keys are properly set up before allowing login
        final hasE2EKeys = await _e2eService.hasE2EKeys();
        final hasSessionKu = await _e2eService.getSessionKu() != null;
        
        debugPrint('🔐 [AUTH] E2E Keys Check - SKd exists: $hasE2EKeys, Ku in session: $hasSessionKu');
        
        if (!e2eResult.isSuccess) {
          print('🔐 E2E Setup: Failed - ${e2eResult.error}');
          debugPrint('⚠️ [AUTH] E2E setup failed: ${e2eResult.error}');
          
          // Check if error indicates user has no E2E at all (new user)
          final e2eError = e2eResult.error?.toLowerCase() ?? '';
          final isNewUserError = e2eError.contains('e2e_not_setup_new_user') ||
                                e2eError.contains('no existing e2e') ||
                                e2eError.contains('use bootstrap/complete') ||
                                (e2eError.contains('not set up') && e2eError.contains('generate keys'));
          
          if (isNewUserError) {
            // User has no E2E at all - this is a new user, use registration
            debugPrint('🔐 [AUTH] Login detected new user (no E2E) - falling back to registration');
            try {
              final registrationResult = await _e2eService.bootstrapForRegistration(accessToken);
              if (registrationResult.isSuccess) {
                debugPrint('🔐 [AUTH] Registration successful after login fallback');
                final hasE2EKeysAfterReg = await _e2eService.hasE2EKeys();
                final hasSessionKuAfterReg = await _e2eService.getSessionKu() != null;
                if (hasE2EKeysAfterReg && hasSessionKuAfterReg) {
                  return AuthResult.success(result.data!, recoveryPhrase: registrationResult.recoveryPhrase);
                }
              }
              // If registration also failed, continue to error handling below
              debugPrint('🔐 [AUTH] Registration fallback also failed');
            } catch (regError) {
              debugPrint('🔐 [AUTH] Registration fallback exception: $regError');
            }
          }
          
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
            }
            
            // Check e2eResult.error for signals that E2E exists on another device
            // This helps when is_new_user is null but we know user has E2E elsewhere
            final hasE2EElsewhere = e2eError.contains('another device') ||
                                    e2eError.contains('pairing') ||
                                    e2eError.contains('new_device') ||
                                    e2eError.contains('not_setup_for_this_device');
            
            debugPrint('🔐 [AUTH] isNewUser: $isNewUser, hasE2EElsewhere: $hasE2EElsewhere, e2eError: ${e2eResult.error}');
            
            // If existing user (is_new_user=false) OR E2E exists elsewhere → force pairing
            // This fixes: is_new_user=null but E2E exists on another device
            if (isNewUser == false || hasE2EElsewhere) {
              debugPrint('🔐 [AUTH] Existing user with missing keys - forcing pairing');
              return AuthResult.pairingRequired(
                'E2E keys not found. Device pairing required. Please scan QR code or enter OTP.'
              );
            }
            
            // Only force registration if this is truly a NEW user (is_new_user == true)
            // For new users, if bootstrap failed, retry registration automatically
            if (isNewUser == true) {
              debugPrint('🔐 [AUTH] New user - bootstrap failed, retrying registration');
              // Retry bootstrap for registration - this handles cases where first attempt failed
              try {
                final retryResult = await _e2eService.bootstrapForRegistration(accessToken);
                if (retryResult.isSuccess) {
                  debugPrint('🔐 [AUTH] Registration retry successful');
                  // Check if keys are now present
                  final hasE2EKeysAfterRetry = await _e2eService.hasE2EKeys();
                  final hasSessionKuAfterRetry = await _e2eService.getSessionKu() != null;
                  if (hasE2EKeysAfterRetry && hasSessionKuAfterRetry) {
                    return AuthResult.success(result.data!, recoveryPhrase: retryResult.recoveryPhrase);
                  }
                }
                // If retry also failed, return error
                debugPrint('🔐 [AUTH] Registration retry also failed');
                return AuthResult.error(
                  'E2E encryption setup required. Please try logging in again to complete setup.'
                );
              } catch (retryError) {
                debugPrint('🔐 [AUTH] Registration retry exception: $retryError');
                return AuthResult.error(
                  'E2E encryption setup required. Please try logging in again to complete setup.'
                );
              }
            }
            
            // Unknown case (is_new_user is null and no E2E signals) - default to pairing
            // Safer to show pairing dialog than to block with error
            debugPrint('🔐 [AUTH] Unknown user status - defaulting to pairing dialog');
            return AuthResult.pairingRequired(
              'Device setup required. Please scan QR code or enter OTP, or use recovery phrase.'
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
      // Login/register API returned an error - check if it indicates pairing requirement
      final errorMessage = result.error?.toLowerCase() ?? '';
      debugPrint('🔗 [AUTH] Login/register API error: ${result.error}');
      
      // Check if error indicates pairing requirement (Android reinstall scenario)
      // Common error messages: "already registered", "e2e keys", "device", "registered", "bootstrap"
      final normalizedError = errorMessage;
      final indicatesPairing = normalizedError.contains('already registered') ||
                               normalizedError.contains('e2e') ||
                               normalizedError.contains('device') ||
                               normalizedError.contains('registered') ||
                               normalizedError.contains('keys') ||
                               (normalizedError.contains('bootstrap') && normalizedError.contains('complete'));
      
      // Check if we have local keys
      final hasLocalKeys = await _e2eService.hasE2EKeys();
      debugPrint('🔗 [AUTH] Error indicates pairing: $indicatesPairing, hasLocalKeys: $hasLocalKeys');
      debugPrint('🔗 [AUTH] Error message: ${result.error}');
      
      // If error indicates pairing and we have no local keys, this is likely Android reinstall
      // Also check if error mentions bootstrap/complete (which suggests pairing is needed)
      if (indicatesPairing && !hasLocalKeys) {
        debugPrint('🔗 [AUTH] ✅ Detected Android reinstall scenario - showing pairing screen');
        return AuthResult.pairingRequired(
          'Device pairing required. Please scan QR code or enter OTP, or use your recovery phrase.'
        );
      }
      
      // Also check for specific error patterns that indicate pairing
      // "this user has not e2e set up first call bootstrap/complete" suggests pairing needed
      if (normalizedError.contains('bootstrap') && normalizedError.contains('complete') && !hasLocalKeys) {
        debugPrint('🔗 [AUTH] ✅ Bootstrap/complete error detected - showing pairing screen');
        return AuthResult.pairingRequired(
          'Device pairing required. Please scan QR code or enter OTP, or use your recovery phrase.'
        );
      }
      
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
    // Clear token expiration
    final tokenExpirationService = TokenExpirationService();
    await tokenExpirationService.clearTokenExpiration();
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
  final bool requiresRecovery;
  final String? recoveryPhrase;

  AuthResult.success(this.data, {this.recoveryPhrase}) 
      : error = null, 
        requiresPairing = false,
        requiresRecovery = false;
  
  AuthResult.error(this.error) 
      : data = null, 
        requiresPairing = false,
        requiresRecovery = false,
        recoveryPhrase = null;
  
  AuthResult.pairingRequired(this.error)
      : data = null,
        requiresPairing = true,
        requiresRecovery = false,
        recoveryPhrase = null;
  
  AuthResult.recoveryRequired(this.error)
      : data = null,
        requiresPairing = false,
        requiresRecovery = true,
        recoveryPhrase = null;

  bool get isSuccess => data != null;
  bool get isError => error != null;
  bool get needsPairing => requiresPairing;
}

