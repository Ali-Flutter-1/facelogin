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

  /// Get or create a unique device ID
  /// Stored securely in Keychain (iOS) or Keystore (Android)
  Future<String> getDeviceId() async {
    try {
      // Try to get existing device ID from secure storage
      String? deviceId = await _storage.read(key: _deviceIdKey);

      if (deviceId != null && deviceId.isNotEmpty) {
        return deviceId;
      }

      // Get actual device ID (no prefixes)
      String newDeviceId;
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // Use Android ID directly (no prefix)
        newDeviceId = androidInfo.id;
        if (newDeviceId.isEmpty) {
          throw Exception('Android ID is empty');
        }
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        // Use identifierForVendor directly (no prefix)
        newDeviceId = iosInfo.identifierForVendor ?? '';
        if (newDeviceId.isEmpty) {
          throw Exception('iOS identifierForVendor is null');
        }
      } else {
        throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
      }

      // Store device ID securely in Keychain/Keystore
      await _storage.write(key: _deviceIdKey, value: newDeviceId);
      return newDeviceId;
    } catch (e) {
      // If the device information retrieval fails, you can throw an exception instead of generating a fallback
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

