import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing device identification
/// Uses Keychain (iOS) and Keystore (Android) via FlutterSecureStorage
/// Generates a unique physical device ID that persists across app reinstalls
class DeviceService {
  static const String _deviceIdKey = 'device_id';
  static const String _physicalDeviceIdKey = 'physical_device_id';
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
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get unique physical device ID from device hardware in real-time
  /// For Android: Uses a combination of hardware identifiers to create a unique fingerprint
  /// For iOS: Uses identifierForVendor (unique per vendor per device)
  /// The ID is hashed for privacy and consistency
  /// Always retrieves fresh from device, not from cache
  Future<String> getDeviceId() async {
    // Always get fresh device ID from hardware (real-time)
    String deviceId;
    
    try {
      if (Platform.isAndroid) {
        deviceId = await _getAndroidDeviceId();
      } else if (Platform.isIOS) {
        deviceId = await _getIOSDeviceId();
      } else {
        throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
      }

      if (deviceId.isEmpty) {
        throw Exception('Failed to generate device ID from device hardware');
      }

      // Store device ID securely in Keychain/Keystore for future reference
      // But we always get it fresh from device first
      await _storage.write(key: _deviceIdKey, value: deviceId);
      
      debugPrint('📱 Physical Device ID (fresh from device): $deviceId');
      return deviceId;
    } catch (e) {
      // Only use cache as last resort if device hardware retrieval completely fails
      debugPrint('⚠️ Failed to get device ID from hardware: $e');
      debugPrint('⚠️ Attempting to use cached device ID as fallback...');
      
      String? cachedDeviceId = await _storage.read(key: _deviceIdKey);
      if (cachedDeviceId != null && cachedDeviceId.isNotEmpty) {
        debugPrint('📱 Using cached device ID as fallback: $cachedDeviceId');
        return cachedDeviceId;
      }
      
      // If both fail, throw exception
      throw Exception('Failed to retrieve device ID from device hardware: $e');
    }
  }
  
  /// Get device ID from cache only (for testing/debugging)
  /// Returns null if not cached
  Future<String?> getCachedDeviceId() async {
    return await _storage.read(key: _deviceIdKey);
  }

  /// Get Android device ID using multiple hardware identifiers
  /// Creates a unique fingerprint based on device hardware characteristics
  Future<String> _getAndroidDeviceId() async {
    final androidInfo = await _deviceInfo.androidInfo;
    
    // Combine multiple hardware identifiers for a unique fingerprint
    // These values are tied to the physical device hardware
    final List<String> identifiers = [
      androidInfo.id, // Android ID (SSAID) - unique per app signing key per device
      androidInfo.fingerprint, // Build fingerprint
      androidInfo.hardware, // Hardware name
      androidInfo.device, // Device codename
      androidInfo.board, // Board name
      androidInfo.brand, // Brand name
      androidInfo.model, // Model name
      androidInfo.product, // Product name
      androidInfo.host, // Build host
    ];
    
    // Remove empty values and join
    final validIdentifiers = identifiers.where((id) => id.isNotEmpty).toList();
    
    if (validIdentifiers.isEmpty) {
      throw Exception('No valid Android identifiers found');
    }
    
    // Create a hash of the combined identifiers for a consistent unique ID
    final combinedString = validIdentifiers.join('|');
    final bytes = utf8.encode(combinedString);
    final hash = sha256.convert(bytes);
    
    // Return first 32 characters of hash for a manageable ID
    final deviceId = hash.toString().substring(0, 32);
    
    debugPrint('📱 Android identifiers used: ${validIdentifiers.length}');
    debugPrint('📱 Android ID (SSAID): ${androidInfo.id}');
    debugPrint('📱 Android fingerprint: ${androidInfo.fingerprint}');
    
    return deviceId;
  }

  /// Get iOS device ID using identifierForVendor
  /// This is the most reliable unique identifier available on iOS
  /// Always retrieves fresh from device hardware in real-time
  Future<String> _getIOSDeviceId() async {
    // Get fresh iOS device info from hardware
    final iosInfo = await _deviceInfo.iosInfo;
    
    // identifierForVendor is unique per vendor per device
    // It persists as long as at least one app from the same vendor is installed
    String? vendorId = iosInfo.identifierForVendor;
    
    if (vendorId == null || vendorId.isEmpty) {
      throw Exception('iOS identifierForVendor is null');
    }
    
    // Combine with other device info for additional uniqueness
    final List<String> identifiers = [
      vendorId,
      iosInfo.model, // Device model
      iosInfo.systemName, // OS name
      iosInfo.name, // Device name (can change, but adds uniqueness)
      iosInfo.utsname.machine, // Machine identifier
    ];
    
    // Remove empty values and join
    final validIdentifiers = identifiers.where((id) => id.isNotEmpty).toList();
    
    // Create a hash of the combined identifiers
    final combinedString = validIdentifiers.join('|');
    final bytes = utf8.encode(combinedString);
    final hash = sha256.convert(bytes);
    
    // Return first 32 characters of hash for a manageable ID
    final deviceId = hash.toString().substring(0, 32);
    
    debugPrint('📱 iOS identifierForVendor: $vendorId');
    debugPrint('📱 iOS model: ${iosInfo.model}');
    
    return deviceId;
  }

  /// Get raw device info for display purposes (not for identification)
  Future<Map<String, String>> getDeviceInfo() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return {
        'brand': androidInfo.brand,
        'model': androidInfo.model,
        'device': androidInfo.device,
        'androidId': androidInfo.id,
        'fingerprint': androidInfo.fingerprint,
      };
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return {
        'name': iosInfo.name,
        'model': iosInfo.model,
        'systemName': iosInfo.systemName,
        'systemVersion': iosInfo.systemVersion,
        'identifierForVendor': iosInfo.identifierForVendor ?? 'N/A',
      };
    }
    return {};
  }

  /// Clear cached device ID (ONLY for account deletion or device reset)
  /// WARNING: Should NOT be called during normal logout
  /// Device ID should persist across logouts for E2E encryption to work
  Future<void> clearDeviceId() async {
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _physicalDeviceIdKey);
    debugPrint('⚠️ Cleared device ID - device will need to regenerate on next use');
  }
}

