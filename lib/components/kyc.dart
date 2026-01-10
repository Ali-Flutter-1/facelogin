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

import 'package:shared_preferences/shared_preferences.dart';

class KycController extends GetxController {
  var frontImage = Rx<XFile?>(null);
  var backImage = Rx<XFile?>(null);
  var frontImageId = RxString('');
  var backImageId = RxString('');
  RxInt step = 1.obs;
  RxBool isLoading = false.obs;
  RxBool isUploadingFront = false.obs;
  RxBool isUploadingBack = false.obs;
  
  // Countdown timer for verification
  static const int verificationTimeSeconds = 150;
  RxInt remainingSeconds = verificationTimeSeconds.obs;
  Timer? _countdownTimer;

  final ImagePicker picker = ImagePicker();
  
  /// Start the countdown timer
  void _startCountdown() {
    remainingSeconds.value = verificationTimeSeconds;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        remainingSeconds.value--;
      } else {
        timer.cancel();
      }
    });
  }
  
  /// Stop the countdown timer
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }
  
  /// Format seconds to MM:SS
  String get formattedRemainingTime {
    final minutes = (remainingSeconds.value ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSeconds.value % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
  
  @override
  void onClose() {
    _stopCountdown();
    super.onClose();
  }




  // Upload image to get ID/path
  Future<String?> uploadImageToServer(XFile imageFile, String fieldName, BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) {
        showCustomToast(context, "No access token found.", isError: true);
        return null;
      }

      // Validate image file
      if (imageFile.path.isEmpty && !kIsWeb) {
        showCustomToast(context, "Invalid image file. Please try again.", isError: true);
        return null;
      }

      final uploadUrl = Uri.parse('https://idp.pollus.tech/api/auth/images/upload/');
      var request = http.MultipartRequest('POST', uploadUrl);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json, text/plain, */*';

      // Detect image format and set proper content type
      String? imageExtension;
      MediaType? contentType;
      
      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        final fileName = imageFile.name.isNotEmpty ? imageFile.name : 'image.jpg';
        
        // Detect format from file name or bytes
        imageExtension = fileName.toLowerCase().split('.').last;
        if (imageExtension == 'jpg' || imageExtension == 'jpeg') {
          contentType = MediaType('image', 'jpeg');
        } else if (imageExtension == 'png') {
          contentType = MediaType('image', 'png');
        } else {
          // Default to JPEG
          contentType = MediaType('image', 'jpeg');
          imageExtension = 'jpg';
        }
        
        final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

        request.files.add(http.MultipartFile(
          fieldName,
          Stream.value(uint8List),
          uint8List.length,
          filename: imageFile.name,
          contentType: contentType,
        ));
      } else {
        // For mobile, detect format from file path
        final path = imageFile.path.toLowerCase();
        if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          contentType = MediaType('image', 'jpeg');
        } else if (path.endsWith('.png')) {
          contentType = MediaType('image', 'png');
        } else {
          // Default to JPEG
          contentType = MediaType('image', 'jpeg');
        }
        
        request.files.add(await http.MultipartFile.fromPath(
          fieldName,
          imageFile.path,
          contentType: contentType,
        ));
      }
      
      print("📤 Uploading $fieldName (${contentType?.mimeType ?? 'unknown'}) to $uploadUrl");

      print("📤 Uploading $fieldName to $uploadUrl");
      
      // Add timeout to prevent hanging
      var streamed = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Image upload timed out after 60 seconds');
        },
      );
      
      var responseBody = await streamed.stream.bytesToString();
      final response = http.Response(responseBody, streamed.statusCode);

      print("📤 Upload response (${response.statusCode}): ${response.body}");
      
      // Log response details for debugging
      if (response.statusCode != 200 && response.statusCode != 201) {
        print("❌ Upload failed - Status: ${response.statusCode}, Body: ${response.body}");
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);

          String? imageId;
          
          // Safely extract image ID, handling cases where it might be false, null, or a string
          if (fieldName == 'id_front_image') {
            final frontIdValue = data['data']?['front_image_id'];
            // Check if it's a valid string (not false, null, or empty)
            if (frontIdValue != null && frontIdValue != false && frontIdValue.toString().trim().isNotEmpty) {
              imageId = frontIdValue.toString().trim();
            } else if (frontIdValue == false) {
              // If explicitly false, the upload failed on server side
              print("❌ Server returned false for front_image_id - upload may have failed");
              showCustomToast(context, "Image upload failed. Please try again.", isError: true);
              return null;
            }
            // Try to get from front_url if ID is not available
            if ((imageId == null || imageId.isEmpty) && frontIdValue != false) {
              final frontUrl = data['data']?['front_url'];
              if (frontUrl != null && frontUrl != false && frontUrl.toString().trim().isNotEmpty) {
                // Extract ID from URL path if possible
                final urlString = frontUrl.toString().trim();
                // Check if URL is complete (not just /storage/)
                if (urlString.endsWith('/storage/') || urlString.endsWith('/storage')) {
                  print("⚠️ Incomplete front_url received: $urlString");
                  showCustomToast(context, "Image upload incomplete. Please try again.", isError: true);
                  return null;
                }
                // Try to extract ID from URL (e.g., /storage/12345/image.jpg -> 12345)
                final urlParts = urlString.split('/').where((p) => p.isNotEmpty && p != 'storage').toList();
                if (urlParts.isNotEmpty) {
                  // Use the first meaningful part as potential ID
                  final potentialId = urlParts.first;
                  if (potentialId.isNotEmpty) {
                    imageId = potentialId;
                    print("⚠️ Extracted ID from front_url: $imageId");
                  } else {
                    // Use full URL as fallback
                    imageId = urlString;
                    print("⚠️ Using full front_url as fallback: $imageId");
                  }
                } else {
                  imageId = urlString;
                  print("⚠️ Using front_url as fallback: $imageId");
                }
              }
            }
          } else if (fieldName == 'id_back_image') {
            final backIdValue = data['data']?['back_image_id'];
            // Check if it's a valid string (not false, null, or empty)
            if (backIdValue != null && backIdValue != false && backIdValue.toString().trim().isNotEmpty) {
              imageId = backIdValue.toString().trim();
            } else if (backIdValue == false) {
              // If explicitly false, the upload failed on server side
              print("❌ Server returned false for back_image_id - upload may have failed");
              showCustomToast(context, "Image upload failed. Please try again.", isError: true);
              return null;
            }
            // Try to get from back_url if ID is not available
            if ((imageId == null || imageId.isEmpty) && backIdValue != false) {
              final backUrl = data['data']?['back_url'];
              if (backUrl != null && backUrl != false && backUrl.toString().trim().isNotEmpty) {
                // Extract ID from URL path if possible
                final urlString = backUrl.toString().trim();
                // Check if URL is complete (not just /storage/)
                if (urlString.endsWith('/storage/') || urlString.endsWith('/storage')) {
                  print("⚠️ Incomplete back_url received: $urlString");
                  showCustomToast(context, "Image upload incomplete. Please try again.", isError: true);
                  return null;
                }
                // Try to extract ID from URL (e.g., /storage/12345/image.jpg -> 12345)
                final urlParts = urlString.split('/').where((p) => p.isNotEmpty && p != 'storage').toList();
                if (urlParts.isNotEmpty) {
                  // Use the first meaningful part as potential ID
                  final potentialId = urlParts.first;
                  if (potentialId.isNotEmpty) {
                    imageId = potentialId;
                    print("⚠️ Extracted ID from back_url: $imageId");
                  } else {
                    // Use full URL as fallback
                    imageId = urlString;
                    print("⚠️ Using full back_url as fallback: $imageId");
                  }
                } else {
                  imageId = urlString;
                  print("⚠️ Using back_url as fallback: $imageId");
                }
              }
            }
          }

          // Fallback to other possible formats (only if still null)
          if (imageId == null || imageId.isEmpty) {
            final fallbackId = data['id'] ??
                data['file_id'] ??
                data['image_id'] ??
                data['path'] ??
                data['url'] ??
                data['data']?['id'] ??
                data['data']?['file_id'] ??
                data['data']?['image_id'] ??
                data['data']?['path'] ??
                data['data']?['url'];
            
            if (fallbackId != null && fallbackId != false && fallbackId.toString().isNotEmpty) {
              imageId = fallbackId.toString();
            }
          }

          if (imageId != null && imageId.isNotEmpty) {
            print("✅ Image uploaded successfully, ID: $imageId");
            return imageId;
          } else {
            print("⚠️ Upload succeeded but no valid ID found in response: $data");
            showCustomToast(context, "Image uploaded but ID not received. Please try again.", isError: true);
          }
        } catch (e) {
          print("❌ Failed to parse upload response: $e");
          print("❌ Response body was: ${response.body}");
          showCustomToast(context, "Failed to process upload response. Please try again.", isError: true);
        }
      } else {
        print("❌ Upload failed with status ${response.statusCode}: ${response.body}");
        
        // Try to parse error message from response
        String errorMessage = "Upload failed. Please try again.";
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map) {
            errorMessage = errorData['error']?['message'] ?? 
                          errorData['message'] ?? 
                          errorData['error']?.toString() ?? 
                          errorMessage;
          }
        } catch (_) {
          // If can't parse, use default message
        }
        
        showCustomToast(context, errorMessage, isError: true);
      }

      return null;
    } on TimeoutException catch (e) {
      print("❌ Upload timeout: $e");
      showCustomToast(context, "Upload timed out. Please check your connection and try again.", isError: true);
      return null;
    } on http.ClientException catch (e) {
      print("❌ Network error: $e");
      showCustomToast(context, "Network error. Please check your connection and try again.", isError: true);
      return null;
    } catch (e) {
      print("❌ Error uploading image: $e");
      print("❌ Error type: ${e.runtimeType}");
      showCustomToast(context, "Failed to upload image: ${e.toString()}. Please try again.", isError: true);
      return null;
    }
  }

  // 📸 Pick image and upload it immediately
  // Only allows camera capture with back camera
  Future<void> pickImage(bool isFront, ImageSource source) async {
    try {
      // Force camera source and back camera only
      // Use higher quality for better image recognition, but compress to reasonable size
      final picked = await picker.pickImage(
        source: ImageSource.camera, // Always use camera, ignore source parameter
        preferredCameraDevice: CameraDevice.rear, // Force back camera only
        imageQuality: 85, // Good balance between quality and file size
        maxWidth: 1920, // Limit width to prevent huge files
        maxHeight: 1920, // Limit height to prevent huge files
      );
      
      if (picked != null) {
        // Validate file exists and is readable
        try {
          final fileSize = await picked.length();
          if (fileSize == 0) {
            showCustomToast(Get.context!, "Image file is empty. Please try again.", isError: true);
            return;
          }
          // Check file size (max 10MB)
          if (fileSize > 10 * 1024 * 1024) {
            showCustomToast(Get.context!, "Image is too large. Please choose a smaller image.", isError: true);
            return;
          }
          print("📸 Selected image: ${picked.path}, size: ${(fileSize / 1024).toStringAsFixed(2)} KB");
        } catch (e) {
          print("⚠️ Error reading image file: $e");
          showCustomToast(Get.context!, "Cannot read image file. Please try again.", isError: true);
          return;
        }
        
        if (isFront) {
          frontImage.value = picked;
          // Upload front image immediately
          isUploadingFront.value = true;
          try {
            final imageId = await uploadImageToServer(picked, 'id_front_image', Get.context!);
            isUploadingFront.value = false;
            if (imageId != null && imageId.isNotEmpty) {
              frontImageId.value = imageId;
              print("✅ Front image uploaded successfully with ID: $imageId");
              showCustomToast(Get.context!, "Front image uploaded successfully!");
            } else {
              print("❌ Front image upload returned null ID");
              showCustomToast(Get.context!, "Failed to upload front image. Please try again.", isError: true);
              frontImage.value = null; // Clear the image if upload failed
            }
          } catch (e) {
            isUploadingFront.value = false;
            print("❌ Error uploading front image: $e");
            showCustomToast(Get.context!, "Failed to upload front image: ${e.toString()}", isError: true);
            frontImage.value = null; // Clear the image on error
          }
        } else {
          backImage.value = picked;
          // Upload back image immediately
          isUploadingBack.value = true;
          try {
            final imageId = await uploadImageToServer(picked, 'id_back_image', Get.context!);
            isUploadingBack.value = false;
            if (imageId != null && imageId.isNotEmpty) {
              backImageId.value = imageId;
              print("✅ Back image uploaded successfully with ID: $imageId");
              showCustomToast(Get.context!, "Back image uploaded successfully!");
            } else {
              print("❌ Back image upload returned null ID");
              showCustomToast(Get.context!, "Failed to upload back image. Please try again.", isError: true);
              backImage.value = null; // Clear the image if upload failed
            }
          } catch (e) {
            isUploadingBack.value = false;
            print("❌ Error uploading back image: $e");
            showCustomToast(Get.context!, "Failed to upload back image: ${e.toString()}", isError: true);
            backImage.value = null; // Clear the image on error
          }
        }
      } else {
        print("ℹ️ User cancelled image selection");
        // Don't show error if user just cancelled
      }
    } catch (e) {
      if (isFront) {
        isUploadingFront.value = false;
        frontImage.value = null;
      } else {
        isUploadingBack.value = false;
        backImage.value = null;
      }
      print("❌ Image pick error: $e");
      showCustomToast(Get.context!, "Failed to select image: ${e.toString()}. Please try again.", isError: true);
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
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');
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
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

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
    _startCountdown();
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
      _stopCountdown();
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
      _stopCountdown();
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

