import 'dart:convert';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/device_service.dart' as device_id_service;
import 'package:facelogin/data/models/device_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Service for API calls related to device management
/// Handles fetching and linking devices via API
class DeviceApiService {
  final http.Client _client = http.Client();
  final device_id_service.DeviceService _deviceIdService = device_id_service.DeviceService();

  /// Fetch all devices for the current user
  Future<List<DeviceModel>> getAllDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
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
      debugPrint('📱 Link Device: Starting with QR code data: $qrCodeData');
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ Link Device: No access token found');
        throw Exception('No access token found. Please login again.');
      }

      // Try to parse QR code - it might be a URL, JSON, or just a device ID
      Map<String, dynamic> requestBody;
      
      // Check if QR code is a URL
      if (qrCodeData.startsWith('http://') || qrCodeData.startsWith('https://')) {
        // Extract device ID from URL if it's a link
        final uri = Uri.tryParse(qrCodeData);
        final deviceId = uri?.queryParameters['deviceId'] ?? 
                        uri?.pathSegments.last ?? 
                        qrCodeData;
        requestBody = {'deviceId': deviceId};
        debugPrint('📱 Link Device: Extracted deviceId from URL: $deviceId');
      } else {
        // Try to parse as JSON
        try {
          final jsonData = jsonDecode(qrCodeData);
          if (jsonData is Map) {
            requestBody = jsonData as Map<String, dynamic>;
            debugPrint('📱 Link Device: Parsed QR code as JSON');
          } else {
            // Treat as plain device ID
            requestBody = {'deviceId': qrCodeData};
            debugPrint('📱 Link Device: Treating QR code as deviceId');
          }
        } catch (e) {
          // Not JSON, treat as plain device ID
          requestBody = {'deviceId': qrCodeData};
          debugPrint('📱 Link Device: Treating QR code as plain deviceId');
        }
      }

      final requestBodyJson = jsonEncode(requestBody);
      final apiUrl = '${ApiConstants.allDevices}/link';
      
      debugPrint('📱 Link Device: POST $apiUrl');
      debugPrint('📱 Link Device: Request body: $requestBodyJson');

      final response = await _client.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
        body: requestBodyJson,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('❌ Link Device: Request timeout after 30 seconds');
          throw Exception('Request timeout. Please check your internet connection and try again.');
        },
      );

      debugPrint('📱 Link Device Response Status: ${response.statusCode}');
      debugPrint('📱 Link Device Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Link Device: Success');
        return true;
      } else {
        // Try to parse error response
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage = errorData['error']?['message'] ?? 
                             errorData['message'] ?? 
                             'Failed to link device';
          debugPrint('❌ Link Device Error: $errorMessage');
          throw Exception(errorMessage);
        } catch (e) {
          if (e is Exception && e.toString().contains('Failed to link device')) {
            rethrow;
          }
          // If parsing fails, return generic error with status code
          debugPrint('❌ Link Device: Failed with status ${response.statusCode}');
          throw Exception('Failed to link device. Server returned status ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error linking device: $e');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Unexpected error: ${e.toString()}');
    }
  }
}

