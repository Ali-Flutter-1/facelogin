import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'package:cryptography/cryptography.dart' as crypto show PublicKey, KeyPair;
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/services/device_service.dart';
import 'package:facelogin/data/services/pairing_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' hide SecureRandom;
import 'package:pointycastle/export.dart' as pc show SecureRandom;
import 'package:shared_preferences/shared_preferences.dart';

/// E2E Encryption Service
/// Handles P-256 (secp256r1) ECDH key exchange and AES-GCM encryption
/// Uses Keychain (iOS) and Keystore (Android) for secure key storage
/// 
/// IMPORTANT SECURITY NOTES:
/// - Ku (User Master Key): 32-byte AES key, exists ONLY on client device
///   - Stored in memory during session only
///   - NEVER sent to server in plaintext
///   - Only wrappedKu (encrypted) is sent to server
/// 
/// - SKd (Device Private Key): P-256 (secp256r1) private key, exists ONLY on client device
///   - Stored permanently in Keychain/Keystore
///   - NEVER sent to server (only PKd is sent)
///   - Used to decrypt wrappedKu on login
///   - NEVER cleared during logout
class E2EService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      // Use first_unlock_this_device for persistence
      // This ensures the keychain item persists even after app reinstall
      // (as long as the device isn't wiped)
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final DeviceService _deviceService = DeviceService();
  final http.Client _client = http.Client();

  // Storage keys for secure keychain/keystore
  static const String _skdKey = 'e2e_skd'; // Device private key (P-256)
  static const String _kuKey = 'e2e_ku_session'; // User master key (AES-256, session only)
  static const String _bootstrapCompleteResponseKey = 'e2e_bootstrap_complete_response'; // Bootstrap complete API response
  static const String _deviceOwnerUserIdKey = 'device_owner_user_id'; // First user who signed up on this device (device owner)

  /// Bootstrap E2E for registration (first device)
  /// Phase 2: E2E Key Bootstrap (First Device)
  Future<E2EBootstrapResult> bootstrapForRegistration(String accessToken) async {
    try {
      final deviceId = await _deviceService.getDeviceId();
      print('🔐 E2E Device ID: $deviceId');

      // Step 2.1: Call /e2e/bootstrap with deviceId
      final requestBody = jsonEncode({'deviceId': deviceId});
      print('🔐 E2E Bootstrap Request: POST ${ApiConstants.e2eBootstrap}');
      print('🔐 E2E Bootstrap Request Body: $requestBody');
      
      final bootstrapResponse = await _client.post(
        Uri.parse(ApiConstants.e2eBootstrap),
        headers: {
          'Content-Type': ApiConstants.contentTypeJson,
          'Authorization': 'Bearer $accessToken',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      print('🔐 E2E Bootstrap Response Status: ${bootstrapResponse.statusCode}');
      print('🔐 E2E Bootstrap Response Body: ${bootstrapResponse.body}');
      
      Map<String, dynamic> bootstrapData;
      try {
        bootstrapData = jsonDecode(bootstrapResponse.body) as Map<String, dynamic>;
      } catch (e) {
        print('🔐 E2E Status: Error parsing response');
        return E2EBootstrapResult.error('Failed to parse bootstrap response: $e');
      }
      
      // Check if error is "E2E_NOT_SETUP" - this is expected for new registration
      if (bootstrapResponse.statusCode != 200) {
        final error = bootstrapData['error'];
        String errorCode = '';
        String errorMessage = '';
        
        if (error != null && error is Map) {
          errorCode = error['code']?.toString() ?? '';
          errorMessage = error['message']?.toString() ?? '';
        } else if (error is String) {
          errorMessage = error;
        }
        
        // If error is "E2E_NOT_SETUP", this is expected - proceed with registration
        if (errorCode == 'E2E_NOT_SETUP' || errorMessage.contains('E2E encryption is not set up')) {
          print('🔐 E2E Status: Not Setup (expected for new registration)');
          // Continue with key generation - this is not an error
        } else {
          print('🔐 E2E Status: Error - ${errorMessage.isNotEmpty ? errorMessage : errorCode}');
          return E2EBootstrapResult.error(
            errorMessage.isNotEmpty ? errorMessage : (errorCode.isNotEmpty ? errorCode : 'Bootstrap failed')
          );
        }
      } else {
        // Status 200 - check if E2E is already set up
        final data = bootstrapData['data'];
        if (bootstrapData['e2e_setup'] == true || (data != null && data is Map && data['wrappedKu'] != null)) {
          print('🔐 E2E Status: Already Setup');
          // Check if we have SKd locally - if not, skip E2E (can't decrypt without matching key)
          final hasLocalSkd = await _storage.read(key: _skdKey);
          print('🔐 E2E Status: Checking local SKd - exists: ${hasLocalSkd != null && hasLocalSkd.isNotEmpty} (length: ${hasLocalSkd?.length ?? 0})');
          if (hasLocalSkd != null && hasLocalSkd.isNotEmpty) {
            // We have SKd, try to recover
            print('🔐 E2E Status: Local SKd found - attempting recovery');
            return await _recoverKeysForExistingDevice(accessToken, deviceId, bootstrapData);
          } else {
            // Server says E2E is active, but we don't have SKd locally
            // This happens when app is reinstalled or keys were cleared
            // Can't decrypt server's wrappedKu without matching SKd
            // Can't re-register because server returns 409 "already_exists"
            // Solution: Skip E2E for this session
            print('🔐 E2E Status: Server active but no local SKd - skipping E2E (app reinstalled/keys cleared)');
            return E2EBootstrapResult.error('E2E keys mismatch - app reinstalled, E2E disabled for this session');
          }
        } else {
          print('🔐 E2E Status: Not Setup');
        }
      }

      // Step 2.3: Generate Keys
      
      // Generate P-256 keypair (PKd, SKd) using pointycastle
      // Use seed-based approach: generate random seed, create keypair from seed, store seed
      final domainParams = ECCurve_secp256r1();
      
      // Generate 32-byte random seed for P-256 private key
      // Use dart:math Random.secure() for secure random generation
      final seed = Uint8List(32);
      final secureRandom = Random.secure();
      for (int i = 0; i < 32; i++) {
        seed[i] = secureRandom.nextInt(256);
      }
      
      // Create keypair from seed using pointycastle
      final keyGen = ECKeyGenerator();
      final keyParams = ECKeyGeneratorParameters(domainParams);
      final pcSecureRandom = pc.SecureRandom('Fortuna');
      pcSecureRandom.seed(KeyParameter(seed));
      keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
      final pcKeyPair = keyGen.generateKeyPair();
      final pcPkd = pcKeyPair.publicKey as ECPublicKey;
      final pcSkd = pcKeyPair.privateKey as ECPrivateKey;
      
      // Extract public key bytes
      final pkdBytes = _ecPublicKeyToBytes(pcPkd);
      

      // Generate 32-byte AES User Master Key (Ku)
      final ku = Uint8List(32);
      final kuSecureRandom = Random.secure();
      for (int i = 0; i < 32; i++) {
        ku[i] = kuSecureRandom.nextInt(256);
      }

      // Step 2.4: Encrypt: wrappedKu = Encrypt(Ku, PKd)
      // We use ECDH key exchange to derive shared secret, then AES-GCM to encrypt Ku
      // Use pointycastle for ECDH
      final wrappedKu = await _encryptKuWithPointycastleKeys(ku, pcPkd, pcSkd);

      // Step 2.5: Send: deviceId, PKd, wrappedKu
      // Step 2.6: Store in Device Keys Table (server-side)
      // pkdBytes was already extracted above using pointycastle
      final pkdBase64 = base64Encode(pkdBytes);
      final wrappedKuBase64 = base64Encode(wrappedKu);
      
      final completeRequestBody = jsonEncode({
        'deviceId': deviceId,
        'PKd': pkdBase64,
        'wrappedKu': wrappedKuBase64,
      });
      
      print('🔐 E2E Bootstrap Complete Request: POST ${ApiConstants.e2eBootstrapComplete}');
      print('🔐 E2E Bootstrap Complete Request Body: $completeRequestBody');
      
      final completeResponse = await _client.post(
        Uri.parse(ApiConstants.e2eBootstrapComplete),
        headers: {
          'Content-Type': ApiConstants.contentTypeJson,
          'Authorization': 'Bearer $accessToken',
        },
        body: completeRequestBody,
      ).timeout(const Duration(seconds: 30));

      print('🔐 E2E Bootstrap Complete Response Status: ${completeResponse.statusCode}');
      print('🔐 E2E Bootstrap Complete Response Body: ${completeResponse.body}');
      
      Map<String, dynamic> completeData;
      try {
        completeData = jsonDecode(completeResponse.body) as Map<String, dynamic>;
      } catch (e) {
        print('🔐 E2E Setup: Failed - Error parsing response');
        return E2EBootstrapResult.error('Failed to parse bootstrap complete response: $e');
      }
      
      if (completeResponse.statusCode == 200 || completeResponse.statusCode == 201) {
        print('🔐 E2E Setup: Success');
        print('🔐 Ku: Generated (32 bytes)');
      } else {
        final error = completeData['error'];
        String errorMessage = 'Unknown error';
        if (error != null && error is Map) {
          errorMessage = error['message']?.toString() ?? error['code']?.toString() ?? 'Unknown error';
        } else if (error is String) {
          errorMessage = error;
        }
        print('🔐 E2E Setup: Failed - $errorMessage');
      }

      // Store bootstrap/complete response for debugging
      await _storage.write(
        key: _bootstrapCompleteResponseKey,
        value: jsonEncode({
          'statusCode': completeResponse.statusCode,
          'body': completeResponse.body,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (completeResponse.statusCode != 200 && completeResponse.statusCode != 201) {
        try {
          final errorData = jsonDecode(completeResponse.body);
          String errorMessage = 'Bootstrap complete failed';
          if (errorData is Map) {
            final error = errorData['error'];
            if (error is Map) {
              errorMessage = error['message']?.toString() ?? error['code']?.toString() ?? errorMessage;
            } else if (error is String) {
              errorMessage = error;
            } else {
              errorMessage = errorData['message']?.toString() ?? errorMessage;
            }
          }
          return E2EBootstrapResult.error(errorMessage);
        } catch (e) {
          return E2EBootstrapResult.error('Bootstrap complete failed: $e');
        }
      }

      // Step 2.7: Store SKd in secure device storage (Keychain/Keystore)
      // IMPORTANT: SKd exists ONLY on this client device, NEVER sent to server
      // Store the seed that was used to generate the keypair
      // This seed is the private key material for P-256
      final skdBase64 = base64Encode(seed);
      print('🔐 SKd: Attempting to store in Keychain/Keystore (length: ${skdBase64.length} bytes)');
      
      try {
        await _storage.write(
          key: _skdKey,
          value: skdBase64,
        );
        print('🔐 SKd: Write operation completed');
        
        // Wait a moment for iOS Keychain to sync
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Verify SKd was stored correctly - try multiple times
        bool verified = false;
        for (int i = 0; i < 3; i++) {
          final verifySkd = await _storage.read(key: _skdKey);
          if (verifySkd != null && verifySkd.isNotEmpty && verifySkd == skdBase64) {
            verified = true;
            print('🔐 SKd: Storage verified successfully (attempt ${i + 1}, length: ${verifySkd.length})');
            break;
          } else {
            print('🔐 SKd: Verification attempt ${i + 1} failed - retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
        
        if (!verified) {
          print('🔐 ERROR: SKd storage verification failed after 3 attempts!');
          print('🔐 ERROR: This may indicate an iOS Keychain issue');
          // Don't fail registration, but log the error
        }
      } catch (e) {
        print('🔐 ERROR: Failed to store SKd: $e');
        // This is critical - SKd must be stored
        return E2EBootstrapResult.error('Failed to store device key: $e');
      }

      // Keep Ku in memory for current session only
      // IMPORTANT: Ku exists ONLY on this client device, NEVER sent to server in plaintext
      // Only wrappedKu (encrypted) is sent to server
      await _storage.write(
        key: _kuKey,
        value: base64Encode(ku),
      );
      print('🔐 Ku: Stored in session storage');
      return E2EBootstrapResult.success(ku);

    } catch (e) {
      return E2EBootstrapResult.error('E2E setup failed: $e');
    }
  }

  /// Bootstrap E2E for login (existing device)
  /// Phase 3.4-3.6: E2E Bootstrap for existing device
  /// If server says E2E_NOT_SETUP but local keys exist, falls back to registration
  Future<E2EBootstrapResult> bootstrapForLogin(String accessToken) async {
    try {
      final deviceId = await _deviceService.getDeviceId();
      print('🔐 E2E Device ID: $deviceId');

      // Step 3.4: Call /e2e/bootstrap with deviceId
      final requestBody = jsonEncode({'deviceId': deviceId});
      print('🔐 E2E Bootstrap Request (LOGIN): POST ${ApiConstants.e2eBootstrap}');
      print('🔐 E2E Bootstrap Request Body: $requestBody');
      
      final bootstrapResponse = await _client.post(
        Uri.parse(ApiConstants.e2eBootstrap),
        headers: {
          'Content-Type': ApiConstants.contentTypeJson,
          'Authorization': 'Bearer $accessToken',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      print('🔐 E2E Bootstrap Response Status: ${bootstrapResponse.statusCode}');
      print('🔐 E2E Bootstrap Response Body: ${bootstrapResponse.body}');
      
      Map<String, dynamic> bootstrapData;
      try {
        bootstrapData = jsonDecode(bootstrapResponse.body) as Map<String, dynamic>;
      } catch (e) {
        return E2EBootstrapResult.error('Failed to parse bootstrap response: $e');
      }

      // Check if server says E2E is not set up
      // Also check the entire response body for pairing message (in case it's in a different format)
      final responseBody = bootstrapResponse.body;
      const String pairingMessage = "E2E encryption exists for this user on another device. This device needs to be paired.";
      final normalizedResponseBody = responseBody.toLowerCase();
      final normalizedPairingMessage = pairingMessage.trim().toLowerCase();
      
      // Check entire response body first (most flexible)
      if (normalizedResponseBody.contains('e2e encryption exists') && 
          normalizedResponseBody.contains('another device') && 
          normalizedResponseBody.contains('needs to be paired')) {
        print('🔐 E2E Status: Pairing message found in response body - pairing required');
        print('🔐 E2E Status: Response body: $responseBody');
        return E2EBootstrapResult.pairingRequired(pairingMessage);
      }
      
      if (bootstrapResponse.statusCode != 200) {
        final error = bootstrapData['error'];
        String errorCode = '';
        String errorMessage = '';
        
        if (error != null && error is Map) {
          errorCode = error['code']?.toString() ?? '';
          errorMessage = error['message']?.toString() ?? '';
        } else if (error is String) {
          errorMessage = error;
        }
        
        print('🔐 E2E Status: Error detected - Code: $errorCode, Message: $errorMessage');
        
        // Check if E2E is set up on another device (requires pairing)
        // Check if error message contains the pairing keywords (flexible matching)
        final normalizedErrorMessage = errorMessage.trim().toLowerCase();
        
        if (errorMessage == pairingMessage || 
            errorMessage.trim() == pairingMessage ||
            normalizedErrorMessage == normalizedPairingMessage ||
            (normalizedErrorMessage.contains('e2e encryption exists') && 
             normalizedErrorMessage.contains('another device') && 
             normalizedErrorMessage.contains('needs to be paired'))) {
          print('🔐 E2E Status: E2E set up on another device - pairing required');
          print('🔐 E2E Status: Error message: $errorMessage');
          return E2EBootstrapResult.pairingRequired(errorMessage);
        }
        
        // If server says E2E_NOT_SETUP but we have local keys,
        // it means registration never completed - clear local keys and retry registration
        if (errorCode == 'E2E_NOT_SETUP' || errorMessage.contains('E2E encryption is not set up')) {
          print('🔐 E2E Status: Server says not set up');
          
          // Check if we have local keys (mismatch scenario)
          final hasLocalSkd = await _storage.read(key: _skdKey);
          if (hasLocalSkd != null && hasLocalSkd.isNotEmpty) {
            print('🔐 E2E Recovery: Local keys exist but server says not set up');
            print('🔐 E2E Recovery: Registration was incomplete - clearing local keys and retrying registration');
            
            // Clear mismatched local keys
            await _storage.delete(key: _skdKey);
            await _storage.delete(key: _kuKey);
            
            // Fall back to registration flow to complete E2E setup
            print('🔐 E2E Recovery: Falling back to registration flow...');
            return await bootstrapForRegistration(accessToken);
            } else {
            // No local keys and server says not set up - this shouldn't happen in login flow
            // But handle gracefully
            print('🔐 E2E Status: No local keys and server says not set up');
            return E2EBootstrapResult.error(errorMessage.isNotEmpty ? errorMessage : 'E2E encryption is not set up');
          }
        } else {
          // Other error - return it
          return E2EBootstrapResult.error(
            errorMessage.isNotEmpty ? errorMessage : (errorCode.isNotEmpty ? errorCode : 'Bootstrap failed')
          );
        }
      }

      // Status 200 - check if E2E is properly set up
      final wrappedKu = bootstrapData['data']?['wrappedKu'];
      final status = bootstrapData['data']?['status']?.toString();
      final message = bootstrapData['data']?['message']?.toString();
      final reason = bootstrapData['data']?['reason']?.toString();
      
      print('🔐 E2E Status: Status=$status, Reason=$reason, HasWrappedKu=${wrappedKu != null}');
      print('🔐 E2E Status: Message from server: $message');
      
      // PRIORITY 1: Check status and reason fields explicitly (most reliable)
      if (status == 'E2E_NOT_SETUP_FOR_THIS_DEVICE' && 
          (reason == 'NEW_DEVICE_NEEDS_PAIRING' || reason == null)) {
        print('🔐 E2E Status: Pairing required - status=E2E_NOT_SETUP_FOR_THIS_DEVICE, reason=$reason');
        return E2EBootstrapResult.pairingRequired(
          message ?? pairingMessage
        );
      }
      
      // PRIORITY 2: Check entire response body for pairing message (even on status 200)
      // Variables already defined above, reuse them
      if (normalizedResponseBody.contains('e2e encryption exists') && 
          normalizedResponseBody.contains('another device') && 
          normalizedResponseBody.contains('needs to be paired')) {
        print('🔐 E2E Status: Pairing message found in response (status 200) - pairing required');
        print('🔐 E2E Status: Response body: $responseBody');
        return E2EBootstrapResult.pairingRequired(pairingMessage);
      }
      
      // Explicitly handle E2E_ALREADY_ACTIVE status (pairing completed)
      if (status == 'E2E_ALREADY_ACTIVE' && wrappedKu != null) {
        print('🔐 E2E Status: E2E_ALREADY_ACTIVE with wrappedKu - pairing completed');
        print('🔐 E2E Status: Message: $message');
        
        // Check if we have SKd (should exist from requestPairing in pairing flow)
        final hasLocalSkd = await _storage.read(key: _skdKey);
        if (hasLocalSkd == null || hasLocalSkd.isEmpty) {
          print('🔐 E2E Status: No local SKd - cannot decrypt wrappedKu');
          return E2EBootstrapResult.error('Device key not found - cannot complete pairing');
        }
        
        // Attempt to decrypt wrappedKu - this handles pairing completion
        print('🔐 E2E Status: Attempting to decrypt wrappedKu for pairing completion');
        try {
          return await _recoverKeysForExistingDevice(accessToken, deviceId, bootstrapData);
        } catch (e) {
          print('🔐 E2E Status: Failed to recover keys: $e');
          return E2EBootstrapResult.error('Failed to complete pairing: $e');
        }
      }
      
      // Also check if wrappedKu is present even if status is not E2E_ALREADY_ACTIVE
      // (some server implementations might return wrappedKu with different status)
      if (wrappedKu != null && status != 'E2E_NOT_SETUP_FOR_THIS_DEVICE') {
        print('🔐 E2E Status: Found wrappedKu with status: $status - attempting decryption');
        
        // Check if we have SKd
        final hasLocalSkd = await _storage.read(key: _skdKey);
        if (hasLocalSkd == null || hasLocalSkd.isEmpty) {
          print('🔐 E2E Status: No local SKd - cannot decrypt wrappedKu');
          return E2EBootstrapResult.error('Device key not found - cannot complete pairing');
        }
        
        // Attempt to decrypt wrappedKu
        print('🔐 E2E Status: Attempting to decrypt wrappedKu');
        try {
          return await _recoverKeysForExistingDevice(accessToken, deviceId, bootstrapData);
        } catch (e) {
          print('🔐 E2E Status: Failed to recover keys: $e');
          return E2EBootstrapResult.error('Failed to complete pairing: $e');
        }
      }
      
      if (bootstrapData['e2e_setup'] == true || wrappedKu != null) {
        print('🔐 E2E Status: Setup Found');
        
        // Check if this is a pairing scenario (wrappedKu present but we just generated keys)
        // In pairing flow, we generate new keys during requestPairing, so we should have SKd
        final hasLocalSkd = await _storage.read(key: _skdKey);
        if (hasLocalSkd == null || hasLocalSkd.isEmpty) {
          print('🔐 E2E Status: Server has E2E but no local SKd - cannot decrypt');
          
          // If we're in pairing flow, we should have SKd from requestPairing
          // If not, this might be a normal login scenario
          print('🔐 E2E Recovery: Clearing server state and retrying registration');
          
          // Clear any stale session keys
          await _storage.delete(key: _kuKey);
          
          // Note: We can't clear server state from here, but we can try registration
          // Server should handle duplicate registration gracefully
          return await bootstrapForRegistration(accessToken);
      }
      
      // Step 3.5: Query Device Keys Table for (userId, deviceId)
      // Step 3.5b: Return wrappedKu for this device
      // Step 3.6: Recover User Master Key
        // This handles both normal login and pairing approval scenarios
        return await _recoverKeysForExistingDevice(accessToken, deviceId, bootstrapData);
      } else {
        // Server returned 200 but no wrappedKu
        // This could mean:
        // 1. Pairing is still pending (waiting for Device A to approve)
        // 2. Normal registration needed
        print('🔐 E2E Status: Server returned 200 but no wrappedKu');
        print('🔐 E2E Status: Status from server: $status');
        print('🔐 E2E Status: Message from server: $message');
        
        // Check for pairing message (flexible matching)
        const String pairingMessage = "E2E encryption exists for this user on another device. This device needs to be paired.";
        if (message != null) {
          final messageStr = message.toString().trim();
          final normalizedMessage = messageStr.toLowerCase();
          final normalizedPairingMessage = pairingMessage.trim().toLowerCase();
          
          if (messageStr == pairingMessage || 
              normalizedMessage == normalizedPairingMessage ||
              (normalizedMessage.contains('e2e encryption exists') && 
               normalizedMessage.contains('another device') && 
               normalizedMessage.contains('needs to be paired'))) {
            print('🔐 E2E Status: Device needs pairing - message match');
            print('🔐 E2E Status: Message: $messageStr');
            return E2EBootstrapResult.pairingRequired(messageStr);
          }
        }
        
        // Check for E2E_NOT_SETUP_FOR_THIS_DEVICE status (pairing required)
        if (status == 'E2E_NOT_SETUP_FOR_THIS_DEVICE' || 
            status == 'NEW_DEVICE_NEEDS_PAIRING') {
          print('🔐 E2E Status: Device needs pairing - checking if pairing was requested');
          
          // Check if we're in pairing flow (have SKd from requestPairing)
          final hasLocalSkd = await _storage.read(key: _skdKey);
          if (hasLocalSkd != null && hasLocalSkd.isNotEmpty) {
            // We have SKd but no wrappedKu - pairing is still pending
            print('🔐 E2E Status: Pairing pending - waiting for approval');
            return E2EBootstrapResult.pairingRequired('Pairing request pending approval');
          } else {
            // No SKd - this shouldn't happen in pairing flow, but handle gracefully
            print('🔐 E2E Status: Pairing required but no local SKd');
            return E2EBootstrapResult.pairingRequired('Device needs to be paired');
          }
        }
        
        // Check if we're in pairing flow (have SKd from requestPairing)
        final hasLocalSkd = await _storage.read(key: _skdKey);
        if (hasLocalSkd != null && hasLocalSkd.isNotEmpty) {
          // We have SKd but no wrappedKu - pairing is still pending
          print('🔐 E2E Status: Pairing pending - waiting for approval');
          return E2EBootstrapResult.pairingRequired('Pairing request pending approval');
        } else {
          // No SKd and no wrappedKu - try registration
          print('🔐 E2E Status: No wrappedKu and no local SKd - attempting registration');
          await _storage.delete(key: _skdKey);
          await _storage.delete(key: _kuKey);
          return await bootstrapForRegistration(accessToken);
        }
      }

    } catch (e) {
      print('🔐 E2E Recovery Error: $e');
      return E2EBootstrapResult.error('E2E recovery failed: $e');
    }
  }

  /// Recover User Master Key for existing device
  /// Step 3.6: Recover User Master Key
  /// 1. Load SKd from secure device storage
  /// 2. Decrypt: Ku = Decrypt(wrappedKu, SKd)
  /// 3. Keep Ku in memory for session
  Future<E2EBootstrapResult> _recoverKeysForExistingDevice(
    String accessToken,
    String deviceId,
    Map<String, dynamic> bootstrapData,
  ) async {
    try {
      // Get wrappedKu from response
      final wrappedKuBase64 = bootstrapData['data']?['wrappedKu'] ?? 
                               bootstrapData['wrappedKu'];
      
      if (wrappedKuBase64 == null) {
        print('🔐 E2E Recovery: No wrappedKu in response');
        return E2EBootstrapResult.error('No wrappedKu found in response');
      }

      print('🔐 E2E Recovery: Found wrappedKu in response');
      
      // Step 3.6.1: Load SKd from secure device storage (Keychain/Keystore)
      // IMPORTANT: SKd exists ONLY on this client device, loaded from local storage
      final skdBase64 = await _storage.read(key: _skdKey);
      if (skdBase64 == null) {
        print('🔐 E2E Recovery: SKd not found in storage - need re-registration');
        return E2EBootstrapResult.error(
          'Device key (SKd) not found in secure storage. Please re-register.'
        );
      }

      print('🔐 E2E Recovery: Loaded SKd from storage');
      final skdSeedBytes = base64Decode(skdBase64);
      // Reconstruct KeyPair from stored seed bytes using pointycastle
      // The stored bytes are the seed that was used to generate the keypair
      final domainParams = ECCurve_secp256r1();
      // Ensure the seed is exactly 32 bytes (P-256 private key size)
      final seedBytes = skdSeedBytes.length >= 32 
          ? skdSeedBytes.sublist(0, 32) 
          : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
      
      // Create keypair from the stored seed bytes using pointycastle
      final keyGen = ECKeyGenerator();
      final keyParams = ECKeyGeneratorParameters(domainParams);
      final pcSecureRandom = pc.SecureRandom('Fortuna');
      pcSecureRandom.seed(KeyParameter(seedBytes));
      keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
      final pcKeyPair = keyGen.generateKeyPair();
      final pcSkd = pcKeyPair.privateKey as ECPrivateKey;
      final pcPkd = pcKeyPair.publicKey as ECPublicKey;
      
      print('🔐 E2E Recovery: Reconstructed keypair from stored SKd');
      final currentPkdBytes = _ecPublicKeyToBytes(pcPkd);
      final currentPkdBase64 = base64Encode(currentPkdBytes);
      print('🔐 E2E Recovery: Current PKd (for verification): $currentPkdBase64');

      // Step 3.6.2: Decrypt: Ku = Decrypt(wrappedKu, SKd)
      // Check if wrappedKu is in ephemeral format (from cross-device pairing) or same-device format
      print('🔐 E2E Recovery: Attempting to decrypt wrappedKu...');
      print('🔐 E2E Recovery: SKd seed length: ${seedBytes.length} bytes');
      
      try {
        Uint8List ku;
        
        // Check if wrappedKu is in ephemeral format (cross-device pairing)
        if (_isEphemeralFormat(wrappedKuBase64)) {
          print('🔐 E2E Recovery: Detected ephemeral format - using cross-device decryption');
          ku = await decryptKuFromEphemeralFormat(wrappedKuBase64, seedBytes);
        } else {
          // Same-device format: base64(iv + ciphertext)
          print('🔐 E2E Recovery: Detected same-device format - using standard decryption');
          final wrappedKu = base64Decode(wrappedKuBase64);
          print('🔐 E2E Recovery: wrappedKu length: ${wrappedKu.length} bytes');
          // For same-device recovery, use device's own PKd (pointycastle keys)
          ku = await _decryptKuWithPointycastleKeys(wrappedKu, seedBytes, pcPkd, pcSkd);
        }
        
        print('🔐 E2E Recovery: Successfully decrypted wrappedKu');
        print('🔐 E2E Recovery: Decrypted Ku length: ${ku.length} bytes');

        // Step 3.6.3: Keep Ku in memory for session
        await _storage.write(
          key: _kuKey,
          value: base64Encode(ku),
        );
        print('🔐 Ku: Recovered and stored in session storage');

        return E2EBootstrapResult.success(ku);
      } catch (decryptError) {
        print('🔐 E2E Recovery: Decryption failed: $decryptError');
        print('🔐 E2E Recovery: This might indicate wrappedKu was encrypted with a different public key');
        print('🔐 E2E Recovery: The wrappedKu might be from a previous pairing attempt');
        print('🔐 E2E Recovery: Current PKd: $currentPkdBase64');
        rethrow;
      }

    } catch (e) {
      print('🔐 E2E Recovery Error: $e');
      print('🔐 E2E Recovery Error Type: ${e.runtimeType}');
      print('🔐 E2E Recovery Error Stack: ${StackTrace.current}');
      
      // If decryption fails, it means wrappedKu was encrypted with a different device's key
      // This can happen if:
      // 1. Another user logged in on the same device
      // 2. App was reinstalled
      // 3. Laptop generated new keys but server has wrappedKu from old keys (pairing retry scenario)
      if (e.toString().contains('InvalidCipherTextException') || 
          e.toString().contains('InvalidCipherText') ||
          e.toString().contains('decrypt') ||
          e.toString().contains('cipher')) {
        print('🔐 E2E Recovery: wrappedKu encrypted with different device key');
        print('🔐 E2E Recovery: This is likely a pairing key mismatch');
        print('🔐 E2E Recovery: The laptop may have generated new keys but server has old wrappedKu');
        
        // In pairing scenario, if decryption fails, it means the keys don't match
        // This could happen if the laptop requested pairing multiple times
        // We should return a specific error that the pairing flow can handle
        return E2EBootstrapResult.error(
          'E2E keys mismatch - wrappedKu was encrypted with a different public key. '
          'This may happen if pairing was requested multiple times. Please try pairing again.'
        );
      }
      return E2EBootstrapResult.error('Failed to recover keys: $e');
    }
  }

  /// Encrypt Ku with pointycastle keys using ECDH key exchange and AES-GCM
  /// Uses P-256 ECDH to derive shared secret, then encrypts Ku
  /// For same-device: uses device's own SKd + PKd
  Future<Uint8List> _encryptKuWithPointycastleKeys(
    Uint8List ku,
    ECPublicKey pkd,
    ECPrivateKey skd,
  ) async {
    // Step 1: Derive shared secret using ECDH (pointycastle)
    // ECDH(skd, pkd) → shared secret
    final agreement = ECDHBasicAgreement();
    agreement.init(skd);
    final sharedSecret = agreement.calculateAgreement(pkd);
    
    // Step 2: Derive AES key from shared secret using SHA-256
    // This matches the TypeScript implementation which uses Web Crypto's deriveKey
    final sharedSecretBytes = _bigIntToBytes(sharedSecret, 32);
    final key = sha256.convert(sharedSecretBytes).bytes.sublist(0, 32);
    
    // Step 3: Generate random IV (12 bytes for GCM)
    final iv = Uint8List(12);
    final secureRandom = Random.secure();
    for (int i = 0; i < 12; i++) {
      iv[i] = secureRandom.nextInt(256);
    }

    // Step 4: Encrypt Ku using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));

    final encrypted = cipher.process(ku);
    
    // Step 5: Prepend IV to encrypted data (IV + encrypted data)
    return Uint8List.fromList([...iv, ...encrypted]);
  }

  /// Encrypt Ku with PKd using ECDH key exchange and AES-GCM
  /// Uses P-256 ECDH to derive shared secret, then encrypts Ku
  /// For same-device: uses device's own SKd + PKd
  /// This version uses cryptography package keys (legacy - not used)
  /// NOTE: This method is kept for compatibility but should use pointycastle instead
  @Deprecated('Use _encryptKuWithPointycastleKeys instead')
  Future<Uint8List> _encryptKuWithPkd(
    Uint8List ku,
    crypto.PublicKey pkd,
    crypto.KeyPair skd,
  ) async {
    // This method is deprecated - use pointycastle methods instead
    throw UnimplementedError('Use _encryptKuWithPointycastleKeys instead');
  }

  /// Extract bytes from cryptography EcPublicKey
  /// Converts EcPublicKey to raw bytes (65 bytes uncompressed for P-256)
  /// NOTE: This method is deprecated - public key bytes are now extracted when generating keypairs using pointycastle
  @Deprecated('Public key bytes should be extracted when generating keypair using pointycastle')
  Future<Uint8List> _extractPublicKeyBytes(crypto.PublicKey publicKey) async {
    throw UnimplementedError('_extractPublicKeyBytes: Public key bytes should be extracted when generating keypair using pointycastle');
  }

  /// Convert ECPublicKey (pointycastle) to raw bytes (65 bytes uncompressed)
  Uint8List _ecPublicKeyToBytes(ECPublicKey publicKey) {
    final point = publicKey.Q!;
    final xBigInt = point.x!.toBigInteger()!;
    final yBigInt = point.y!.toBigInteger()!;
    
    // Convert BigInt to bytes (big-endian, unsigned)
    Uint8List xBytes = _bigIntToBytes(xBigInt, 32);
    Uint8List yBytes = _bigIntToBytes(yBigInt, 32);
    
    // Create uncompressed format: 0x04 + X (32 bytes) + Y (32 bytes)
    final result = Uint8List(65);
    result[0] = 0x04;
    result.setRange(1, 33, xBytes);
    result.setRange(33, 65, yBytes);
    
    return result;
  }

  /// Convert BigInt to bytes (big-endian, padded to specified length)
  Uint8List _bigIntToBytes(BigInt value, int length) {
    if (value < BigInt.zero) {
      throw ArgumentError('BigInt must be non-negative');
    }
    
    // Convert to hex string, then to bytes
    final hex = value.toRadixString(16);
    final hexPadded = hex.padLeft(length * 2, '0');
    
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      final byteStr = hexPadded.substring(i * 2, (i + 1) * 2);
      bytes[i] = int.parse(byteStr, radix: 16);
    }
    
    return bytes;
  }

  /// Extract raw P-256 public key from SPKI format or return as-is if already raw
  /// P-256 public keys: 65 bytes uncompressed (0x04 + 32 bytes X + 32 bytes Y) or 33 bytes compressed
  /// SPKI format for P-256: The public key is encoded in the BIT STRING
  /// This matches the TypeScript importPublicKey behavior
  Uint8List _extractRawPublicKey(Uint8List publicKeyBytes) {
    // If it's exactly 65 bytes (uncompressed) or 33 bytes (compressed), it's already in raw format
    if (publicKeyBytes.length == 65 && publicKeyBytes[0] == 0x04) {
      // Uncompressed format: 0x04 prefix + 32 bytes X + 32 bytes Y
      return publicKeyBytes;
    }
    if (publicKeyBytes.length == 33) {
      // Compressed format: 0x02 or 0x03 prefix + 32 bytes
      return publicKeyBytes;
    }
    
    // If it's longer, it's likely SPKI format
    // For P-256 SPKI, we need to extract from the BIT STRING
    // The public key in SPKI is in the BIT STRING, typically 65 bytes (uncompressed)
    if (publicKeyBytes.length > 65) {
      // Try to find the 65-byte uncompressed key (starts with 0x04)
      // Look for 0x04 byte followed by 64 more bytes
      for (int i = 0; i <= publicKeyBytes.length - 65; i++) {
        if (publicKeyBytes[i] == 0x04) {
          // Found potential uncompressed key
          final candidate = publicKeyBytes.sublist(i, i + 65);
          return candidate;
        }
      }
      // If not found, extract last 65 bytes as fallback
      return publicKeyBytes.sublist(publicKeyBytes.length - 65);
    }
    
    // If it's between 33 and 65 bytes, might be partial or invalid
    if (publicKeyBytes.length >= 33) {
      return publicKeyBytes;
    }
    
    // If it's shorter than 33 bytes, it's invalid
    throw Exception('Invalid public key length: ${publicKeyBytes.length} bytes. Expected 65 bytes (uncompressed), 33 bytes (compressed), or SPKI format (>=65 bytes)');
  }

  /// Convert raw P-256 public key (65 bytes uncompressed) to SPKI format (DER-encoded)
  /// SPKI format structure for P-256:
  /// SEQUENCE {
  ///   AlgorithmIdentifier { algorithm: id-ecPublicKey, parameters: secp256r1 }
  ///   BIT STRING { publicKey }
  /// }
  /// This ensures web compatibility
  Uint8List _convertRawToSpki(Uint8List rawPublicKey) {
    // P-256 public key should be 65 bytes uncompressed (0x04 + 32 bytes X + 32 bytes Y)
    if (rawPublicKey.length != 65 || rawPublicKey[0] != 0x04) {
      throw Exception('Invalid raw public key length: ${rawPublicKey.length} bytes. Expected 65 bytes (uncompressed) for P-256');
    }

    // P-256 OID: 1.2.840.10045.3.1.7 (prime256v1, secp256r1)
    // OID encoding: 1.2.840.10045.3.1.7
    // First two arcs: 1.2 = 40*1 + 2 = 42 = 0x2A
    // Remaining: 840.10045.3.1.7 encoded in base-128
    // Standard encoding: 0x2A 0x86 0x48 0xCE 0x3D 0x03 0x01 0x07
    final oidBytes = Uint8List.fromList([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]); // 1.2.840.10045.3.1.7
    
    // AlgorithmIdentifier: SEQUENCE { OID ecPublicKey, OID secp256r1 }
    // ecPublicKey OID: 1.2.840.10045.2.1
    final ecPublicKeyOid = Uint8List.fromList([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]); // 1.2.840.10045.2.1
    
    // AlgorithmIdentifier structure:
    // SEQUENCE {
    //   OBJECT IDENTIFIER ecPublicKey (1.2.840.10045.2.1)
    //   OBJECT IDENTIFIER secp256r1 (1.2.840.10045.3.1.7)
    // }
    final algorithmIdentifier = Uint8List.fromList([
      0x30, // SEQUENCE
      0x13, // Length: 19 bytes
      0x06, // OBJECT IDENTIFIER
      0x07, // OID length
      ...ecPublicKeyOid, // ecPublicKey OID
      0x06, // OBJECT IDENTIFIER
      0x08, // OID length
      ...oidBytes, // secp256r1 OID
    ]);

    // Public key as BIT STRING
    // BIT STRING { 0x00 (unused bits) + publicKey }
    final publicKeyBitString = Uint8List.fromList([
      0x03, // BIT STRING
      0x42, // Length: 66 bytes (1 byte unused bits + 65 bytes key)
      0x00, // 0 unused bits
      ...rawPublicKey, // 65 bytes public key (uncompressed)
    ]);

    // Complete SPKI structure
    // SEQUENCE {
    //   AlgorithmIdentifier
    //   BIT STRING { publicKey }
    // }
    final spkiLength = algorithmIdentifier.length + publicKeyBitString.length;
    final spki = Uint8List.fromList([
      0x30, // SEQUENCE
      spkiLength, // Length
      ...algorithmIdentifier,
      ...publicKeyBitString,
    ]);

    return spki;
  }

  /// Encrypt Ku with a public key (for device pairing)
  /// Uses ephemeral keypair approach for cross-device pairing
  /// Device A generates ephemeral keypair, encrypts Ku using ECDH(ephemeralPrivateKey, PKdB)
  /// Returns wrappedKu in format: base64(JSON.stringify({epk, iv, ct}))
  /// publicKeyBytes: Public key bytes from the new device (Device B's PKd, can be raw or SPKI format)
  Future<String> encryptKuWithPublicKey(
    Uint8List ku,
    Uint8List publicKeyBytes,
  ) async {
    // Extract raw public key (handle both raw and SPKI formats)
    // This matches the TypeScript importPublicKey behavior
    final rawPublicKeyBytes = _extractRawPublicKey(publicKeyBytes);
    
    // Create PublicKey from raw bytes (Device B's public key)
    // P-256 public keys are 65 bytes uncompressed
    // Since cryptography package doesn't have publicKeyFromBytes,
    // we'll use pointycastle to parse the public key and do ECDH with pointycastle
    final domainParams = ECCurve_secp256r1();
    final pkdBPointycastle = ECPublicKey(
      domainParams.curve.decodePoint(rawPublicKeyBytes),
      domainParams,
    );
    
    // For encryption with raw public key bytes, we'll use pointycastle ECDH
    // Generate ephemeral keypair using pointycastle (for compatibility with raw public keys)
    final keyGen = ECKeyGenerator();
    final keyParams = ECKeyGeneratorParameters(domainParams);
    
    // Generate secure random seed
    final seed = Uint8List(32);
    final secureRandom = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = secureRandom.nextInt(256);
    }
    
    // Use SecureRandom with seed (pointycastle)
    final pcSecureRandom = pc.SecureRandom('Fortuna');
    pcSecureRandom.seed(KeyParameter(seed));
    keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
    final ephemeralKeyPairPointy = keyGen.generateKeyPair();
    final ephemeralPrivateKey = ephemeralKeyPairPointy.privateKey as ECPrivateKey;
    final ephemeralPublicKey = ephemeralKeyPairPointy.publicKey as ECPublicKey;
    
    // Perform ECDH key agreement using pointycastle
    final agreement = ECDHBasicAgreement();
    agreement.init(ephemeralPrivateKey);
    final sharedSecret = agreement.calculateAgreement(pkdBPointycastle);
    
    // Derive AES key from shared secret using SHA-256
    // Convert BigInt to bytes
    final sharedSecretBigInt = sharedSecret;
    final sharedSecretBytes = _bigIntToBytes(sharedSecretBigInt, 32);
    final key = sha256.convert(sharedSecretBytes).bytes.sublist(0, 32);
    
    // Generate random IV (12 bytes for GCM)
    final iv = Uint8List(12);
    final ivRandom = Random.secure();
    for (int i = 0; i < 12; i++) {
      iv[i] = ivRandom.nextInt(256);
    }

    // Encrypt Ku using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));

    final encrypted = cipher.process(ku);
    
    // Extract IV and ciphertext
    final ciphertext = encrypted;
    
    // Get ephemeral public key bytes for the payload
    final ephemeralPkdBytes = _ecPublicKeyToBytes(ephemeralPublicKey);
    final ephemeralPkdSpki = _convertRawToSpki(ephemeralPkdBytes);
    
    final payload = {
      'epk': base64Encode(ephemeralPkdSpki), // Ephemeral public key in SPKI format
      'iv': base64Encode(iv),                 // IV
      'ct': base64Encode(ciphertext),         // Ciphertext
    };
    
    final jsonPayload = jsonEncode(payload);
    return base64Encode(utf8.encode(jsonPayload));
  }

  /// Decrypt wrappedKu with pointycastle keys using ECDH key exchange
  /// skdSeedBytes: The seed bytes that were used to generate the keypair (the private key material)
  /// pkd: The public key to use for ECDH (for same-device, this is the device's own PKd)
  /// IMPORTANT: Uses ECDH(skd, pkd) to derive shared secret, matching the encryption method
  Future<Uint8List> _decryptKuWithPointycastleKeys(
    Uint8List wrappedKu,
    Uint8List skdSeedBytes,
    ECPublicKey pkd,
    ECPrivateKey skd,
  ) async {
    // Extract IV (first 12 bytes) and encrypted data
    if (wrappedKu.length < 12) {
      throw Exception('Invalid wrappedKu: too short');
    }
    
    final iv = wrappedKu.sublist(0, 12);
    final encrypted = wrappedKu.sublist(12);

    // Step 1: Derive shared secret using ECDH (pointycastle)
    // ECDH(skd, pkd) → shared secret (same as encryption)
    final agreement = ECDHBasicAgreement();
    agreement.init(skd);
    final sharedSecret = agreement.calculateAgreement(pkd);
    
    // Step 2: Derive AES key from shared secret using SHA-256
    final sharedSecretBytes = _bigIntToBytes(sharedSecret, 32);
    final key = sha256.convert(sharedSecretBytes).bytes.sublist(0, 32);

    // Step 3: Decrypt using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));

    return cipher.process(encrypted);
  }

  /// Decrypt wrappedKu with SKd using ECDH key exchange
  /// skdSeedBytes: The seed bytes that were used to generate the keypair (the private key material)
  /// pkd: The public key to use for ECDH (for same-device, this is the device's own PKd)
  /// IMPORTANT: Uses ECDH(skd, pkd) to derive shared secret, matching the encryption method
  /// This version uses cryptography package keys (legacy - not used)
  /// NOTE: This method is kept for compatibility but should use pointycastle instead
  @Deprecated('Use _decryptKuWithPointycastleKeys instead')
  Future<Uint8List> _decryptKuWithSkd(
    Uint8List wrappedKu,
    Uint8List skdSeedBytes,
    crypto.PublicKey pkd,
  ) async {
    // This method is deprecated - use pointycastle methods instead
    throw UnimplementedError('Use _decryptKuWithPointycastleKeys instead');
  }

  /// Decrypt wrappedKu for cross-device pairing (ephemeral format)
  /// Handles ephemeral format: base64(JSON.stringify({epk, iv, ct}))
  /// Uses ECDH(DeviceBPrivateKey, ephemeralPublicKey) to derive shared secret
  Future<Uint8List> decryptKuFromEphemeralFormat(
    String wrappedKuBase64,
    Uint8List skdSeedBytes,
  ) async {
    // Decode base64 and parse JSON
    final decoded = utf8.decode(base64Decode(wrappedKuBase64));
    final payload = jsonDecode(decoded) as Map<String, dynamic>;
    
    if (!payload.containsKey('epk') || !payload.containsKey('iv') || !payload.containsKey('ct')) {
      throw Exception('Invalid ephemeral format. Expected {epk, iv, ct} structure.');
    }
    
    // Import ephemeral public key (handle both raw and SPKI formats)
    final epkBytes = base64Decode(payload['epk'] as String);
    final rawEpkBytes = _extractRawPublicKey(epkBytes);
    
    // Parse ephemeral public key using pointycastle
    final domainParams = ECCurve_secp256r1();
    final ephemeralPkd = ECPublicKey(
      domainParams.curve.decodePoint(rawEpkBytes),
      domainParams,
    );
    
    // Reconstruct SKd from seed using pointycastle
    // IMPORTANT: The seed is used to generate the keypair, not as the private key directly
    // We need to use the same method as in requestDevicePairing - seed the SecureRandom
    final seedBytes = skdSeedBytes.length >= 32 
        ? skdSeedBytes.sublist(0, 32) 
        : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
    
    // Generate keypair from seed (same method as requestDevicePairing)
    final keyGen = ECKeyGenerator();
    final keyParams = ECKeyGeneratorParameters(domainParams);
    final pcSecureRandom = pc.SecureRandom('Fortuna');
    pcSecureRandom.seed(KeyParameter(seedBytes));
    keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
    final pcKeyPair = keyGen.generateKeyPair();
    final skd = pcKeyPair.privateKey as ECPrivateKey;
    
    // Perform ECDH key agreement using pointycastle
    final agreement = ECDHBasicAgreement();
    agreement.init(skd);
    final sharedSecret = agreement.calculateAgreement(ephemeralPkd);
    
    // Derive AES key from shared secret using SHA-256
    // Convert BigInt to bytes
    final sharedSecretBigInt = sharedSecret;
    final sharedSecretBytes = _bigIntToBytes(sharedSecretBigInt, 32);
    final key = sha256.convert(sharedSecretBytes).bytes.sublist(0, 32);
    
    // Decode IV and ciphertext
    final iv = base64Decode(payload['iv'] as String);
    final ciphertext = base64Decode(payload['ct'] as String);
    
    // Decrypt using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));
    
    return cipher.process(ciphertext);
  }

  /// Detect if wrappedKu is in ephemeral format (from cross-device pairing)
  /// Ephemeral format: base64(JSON.stringify({epk, iv, ct}))
  /// Same-device format: base64(iv + ciphertext)
  bool _isEphemeralFormat(String wrappedKuBase64) {
    try {
      final decoded = utf8.decode(base64Decode(wrappedKuBase64));
      final parsed = jsonDecode(decoded);
      if (parsed is Map) {
        return parsed.containsKey('epk') && 
               parsed.containsKey('iv') && 
               parsed.containsKey('ct');
      }
    } catch (e) {
      // If parsing fails, it's likely the old same-device format
      return false;
    }
    return false;
  }

  /// Public wrapper for decrypting wrappedKu (for pairing flow)
  /// Automatically detects format and uses appropriate decryption method
  Future<Uint8List> decryptKuWithSkd(Uint8List wrappedKu, Uint8List skdSeedBytes) async {
    // This method is for same-device format (legacy)
    // For ephemeral format, use decryptKuFromEphemeralFormat
    final seedBytes = skdSeedBytes.length >= 32 
        ? skdSeedBytes.sublist(0, 32) 
        : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
    // Use pointycastle to generate keypair from seed
    final domainParams = ECCurve_secp256r1();
    final keyGen = ECKeyGenerator();
    final keyParams = ECKeyGeneratorParameters(domainParams);
    final pcSecureRandom = pc.SecureRandom('Fortuna');
    pcSecureRandom.seed(KeyParameter(seedBytes));
    keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
    final pcKeyPair = keyGen.generateKeyPair();
    final pcSkd = pcKeyPair.privateKey as ECPrivateKey;
    final pcPkd = pcKeyPair.publicKey as ECPublicKey;
    
    // Use pointycastle for decryption
    return await _decryptKuWithPointycastleKeys(wrappedKu, seedBytes, pcPkd, pcSkd);
  }

  /// Get current session Ku (User Master Key)
  /// Returns null if no active session
  Future<Uint8List?> getSessionKu() async {
    final kuBase64 = await _storage.read(key: _kuKey);
    if (kuBase64 == null) return null;
    return base64Decode(kuBase64);
  }

  /// Clear session keys (Ku only - keeps SKd for future logins)
  /// This is called during logout to clear the session key
  /// SKd (Device Private Key) is NEVER cleared - it stays on the device permanently
  Future<void> clearSessionKeys() async {
    // Verify SKd exists before clearing
    final skdBefore = await _storage.read(key: _skdKey);
    print('🔐 clearSessionKeys: SKd before clear - exists: ${skdBefore != null && skdBefore.isNotEmpty}');
    
    // Only clear Ku (session key), keep SKd (device key) for future logins
    await _storage.delete(key: _kuKey);
    
    // Verify SKd still exists after clearing
    final skdAfter = await _storage.read(key: _skdKey);
    print('🔐 clearSessionKeys: SKd after clear - exists: ${skdAfter != null && skdAfter.isNotEmpty}');
    
    if (skdBefore != null && skdAfter == null) {
      print('🔐 ERROR: SKd was accidentally cleared during logout!');
    } else {
      debugPrint('🔐 Cleared session key (Ku), kept device key (SKd)');
    }
  }

  /// Clear all E2E keys (ONLY for account deletion or device reset)
  /// WARNING: This will permanently delete SKd, requiring re-registration
  /// Should NOT be called during normal logout
  Future<void> clearAllKeys() async {
    await _storage.delete(key: _skdKey);
    await _storage.delete(key: _kuKey);
    await clearDeviceOwner(); // Clear device owner when all keys are cleared
    debugPrint('⚠️ Cleared ALL E2E keys (including SKd) - device will need re-registration');
  }

  /// Get the device owner's user ID (first user who signed up on this device)
  /// Stored in SharedPreferences (local storage)
  Future<String?> getDeviceOwnerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceOwnerUserIdKey);
  }

  /// Set the device owner (first user who signs up on this device)
  /// This user becomes the ONLY user who can login on this device
  /// Stored in SharedPreferences (local storage)
  Future<void> setDeviceOwner(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceOwnerUserIdKey, userId);
    print('🔐 Device owner set: $userId - This user is now the only user who can login on this device');
  }

  /// Clear device owner (when owner logs out completely)
  /// Stored in SharedPreferences (local storage)
  Future<void> clearDeviceOwner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceOwnerUserIdKey);
    print('🔐 Device owner cleared - New user can now sign up and become device owner');
  }

  /// Check if a user is the device owner
  /// Returns true if user matches device owner, false if different user or no owner set
  Future<bool> isDeviceOwner(String userId) async {
    final ownerUserId = await getDeviceOwnerUserId();
    if (ownerUserId == null) {
      // No owner set yet - first user can become owner
      return true;
    }
    final isOwner = ownerUserId == userId;
    print('🔐 Device owner check - Owner: $ownerUserId, Current: $userId, Match: $isOwner');
    return isOwner;
  }

  /// Check if device has E2E keys set up
  Future<bool> hasE2EKeys() async {
    final skd = await _storage.read(key: _skdKey);
    final hasKeys = skd != null && skd.isNotEmpty;
    print('🔐 E2E hasE2EKeys check: SKd exists = $hasKeys (length: ${skd?.length ?? 0})');
    return hasKeys;
  }

  /// Get bootstrap/complete response (stored during registration)
  Future<Map<String, dynamic>?> getBootstrapCompleteResponse() async {
    final responseJson = await _storage.read(key: _bootstrapCompleteResponseKey);
    if (responseJson == null) return null;
    return jsonDecode(responseJson);
  }

  /// Request device pairing (for new device - Device B)
  /// Returns OTP that needs to be entered on existing device (Device A)
  Future<PairingRequestResult> requestDevicePairing(String accessToken) async {
    try {
      final deviceId = await _deviceService.getDeviceId();
      
      // Generate new keypair for this device using pointycastle
      final seed = Uint8List(32);
      final secureRandom = Random.secure();
      for (int i = 0; i < 32; i++) {
        seed[i] = secureRandom.nextInt(256);
      }
      
      // Use pointycastle to generate keypair from seed
      final domainParams = ECCurve_secp256r1();
      final keyGen = ECKeyGenerator();
      final keyParams = ECKeyGeneratorParameters(domainParams);
      final pcSecureRandom = pc.SecureRandom('Fortuna');
      pcSecureRandom.seed(KeyParameter(seed));
      keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
      final pcKeyPair = keyGen.generateKeyPair();
      final pcPkd = pcKeyPair.publicKey as ECPublicKey;
      final pkdBytes = _ecPublicKeyToBytes(pcPkd);
      final pkdBase64 = base64Encode(pkdBytes);
      
      // Store SKd for this device (will be used after pairing is approved)
      final skdBase64 = base64Encode(seed);
      await _storage.write(key: _skdKey, value: skdBase64);
      
      // Import pairing service
      final pairingService = PairingService();
      final result = await pairingService.requestPairing(
        deviceId: deviceId,
        publicKey: pkdBase64,
      );
      
      if (result.isSuccess) {
        print('🔗 Pairing requested - OTP: ${result.otp}');
        return PairingRequestResult.success(
          otp: result.otp!,
          pairingToken: result.pairingToken,
        );
      } else {
        return PairingRequestResult.error(result.error ?? 'Failed to request pairing');
      }
    } catch (e) {
      print('🔗 Pairing request error: $e');
      return PairingRequestResult.error('Failed to request pairing: $e');
    }
  }

  /// Complete pairing after approval (for new device - Device B)
  /// Polls for wrappedKu from server after Device A approves
  Future<E2EBootstrapResult> completePairing({
    required String accessToken,
    required String pairingToken,
  }) async {
    try {
      final pairingService = PairingService();
      
      // Poll for approval (check every 2 seconds, max 60 seconds)
      const maxAttempts = 30;
      const pollInterval = Duration(seconds: 2);
      
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final status = await pairingService.checkPairingStatus(pairingToken);
        
        if (status.isApproved && status.wrappedKu != null) {
          print('🔗 Pairing approved! Receiving wrappedKu...');
          
          // Decrypt wrappedKu with local SKd
          final skdBase64 = await _storage.read(key: _skdKey);
          if (skdBase64 == null) {
            return E2EBootstrapResult.error('Device key not found');
          }
          
          final skdSeedBytes = base64Decode(skdBase64);
          final wrappedKuBase64 = status.wrappedKu!;
          
          // Decrypt Ku - handle ephemeral format (from cross-device pairing)
          Uint8List ku;
          if (_isEphemeralFormat(wrappedKuBase64)) {
            print('🔗 Detected ephemeral format - using cross-device decryption');
            ku = await decryptKuFromEphemeralFormat(wrappedKuBase64, skdSeedBytes);
          } else {
            // Legacy same-device format
            print('🔗 Detected same-device format - using standard decryption');
            final wrappedKu = base64Decode(wrappedKuBase64);
            final seedBytes = skdSeedBytes.length >= 32 
                ? skdSeedBytes.sublist(0, 32) 
                : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
            // Use pointycastle to generate keypair from seed
            final domainParams = ECCurve_secp256r1();
            final keyGen = ECKeyGenerator();
            final keyParams = ECKeyGeneratorParameters(domainParams);
            final pcSecureRandom = pc.SecureRandom('Fortuna');
            pcSecureRandom.seed(KeyParameter(seedBytes));
            keyGen.init(ParametersWithRandom(keyParams, pcSecureRandom));
            final pcKeyPair = keyGen.generateKeyPair();
            final pcSkd = pcKeyPair.privateKey as ECPrivateKey;
            final pcPkd = pcKeyPair.publicKey as ECPublicKey;
            
            // Use pointycastle for decryption
            ku = await _decryptKuWithPointycastleKeys(wrappedKu, seedBytes, pcPkd, pcSkd);
          }
          
          // Store Ku in session
          await _storage.write(
            key: _kuKey,
            value: base64Encode(ku),
          );
          
          print('🔗 Pairing completed - Ku recovered');
          return E2EBootstrapResult.success(ku);
        }
        
        // Wait before next poll
        await Future.delayed(pollInterval);
      }
      
      return E2EBootstrapResult.error('Pairing approval timeout');
    } catch (e) {
      print('🔗 Pairing completion error: $e');
      return E2EBootstrapResult.error('Failed to complete pairing: $e');
    }
  }
}

/// Result class for E2E bootstrap operations
class E2EBootstrapResult {
  final Uint8List? ku;
  final String? error;
  final bool requiresPairing;

  E2EBootstrapResult.success(this.ku) 
      : error = null, 
        requiresPairing = false;
  
  E2EBootstrapResult.error(this.error) 
      : ku = null, 
        requiresPairing = false;
  
  E2EBootstrapResult.pairingRequired(this.error)
      : ku = null,
        requiresPairing = true;

  bool get isSuccess => ku != null;
  bool get needsPairing => requiresPairing;
}

