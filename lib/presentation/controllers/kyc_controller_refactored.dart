import 'dart:convert';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/message_constants.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';

import 'package:facelogin/data/repositories/auth_repository.dart';
import 'package:facelogin/data/services/image_service.dart';
import 'package:facelogin/screens/kyc/kyc_screen.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class KycControllerRefactored extends GetxController {
  final ImageService _imageService;
  final AuthRepository _authRepository;
  final ImagePicker _picker = ImagePicker();

  var frontImage = Rx<XFile?>(null);
  var backImage = Rx<XFile?>(null);
  var frontImageId = RxString('');
  var backImageId = RxString('');
  RxInt step = 1.obs;
  RxBool isLoading = false.obs;
  RxBool isUploadingFront = false.obs;
  RxBool isUploadingBack = false.obs;

  KycControllerRefactored({
    ImageService? imageService,
    AuthRepository? authRepository,
  })  : _imageService = imageService ?? ImageService(),
        _authRepository = authRepository ?? AuthRepository();

  /// Pick image and upload it immediately
  Future<void> pickImage(bool isFront, ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: AppConstants.imageQuality,
      );

      if (picked != null) {
        if (isFront) {
          await _handleFrontImageUpload(picked);
        } else {
          await _handleBackImageUpload(picked);
        }
      }
    } catch (e) {
      _handleUploadError(isFront, e);
    }
  }

  Future<void> _handleFrontImageUpload(XFile picked) async {
    frontImage.value = picked;
    isUploadingFront.value = true;

    try {
      final response = await _imageService.uploadImage(
        picked,
        'id_front_image',
      );

      if (response != null) {
        final imageId = response.getImageId('id_front_image');
        if (imageId != null) {
          frontImageId.value = imageId;
          debugPrint("✅ Front image uploaded successfully, ID: $imageId");
        } else {
          _showError(MessageConstants.failedToUploadFrontImage);
        }
      } else {
        _showError(MessageConstants.failedToUploadFrontImage);
      }
    } catch (e) {
      debugPrint("❌ Error uploading front image: $e");
      _showError(MessageConstants.failedToUploadFrontImage);
    } finally {
      isUploadingFront.value = false;
    }
  }

  Future<void> _handleBackImageUpload(XFile picked) async {
    backImage.value = picked;
    isUploadingBack.value = true;

    try {
      final response = await _imageService.uploadImage(
        picked,
        'id_back_image',
      );

      if (response != null) {
        final imageId = response.getImageId('id_back_image');
        if (imageId != null) {
          backImageId.value = imageId;
          debugPrint("✅ Back image uploaded successfully, ID: $imageId");
        } else {
          _showError(MessageConstants.failedToUploadBackImage);
        }
      } else {
        _showError(MessageConstants.failedToUploadBackImage);
      }
    } catch (e) {
      debugPrint("❌ Error uploading back image: $e");
      _showError(MessageConstants.failedToUploadBackImage);
    } finally {
      isUploadingBack.value = false;
    }
  }

  void _handleUploadError(bool isFront, dynamic error) {
    if (isFront) {
      isUploadingFront.value = false;
    } else {
      isUploadingBack.value = false;
    }
    _showError(MessageConstants.failedToSelectImage);
    debugPrint("❌ Image pick error: $error");
  }

  void _showError(String message) {
    if (Get.context != null) {
      showCustomToast(Get.context!, message, isError: true);
    }
  }

  /// Clear all images and reset state
  void clearImages() {
    frontImage.value = null;
    backImage.value = null;
    frontImageId.value = '';
    backImageId.value = '';
    isUploadingFront.value = false;
    isUploadingBack.value = false;
    step.value = 1;
    debugPrint("🧹 Cleared all images from UI");
  }

  /// Step navigation
  void nextStep() {
    if (step.value < 3) {
      step.value++;
      debugPrint("Step advanced to: ${step.value}");
    }
  }

  void prevStep() {
    if (step.value > 1) step.value--;
  }

  /// Get access token
  Future<String?> getAccessToken() async {
    try {
      final token = await _authRepository.getAccessToken();
      if (token == null || token.isEmpty) {
        _showError(MessageConstants.noAccessTokenFound);
        return null;
      }
      return token;
    } catch (e) {
      _showError(MessageConstants.unableToAuthenticate);
      return null;
    }
  }

  /// Submit KYC verification
  Future<void> submitKyc({required BuildContext context}) async {
    // Check if images are still uploading
    if (isUploadingFront.value || isUploadingBack.value) {
      showCustomToast(context, MessageConstants.waitForImagesUpload, isError: true);
      return;
    }

    // Check if images are uploaded
    if (frontImageId.value.isEmpty || backImageId.value.isEmpty) {
      showCustomToast(context, MessageConstants.uploadBothImages, isError: true);
      return;
    }

    final token = await getAccessToken();
    if (token == null) {
      showCustomToast(context, MessageConstants.noAccessToken, isError: true);
      return;
    }

    isLoading.value = true;

    final url = Uri.parse(ApiConstants.kyc);
    debugPrint("🟢 Sending KYC verification with IDs: front=${frontImageId.value}, back=${backImageId.value}");

    try {
      final body = jsonEncode({
        "front_image_id": frontImageId.value,
        "back_image_id": backImageId.value,
        "require_live": true,
        "overwrite": true,
        "threshold": 0.95,
      });

      debugPrint("📋 Request body: $body");

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': ApiConstants.acceptHeader,
          'Content-Type': ApiConstants.contentTypeJson,
        },
        body: body,
      );

      debugPrint("🔹 Response (${response.statusCode}): ${response.body}");

      isLoading.value = false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        showCustomToast(context, MessageConstants.kycSubmittedSuccess);
        clearImages();
        Navigator.pop(context, true);
      } else {
        try {
          final error = json.decode(response.body);
          final errorMessage = error['error']?['message'] ?? MessageConstants.kycSubmissionFailed;
          showCustomToast(context, errorMessage, isError: true);
        } catch (e) {
          showCustomToast(context, MessageConstants.kycSubmissionFailed, isError: true);
        }
        clearImages();
      }
    } catch (e) {
      debugPrint("❌ Exception during KYC: $e");
      isLoading.value = false;
      showCustomToast(context, MessageConstants.somethingWentWrong, isError: true);
      clearImages();
    }
  }

  /// Show KYC dialog
  Future<bool?> showKycDialog(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const KycScreen(),
      ),
    );
    return result as bool?;
  }
}

