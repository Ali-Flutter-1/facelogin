import 'dart:convert';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/device_service.dart' as device_id_service;
import 'package:facelogin/data/models/device_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Service for API calls related to device management
/// Handles fetching and linking devices via API
class DeviceApiService {
  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final device_id_service.DeviceService _deviceIdService = device_id_service.DeviceService();

  /// Fetch all devices for the current user
  Future<List<DeviceModel>> getAllDevices() async {
    try {
      final accessToken = await _storage.read(key: AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final response = await _client.get(
        Uri.parse(ApiConstants.allDevices),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
      ).timeout(const Duration(seconds: 30));

      debugPrint('📱 Devices API Response Status: ${response.statusCode}');
      debugPrint('📱 Devices API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle different response structures
        List<dynamic> devicesJson = [];
        if (data['data'] != null) {
          if (data['data'] is List) {
            // If data is directly a list
            devicesJson = data['data'] as List<dynamic>;
          } else if (data['data'] is Map && data['data']['devices'] != null) {
            // If data is a map containing devices array
            devicesJson = data['data']['devices'] as List<dynamic>;
          }
        } else if (data['devices'] != null) {
          devicesJson = data['devices'] as List<dynamic>;
        }
        
        // Get current device ID to mark it
        String? currentDeviceId;
        try {
          currentDeviceId = await _deviceIdService.getDeviceId();
        } catch (e) {
          debugPrint('⚠️ Could not get current device ID: $e');
        }

        return devicesJson
            .map((json) {
              final device = DeviceModel.fromJson(json as Map<String, dynamic>);
              
              // Mark as current device if device_id matches
              // API format: "ios-UUID" or "android-UUID"
              // DeviceService returns: "UUID" (just the UUID part)
              if (currentDeviceId != null && device.deviceId.isNotEmpty) {
                // Extract UUID from device_id (remove platform prefix if present)
                final deviceIdParts = device.deviceId.split('-');
                final deviceUuid = deviceIdParts.length > 1 
                    ? deviceIdParts.sublist(1).join('-') 
                    : device.deviceId;
                
                // Compare UUIDs (case-insensitive)
                if (deviceUuid.toLowerCase() == currentDeviceId.toLowerCase()) {
                  return DeviceModel(
                    deviceId: device.deviceId,
                    deviceName: device.deviceName,
                    deviceType: device.deviceType,
                    platform: device.platform,
                    createdAt: device.createdAt,
                    lastActiveAt: device.lastActiveAt,
                    isCurrentDevice: true,
                  );
                }
              }
              return device;
            })
            .toList();
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 
                           errorData['message'] ?? 
                           'Failed to fetch devices';
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error fetching devices: $e');
      rethrow;
    }
  }

  /// Link a new device using QR code data
  Future<bool> linkDevice(String qrCodeData) async {
    try {
      final accessToken = await _storage.read(key: AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      // Parse QR code data (assuming it contains deviceId or similar)
      final requestBody = jsonEncode({
        'qrCode': qrCodeData,
        // Add other required fields based on your API
      });

      final response = await _client.post(
        Uri.parse('${ApiConstants.allDevices}/link'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      debugPrint('📱 Link Device Response Status: ${response.statusCode}');
      debugPrint('📱 Link Device Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 
                           errorData['message'] ?? 
                           'Failed to link device';
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error linking device: $e');
      rethrow;
    }
  }
}

