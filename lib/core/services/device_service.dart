import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing device identification
/// Uses Keychain (iOS) and Keystore (Android) via FlutterSecureStorage
class DeviceService {
  static const String _deviceIdKey = 'device_id';
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

  /// Get device ID in real-time (always fetches fresh from device)
  /// Also stores it securely in Keychain (iOS) or Keystore (Android) for reference
  /// This ensures we always get the current device ID, not a cached value
  Future<String> getDeviceId() async {
    try {
      // Always get device ID fresh from device (real-time)
      // Don't use cached value - fetch directly from device info
      String deviceId;
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // Use Android ID directly (no prefix)
        deviceId = androidInfo.id;
        if (deviceId.isEmpty) {
          throw Exception('Android ID is empty');
        }
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        // Use identifierForVendor directly (no prefix)
        deviceId = iosInfo.identifierForVendor ?? '';
        if (deviceId.isEmpty) {
          throw Exception('iOS identifierForVendor is null');
        }
      } else {
        throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
      }

      // Store device ID securely in Keychain/Keystore for reference
      // (but we always fetch fresh above, so this is just for backup/reference)
      await _storage.write(key: _deviceIdKey, value: deviceId);
      
      debugPrint('📱 Device ID fetched in real-time: $deviceId');
      return deviceId;
    } catch (e) {
      // If the device information retrieval fails, try to get from cache as fallback
      debugPrint('⚠️ Failed to get device ID in real-time: $e');
      String? cachedDeviceId = await _storage.read(key: _deviceIdKey);
      if (cachedDeviceId != null && cachedDeviceId.isNotEmpty) {
        debugPrint('📱 Using cached device ID as fallback: $cachedDeviceId');
        return cachedDeviceId;
      }
      // If both fail, throw exception
      throw Exception('Failed to retrieve device ID: $e');
    }
  }

  /// Clear cached device ID (ONLY for account deletion or device reset)
  /// WARNING: Should NOT be called during normal logout
  /// Device ID should persist across logouts for E2E encryption to work
  Future<void> clearDeviceId() async {
    await _storage.delete(key: _deviceIdKey);
    debugPrint('⚠️ Cleared device ID - device will need to regenerate on next use');
  }
}

