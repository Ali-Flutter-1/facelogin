import 'dart:convert';

import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/data/models/api_error_model.dart';
import 'package:facelogin/data/models/login_response_model.dart';
import 'package:facelogin/data/services/image_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final http.Client _client;
  final ImageService _imageService;

  AuthService({
    http.Client? client,
    ImageService? imageService,
  })  : _client = client ?? http.Client(),
        _imageService = imageService ?? ImageService();

  /// Login or register with face image
  Future<Result<LoginResponseModel>> loginOrRegister(Uint8List faceImageBytes) async {
    try {
      // Validate API URL
      if (ApiConstants.loginOrRegister.isEmpty) {
        return Result.error('Configuration error. Please contact support.');
      }

      debugPrint("📤 Preparing to send image to: ${ApiConstants.loginOrRegister}");

      // Resize image to web resolution
      final resizedBytes = await _imageService.resizeImageToWebResolution(faceImageBytes);

      // Validate image size
      if (resizedBytes.isEmpty) {
        return Result.error('Image file is empty. Please capture again.');
      }

      if (resizedBytes.lengthInBytes < 1024) {
        return Result.error('Image quality is too low. Please capture again.');
      }

      // Convert to base64 data URL
      final dataUrl = _imageService.imageToBase64DataUrl(resizedBytes);
      debugPrint("✅ Data URL created (length: ${dataUrl.length})");

      // Create request body
      final requestBody = {"face_image": dataUrl};
      final jsonBody = jsonEncode(requestBody);
      debugPrint("✅ JSON body created (length: ${jsonBody.length})");

      // Send HTTP request
      debugPrint("📤 Sending POST request to: ${ApiConstants.loginOrRegister}");
      final response = await _client
          .post(
            Uri.parse(ApiConstants.loginOrRegister),
            headers: {
              "Content-Type": ApiConstants.contentTypeJson,
            },
            body: jsonBody,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException("Request timeout after 30 seconds");
            },
          );

      debugPrint("✅ Response received: Status ${response.statusCode}");
      debugPrint("📥 Response body length: ${response.body.length}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("API Response: $data");

        final loginResponse = LoginResponseModel.fromJson(data);

        if (loginResponse.hasValidTokens) {
          return Result.success(loginResponse);
        } else {
          debugPrint("No tokens found in response: ${response.body}");
          return Result.error('No tokens received from server');
        }
      } else {
        debugPrint("❌ API Error: Status ${response.statusCode}");
        debugPrint("❌ Response body: ${response.body}");

        try {
          final errorData = jsonDecode(response.body);
          final apiError = ApiErrorModel.fromJson(errorData);
          return Result.error(apiError.displayMessage);
        } catch (parseError) {
          debugPrint("Could not parse error response: $parseError");
          return Result.error('Face recognition failed. Please try again.');
        }
      }
    } on TimeoutException {
      return Result.error('Request timeout. Check your internet connection.');
    } on http.ClientException catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('network')) {
        return Result.error('Network error. Check your internet connection.');
      }
      return Result.error('Request failed. Please try again.');
    } catch (e) {
      debugPrint("❌ Unexpected error in loginOrRegister: $e");
      return Result.error('Something went wrong. Please try again.');
    }
  }
}

/// Result class for handling success/error states
class Result<T> {
  final T? data;
  final String? error;

  Result.success(this.data) : error = null;
  Result.error(this.error) : data = null;

  bool get isSuccess => data != null;
  bool get isError => error != null;
}

/// TimeoutException for request timeouts
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

