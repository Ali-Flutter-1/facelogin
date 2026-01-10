import 'dart:convert';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/services/http_interceptor_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Service for device pairing (cross-device E2E setup)
/// Handles OTP-based pairing between devices
class PairingService {
  final http.Client _client = http.Client();

  /// Request pairing for a new device (Device B - e.g., Oppo)
  /// Returns OTP that needs to be entered on existing device (Device A - e.g., Vivo)
  Future<PairingRequestResult> requestPairing({
    required String deviceId,
    required String publicKey, // PKd2 (base64 encoded)
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final requestBody = jsonEncode({
        'deviceId': deviceId,
        'publicKey': publicKey,
      });

      debugPrint('🔗 Pairing Request: POST ${ApiConstants.pairingRequest}');
      debugPrint('🔗 Pairing Request Body: $requestBody');

      final response = await _client.post(
        Uri.parse(ApiConstants.pairingRequest),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, null);

      debugPrint('🔗 Pairing Request Response Status: ${response.statusCode}');
      debugPrint('🔗 Pairing Request Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final otp = data['data']?['otp'] ?? data['otp'];
        final pairingToken = data['data']?['pairingToken'] ?? data['pairingToken'];

        if (otp != null) {
          return PairingRequestResult.success(
            otp: otp.toString(),
            pairingToken: pairingToken?.toString(),
          );
        } else {
          return PairingRequestResult.error('OTP not found in response');
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ??
            errorData['message'] ??
            'Failed to request pairing';
        return PairingRequestResult.error(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error requesting pairing: $e');
      return PairingRequestResult.error('Failed to request pairing: $e');
    }
  }

  /// Lookup pairing request by pairing token (on Device A - existing device)
  /// Used when scanning QR code from web
  /// Returns pairing details (deviceId, publicKey) that can be used to approve
  Future<PairingLookupResult> lookupByPairingToken(String pairingToken, {BuildContext? context}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final url = Uri.parse('${ApiConstants.pairingLookup}?pairingToken=$pairingToken');

      debugPrint('🔗 [API] Pairing Lookup by Token: GET $url');
      debugPrint('🔗 [API] Access Token present: ${accessToken != null && accessToken.isNotEmpty}');

      final response = await _client.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': ApiConstants.acceptHeader,
        },
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('🔗 [API] Response received - Status: ${response.statusCode}');

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, context);
      
      // If 401 occurred, return error (handler will navigate away)
      if (response.statusCode == 401) {
        return PairingLookupResult.error('Session expired. Please log in again.');
      }

      debugPrint('🔗 Pairing Lookup Response Status: ${response.statusCode}');
      debugPrint('🔗 Pairing Lookup Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseData = data['data'] ?? data;
        final deviceId = responseData['deviceId']?.toString();
        final publicKey = responseData['publicKey']?.toString();
        final status = responseData['status']?.toString();

        // Check if pairing is already approved
        if (status == 'PAIRING_APPROVED' || responseData['wrappedKu'] != null) {
          return PairingLookupResult.error('Pairing already approved');
        }

        if (deviceId != null && publicKey != null) {
          return PairingLookupResult.success(
            pairingToken: pairingToken, // Use the input pairingToken
            deviceId: deviceId,
            publicKey: publicKey,
          );
        } else {
          return PairingLookupResult.error('Missing pairing information in response');
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ??
            errorData['message'] ??
            'Invalid pairing token or pairing request not found';
        return PairingLookupResult.error(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error looking up pairing by token: $e');
      return PairingLookupResult.error('Failed to lookup pairing: $e');
    }
  }

  /// Lookup pairing request by OTP (on Device A - existing device)
  /// Returns pairingToken that can be used to approve
  Future<PairingLookupResult> lookupByOtp(String otp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final requestBody = jsonEncode({
        'otp': otp,
      });

      debugPrint('🔗 Pairing Lookup by OTP: POST ${ApiConstants.pairingLookupByOtp}');
      debugPrint('🔗 Pairing Lookup Body: $requestBody');

      final response = await _client.post(
        Uri.parse(ApiConstants.pairingLookupByOtp),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, null);

      debugPrint('🔗 Pairing Lookup Response Status: ${response.statusCode}');
      debugPrint('🔗 Pairing Lookup Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pairingToken = data['data']?['pairingToken'] ?? data['pairingToken'];
        final deviceId = data['data']?['deviceId'] ?? data['deviceId'];
        final publicKey = data['data']?['publicKey'] ?? data['publicKey'];

        if (pairingToken != null) {
          return PairingLookupResult.success(
            pairingToken: pairingToken.toString(),
            deviceId: deviceId?.toString(),
            publicKey: publicKey?.toString(),
          );
        } else {
          return PairingLookupResult.error('Pairing token not found in response');
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ??
            errorData['message'] ??
            'Invalid OTP or pairing request not found';
        return PairingLookupResult.error(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error looking up pairing: $e');
      return PairingLookupResult.error('Failed to lookup pairing: $e');
    }
  }

  /// Approve pairing request (on Device A - existing device)
  /// Sends wrappedKu for the new device
  Future<bool> approvePairing({
    required String pairingToken,
    required String wrappedKu, // Base64 encoded wrappedKu for Device B
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final requestBody = jsonEncode({
        'pairingToken': pairingToken,
        'wrappedKu': wrappedKu,
      });

      debugPrint('🔗 Pairing Approve: POST ${ApiConstants.pairingApprove}');
      debugPrint('🔗 Pairing Approve Body: $requestBody');

      final response = await _client.post(
        Uri.parse(ApiConstants.pairingApprove),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': ApiConstants.contentTypeJson,
          'Accept': ApiConstants.acceptHeader,
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 30));

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, null);

      debugPrint('🔗 Pairing Approve Response Status: ${response.statusCode}');
      debugPrint('🔗 Pairing Approve Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ??
            errorData['message'] ??
            'Failed to approve pairing';
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('❌ Error approving pairing: $e');
      rethrow;
    }
  }

  /// Check pairing status (polling from Device B)
  Future<PairingStatusResult> checkPairingStatus(String pairingToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final url = Uri.parse('${ApiConstants.pairingLookup}?pairingToken=$pairingToken');

      debugPrint('🔗 Pairing Status Check: GET $url');

      final response = await _client.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': ApiConstants.acceptHeader,
        },
      ).timeout(const Duration(seconds: 30));

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, null);

      debugPrint('🔗 Pairing Status Response Status: ${response.statusCode}');
      debugPrint('🔗 Pairing Status Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wrappedKu = data['data']?['wrappedKu'] ?? data['wrappedKu'];
        final isApproved = wrappedKu != null;

        return PairingStatusResult(
          isApproved: isApproved,
          wrappedKu: wrappedKu?.toString(),
        );
      } else {
        return PairingStatusResult(isApproved: false);
      }
    } catch (e) {
      debugPrint('❌ Error checking pairing status: $e');
      return PairingStatusResult(isApproved: false);
    }
  }
}

/// Result class for pairing request
class PairingRequestResult {
  final String? otp;
  final String? pairingToken;
  final String? error;

  PairingRequestResult.success({required this.otp, this.pairingToken}) : error = null;
  PairingRequestResult.error(this.error) : otp = null, pairingToken = null;

  bool get isSuccess => otp != null;
}

/// Result class for pairing lookup
class PairingLookupResult {
  final String? pairingToken;
  final String? deviceId;
  final String? publicKey;
  final String? error;

  PairingLookupResult.success({
    required this.pairingToken,
    this.deviceId,
    this.publicKey,
  }) : error = null;

  PairingLookupResult.error(this.error)
      : pairingToken = null,
        deviceId = null,
        publicKey = null;

  bool get isSuccess => pairingToken != null;
}

/// Result class for pairing status check
class PairingStatusResult {
  final bool isApproved;
  final String? wrappedKu;

  PairingStatusResult({
    required this.isApproved,
    this.wrappedKu,
  });
}

