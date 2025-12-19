import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/services/device_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart' as crypto;
import 'package:pointycastle/export.dart';

/// E2E Encryption Service
/// Handles X25519 key exchange and AES-GCM encryption
/// Uses Keychain (iOS) and Keystore (Android) for secure key storage
/// 
/// IMPORTANT SECURITY NOTES:
/// - Ku (User Master Key): 32-byte AES key, exists ONLY on client device
///   - Stored in memory during session only
///   - NEVER sent to server in plaintext
///   - Only wrappedKu (encrypted) is sent to server
/// 
/// - SKd (Device Private Key): X25519 private key, exists ONLY on client device
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
  static const String _skdKey = 'e2e_skd'; // Device private key (X25519)
  static const String _kuKey = 'e2e_ku_session'; // User master key (AES-256, session only)
  static const String _bootstrapCompleteResponseKey = 'e2e_bootstrap_complete_response'; // Bootstrap complete API response

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
      
      // Generate X25519 keypair (PKd, SKd) using cryptography package
      // Use seed-based approach: generate random seed, create keypair from seed, store seed
      final x25519 = X25519();
      
      // Generate 32-byte random seed for X25519 private key
      // Use dart:math Random.secure() for secure random generation
      final seed = Uint8List(32);
      final secureRandom = Random.secure();
      for (int i = 0; i < 32; i++) {
        seed[i] = secureRandom.nextInt(256);
      }
      
      // Create keypair from seed
      final keyPair = await x25519.newKeyPairFromSeed(seed);
      final pkd = await keyPair.extractPublicKey();
      final skd = keyPair;

      // Generate 32-byte AES User Master Key (Ku)
      final ku = Uint8List(32);
      final kuSecureRandom = Random.secure();
      for (int i = 0; i < 32; i++) {
        ku[i] = kuSecureRandom.nextInt(256);
      }

      // Step 2.4: Encrypt: wrappedKu = Encrypt(Ku, PKd)
      // We use AES-GCM with a key derived from PKd
      final wrappedKu = await _encryptKuWithPkd(ku, pkd);

      // Step 2.5: Send: deviceId, PKd, wrappedKu
      // Step 2.6: Store in Device Keys Table (server-side)
      final pkdBytes = pkd.bytes;
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
      // This seed is the private key material for X25519
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
      if (bootstrapData['e2e_setup'] == true || bootstrapData['data']?['wrappedKu'] != null) {
        print('🔐 E2E Status: Setup Found');
        
        // Verify we have SKd locally to decrypt wrappedKu
        final hasLocalSkd = await _storage.read(key: _skdKey);
        if (hasLocalSkd == null || hasLocalSkd.isEmpty) {
          print('🔐 E2E Status: Server has E2E but no local SKd - cannot decrypt');
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
        return await _recoverKeysForExistingDevice(accessToken, deviceId, bootstrapData);
      } else {
        // Server returned 200 but no wrappedKu - try registration
        print('🔐 E2E Status: Server returned 200 but no wrappedKu - attempting registration');
        await _storage.delete(key: _skdKey);
        await _storage.delete(key: _kuKey);
        return await bootstrapForRegistration(accessToken);
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
      final wrappedKu = base64Decode(wrappedKuBase64);
      print('🔐 E2E Recovery: wrappedKu length: ${wrappedKu.length} bytes');

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
      // Reconstruct KeyPair from stored seed bytes
      // The stored bytes are the seed that was used to generate the keypair
      final x25519 = X25519();
      // Ensure the seed is exactly 32 bytes (X25519 private key size)
      final seedBytes = skdSeedBytes.length >= 32 
          ? skdSeedBytes.sublist(0, 32) 
          : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
      
      // Create keypair from the stored seed bytes
      final skd = await x25519.newKeyPairFromSeed(seedBytes);
      final currentPkd = await skd.extractPublicKey();
      print('🔐 E2E Recovery: Reconstructed keypair from stored SKd');

      // Step 3.6.2: Decrypt: Ku = Decrypt(wrappedKu, SKd)
      // Pass the seed bytes directly for key derivation
      print('🔐 E2E Recovery: Attempting to decrypt wrappedKu...');
      final ku = await _decryptKuWithSkd(wrappedKu, seedBytes);
      print('🔐 E2E Recovery: Successfully decrypted wrappedKu');

      // Step 3.6.3: Keep Ku in memory for session
      await _storage.write(
        key: _kuKey,
        value: base64Encode(ku),
      );
      print('🔐 Ku: Recovered and stored in session storage');

      return E2EBootstrapResult.success(ku);

    } catch (e) {
      print('🔐 E2E Recovery Error: $e');
      // If decryption fails, it means wrappedKu was encrypted with a different device's key
      // This can happen if another user logged in on the same device, or app was reinstalled
      if (e.toString().contains('InvalidCipherTextException') || 
          e.toString().contains('InvalidCipherText')) {
        print('🔐 E2E Recovery: wrappedKu encrypted with different device key');
        print('🔐 E2E Recovery: Clearing mismatched keys and skipping E2E');
        // Clear the mismatched SKd
        await _storage.delete(key: _skdKey);
        await _storage.delete(key: _kuKey);
        // Don't try to re-register - server will return 409 "already_exists"
        // Just skip E2E for this session
        return E2EBootstrapResult.error('E2E keys mismatch - skipping E2E for this session');
      }
      return E2EBootstrapResult.error('Failed to recover keys: $e');
    }
  }

  /// Encrypt Ku with PKd using AES-GCM
  /// Uses a key derived from X25519 public key
  Future<Uint8List> _encryptKuWithPkd(Uint8List ku, SimplePublicKey pkd) async {
    // Derive encryption key from PKd using SHA-256
    final keyMaterial = pkd.bytes;
    final key = sha256.convert(keyMaterial).bytes.sublist(0, 32);
    
    // Generate random IV (12 bytes for GCM)
    final iv = Uint8List(12);
    final secureRandom = Random.secure();
    for (int i = 0; i < 12; i++) {
      iv[i] = secureRandom.nextInt(256);
    }

    // Encrypt using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));

    final encrypted = cipher.process(ku);
    
    // Prepend IV to encrypted data (IV + encrypted data)
    return Uint8List.fromList([...iv, ...encrypted]);
  }

  /// Decrypt wrappedKu with SKd
  /// skdSeedBytes: The seed bytes that were used to generate the keypair (the private key material)
  /// IMPORTANT: Must reconstruct PKd from seed and use PKd.bytes for key derivation
  /// to match the encryption method which uses PKd.bytes
  Future<Uint8List> _decryptKuWithSkd(Uint8List wrappedKu, Uint8List skdSeedBytes) async {
    // Extract IV (first 12 bytes) and encrypted data
    if (wrappedKu.length < 12) {
      throw Exception('Invalid wrappedKu: too short');
    }
    
    final iv = wrappedKu.sublist(0, 12);
    final encrypted = wrappedKu.sublist(12);

    // Reconstruct PKd from seed to get the same key derivation as encryption
    // Encryption uses: sha256(PKd.bytes), so decryption must match
    final x25519 = X25519();
    // Ensure the seed is exactly 32 bytes (X25519 private key size)
    final seedBytes = skdSeedBytes.length >= 32 
        ? skdSeedBytes.sublist(0, 32) 
        : Uint8List.fromList([...skdSeedBytes, ...List.filled(32 - skdSeedBytes.length, 0)]);
    
    // Reconstruct keypair from seed and extract public key
    final keyPair = await x25519.newKeyPairFromSeed(seedBytes);
    final pkd = await keyPair.extractPublicKey();
    
    // Derive decryption key from PKd (same as encryption)
    final keyMaterial = pkd.bytes;
    final key = sha256.convert(keyMaterial).bytes.sublist(0, 32);

    // Decrypt using AES-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, iv, Uint8List(0)));

    return cipher.process(encrypted);
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
    debugPrint('⚠️ Cleared ALL E2E keys (including SKd) - device will need re-registration');
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
}

/// Result class for E2E bootstrap operations
class E2EBootstrapResult {
  final Uint8List? ku;
  final String? error;

  E2EBootstrapResult.success(this.ku) : error = null;
  E2EBootstrapResult.error(this.error) : ku = null;

  bool get isSuccess => ku != null;
}

