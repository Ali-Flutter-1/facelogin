import 'dart:async';
import 'dart:convert';
import 'package:facelogin/constant/constant.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/screens/kyc/kyc_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KycController extends GetxController {
  var frontImage = Rx<XFile?>(null);
  var backImage = Rx<XFile?>(null);
  var frontImageId = RxString('');
  var backImageId = RxString('');
  RxInt step = 1.obs;
  RxBool isLoading = false.obs;
  RxBool isUploadingFront = false.obs;
  RxBool isUploadingBack = false.obs;


  final ImagePicker picker = ImagePicker();
  final FlutterSecureStorage storage = const FlutterSecureStorage();




  // Upload image to get ID/path
  Future<String?> uploadImageToServer(XFile imageFile, String fieldName, BuildContext context) async {
    try {
      final token = await storage.read(key: 'access_token');
      if (token == null) {
        showCustomToast(context, "No access token found.", isError: true);
        return null;
      }

      final uploadUrl = Uri.parse('https://idp.pollus.tech/api/auth/images/upload/');
      var request = http.MultipartRequest('POST', uploadUrl);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json, text/plain, */*';

      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        final fileName = imageFile.name.isNotEmpty ? imageFile.name : 'image.png';
        final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

        request.files.add(http.MultipartFile(
          fieldName,
          Stream.value(uint8List),
          uint8List.length,
          filename: fileName,
          contentType: MediaType('image', 'png'),
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          fieldName,
          imageFile.path,
        ));
      }

      print("📤 Uploading $fieldName to $uploadUrl");
      var streamed = await request.send();
      var responseBody = await streamed.stream.bytesToString();
      final response = http.Response(responseBody, streamed.statusCode);

      print("📤 Upload response (${response.statusCode}): ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);

          String? imageId;
          if (fieldName == 'id_front_image') {
            imageId = data['data']?['front_image_id'];
          } else if (fieldName == 'id_back_image') {
            imageId = data['data']?['back_image_id'];
          }

          // Fallback to other possible formats
          imageId ??= data['id'] ??
              data['file_id'] ??
              data['image_id'] ??
              data['path'] ??
              data['url'] ??
              data['data']?['id'] ??
              data['data']?['file_id'] ??
              data['data']?['image_id'] ??
              data['data']?['path'] ??
              data['data']?['url'];

          if (imageId != null) {
            print("✅ Image uploaded successfully, ID: $imageId");
            return imageId.toString();
          } else {
            print("⚠️ Upload succeeded but no ID found in response: $data");
          }
        } catch (e) {
          print("❌ Failed to parse upload response: $e");
        }
      } else {
        print("❌ Upload failed with status ${response.statusCode}: ${response.body}");
      }

      return null;
    } catch (e) {
      print("❌ Error uploading image: $e");
      showCustomToast(context, "Failed to upload image. Please try again.", isError: true);
      return null;
    }
  }

  // 📸 Pick image and upload it immediately
  Future<void> pickImage(bool isFront, ImageSource source) async {
    try {
      final picked = await picker.pickImage(source: source, imageQuality: 80);
      if (picked != null) {
        if (isFront) {
          frontImage.value = picked;
          // Upload front image immediately
          isUploadingFront.value = true;
          final imageId = await uploadImageToServer(picked, 'id_front_image', Get.context!);
          isUploadingFront.value = false;
          if (imageId != null) {
            frontImageId.value = imageId;
          } else {
            showCustomToast(Get.context!, "Failed to upload front image", isError: true);
          }
        } else {
          backImage.value = picked;
          // Upload back image immediately
          isUploadingBack.value = true;
          final imageId = await uploadImageToServer(picked, 'id_back_image', Get.context!);
          isUploadingBack.value = false;
          if (imageId != null) {
            backImageId.value = imageId;
          } else {
            showCustomToast(Get.context!, "Failed to upload back image", isError: true);
          }
        }
      }
    } catch (e) {
      if (isFront) {
        isUploadingFront.value = false;
      } else {
        isUploadingBack.value = false;
      }
      showCustomToast(Get.context!, "Failed to select image. Please try again.", isError: true);
      debugPrint("Image pick error: $e");
    }
  }

  // Clear all images and reset state (for UI only, not database)
  void clearImages() {
    frontImage.value = null;
    backImage.value = null;
    frontImageId.value = '';
    backImageId.value = '';
    isUploadingFront.value = false;
    isUploadingBack.value = false;
    step.value = 1;
    print("🧹 Cleared all images from UI");
  }

  // Step navigation - ONLY called when Continue button is clicked
  // Step does NOT auto-advance when images are uploaded
  void nextStep() {
    if (step.value < 3) {
      step.value++;
      debugPrint("Step advanced to: ${step.value}");
    }
  }

  void prevStep() {
    if (step.value > 1) step.value--;
  }

  Future<String?> getAccessToken() async {
    try {
      String? token = await storage.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        showCustomToast(Get.context!, "No access token found. Please log in again.");
        return null;
      }
      return token;
    } catch (e) {
      showCustomToast(Get.context!, "Unable to authenticate. Please log in again.", isError: true);
      return null;
    }
  }
  Future<void> submitKyc({
    required BuildContext context,
  }) async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');

    if (token == null) {
      showCustomToast(context, "No access token found.", isError: true);
      return;
    }

    // Check if images are still uploading
    if (isUploadingFront.value || isUploadingBack.value) {
      showCustomToast(context, "Please wait for images to finish uploading", isError: true);
      return;
    }

    // Check if images are uploaded
    if (frontImageId.value.isEmpty || backImageId.value.isEmpty) {
      showCustomToast(context, "Please upload both images first", isError: true);
      return;
    }

    // Start countdown timer

    isLoading.value = true;

    final url = Uri.parse(ApiConstants.kyc);
    print("🟢 Sending KYC verification with IDs only (NO image uploads): front=${frontImageId.value}, back=${backImageId.value}");

    try {
      // Only send image IDs, NOT the images themselves
      final body = jsonEncode({
        "front_image_id": frontImageId.value,
        "back_image_id": backImageId.value,
        "require_live": true,
        "overwrite": true,
        "threshold": 0.95,
      });

      print("📋 Request body (JSON only, no files): $body");

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      print("🔹 Response (${response.statusCode}): ${response.body}");

      // Stop countdown

      isLoading.value = false;

      if (response.statusCode == 200 || response.statusCode == 201) {
        showCustomToast(context, " KYC submitted successfully!");
        // Clear images from UI after successful submission
        clearImages();
        // Close the screen after success and return true to indicate success
        Navigator.pop(context, true);
      } else {
        final error = json.decode(response.body);
        showCustomToast(
          context,
          error['error']?['message'] ?? 'KYC submission failed.',
          isError: true,
        );
        // Clear images from UI even after failure
        clearImages();
      }
    } catch (e) {
      print(" Exception during KYC: $e");

      isLoading.value = false;
      showCustomToast(context, "Something went wrong. Please try again.", isError: true);
      // Clear images from UI on exception
      clearImages();
    }
  }

  Future<bool?> showKycDialog(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const KycScreen(),
      ),
    );
    // Return the result so the caller can refresh if needed
    return result as bool?;
  }
}

