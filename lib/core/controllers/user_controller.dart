import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/services/http_interceptor_service.dart';

/// Shared user state controller that manages user data across all screens
class UserController extends GetxController {
  // User profile data
  final _firstName = ''.obs;
  final _lastName = ''.obs;
  final _fullName = ''.obs;
  final _email = ''.obs;
  final _phone = ''.obs;
  final _dob = ''.obs;
  final _faceImageUrl = Rxn<String>();
  final _idVerified = false.obs;
  final _createdAt = ''.obs;
  
  // Loading state
  final _isLoading = true.obs;
  
  // Getters
  String get firstName => _firstName.value;
  String get lastName => _lastName.value;
  String get fullName => _fullName.value;
  String get displayName => _firstName.value.isNotEmpty ? _firstName.value : (_fullName.value.isNotEmpty ? _fullName.value : 'User');
  String get email => _email.value;
  String get phone => _phone.value;
  String get dob => _dob.value;
  String? get faceImageUrl => _faceImageUrl.value;
  bool get idVerified => _idVerified.value;
  String get createdAt => _createdAt.value;
  bool get isLoading => _isLoading.value;
  
  @override
  void onInit() {
    super.onInit();
    fetchUserData();
  }
  
  /// Fetch user data from API
  Future<void> fetchUserData() async {
    try {
      _isLoading.value = true;
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.accessTokenKey);

      if (token == null || token.isEmpty) {
        _isLoading.value = false;
        return;
      }

      final response = await http.patch(
        Uri.parse(ApiConstants.profileUpdate),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      // Check for 401 and handle logout (preserves E2E keys)
      await handle401IfNeeded(response, Get.context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = data['data']?['user'];
        if (userData != null) {
          _updateUserData(userData);
        }
      }
    } catch (e) {
      debugPrint('UserController: Error fetching user data: $e');
    } finally {
      _isLoading.value = false;
    }
  }
  
  /// Update user data from API response
  void _updateUserData(Map<String, dynamic> userData) {
    _firstName.value = userData['first_name'] ?? '';
    _lastName.value = userData['last_name'] ?? '';
    _fullName.value = userData['full_name'] ?? '';
    _email.value = userData['email'] ?? '';
    _phone.value = userData['phone'] ?? '';
    _dob.value = userData['dob'] ?? '';
    _faceImageUrl.value = userData['face_image_url'];
    _idVerified.value = userData['id_verified'] ?? false;
    _createdAt.value = userData['created_at'] ?? '';
    
    debugPrint('UserController: Updated user data - name: $displayName, verified: $idVerified');
  }
  
  /// Refresh user data (call after profile update or KYC completion)
  Future<void> refreshUserData() async {
    debugPrint('UserController: Refreshing user data...');
    await fetchUserData();
  }
  
  /// Clear all user data (call on logout)
  void clearUserData() {
    _firstName.value = '';
    _lastName.value = '';
    _fullName.value = '';
    _email.value = '';
    _phone.value = '';
    _dob.value = '';
    _faceImageUrl.value = null;
    _idVerified.value = false;
    _createdAt.value = '';
    _isLoading.value = false;
  }
}
