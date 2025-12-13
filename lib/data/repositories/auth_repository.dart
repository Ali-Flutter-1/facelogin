import 'dart:typed_data';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/data/models/login_response_model.dart';
import 'package:facelogin/data/services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthRepository {
  final AuthService _authService;
  final FlutterSecureStorage _storage;

  AuthRepository({
    AuthService? authService,
    FlutterSecureStorage? storage,
  })  : _authService = authService ?? AuthService(),
        _storage = storage ?? const FlutterSecureStorage();

  /// Login or register with face image
  Future<AuthResult> loginOrRegister(Uint8List faceImageBytes) async {
    final result = await _authService.loginOrRegister(faceImageBytes);

    if (result.isSuccess && result.data != null) {
      try {
        // Save tokens to secure storage
        await _storage.write(
          key: AppConstants.accessTokenKey,
          value: result.data!.accessToken,
        );
        await _storage.write(
          key: AppConstants.refreshTokenKey,
          value: result.data!.refreshToken,
        );

        // Verify tokens were saved
        final savedAccessToken = await _storage.read(key: AppConstants.accessTokenKey);
        final savedRefreshToken = await _storage.read(key: AppConstants.refreshTokenKey);

        if (savedAccessToken == null || savedRefreshToken == null) {
          return AuthResult.error(
            'Login successful but failed to save session. Please try again.',
          );
        }

        return AuthResult.success(result.data!);
      } catch (e) {
        return AuthResult.error(
          'Login successful but failed to save session. Please try again.',
        );
      }
    } else {
      return AuthResult.error(result.error ?? 'Login failed');
    }
  }

  /// Get access token from storage
  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConstants.accessTokenKey);
  }

  /// Get refresh token from storage
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConstants.refreshTokenKey);
  }

  /// Clear all stored tokens
  Future<void> clearTokens() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
  }
}

/// Auth result class
class AuthResult {
  final LoginResponseModel? data;
  final String? error;

  AuthResult.success(this.data) : error = null;
  AuthResult.error(this.error) : data = null;

  bool get isSuccess => data != null;
  bool get isError => error != null;
}

