import 'dart:convert';

import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/data/models/image_upload_response_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ImageService {
  final http.Client _client;
  final FlutterSecureStorage _storage;

  ImageService({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  /// Resize image to target resolution while maintaining aspect ratio
  Future<Uint8List> resizeImageToWebResolution(Uint8List imageBytes) async {
    try {
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        debugPrint("⚠️ Could not decode image, using original");
        return imageBytes;
      }

      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
      debugPrint("📐 Original image size: ${originalWidth}x${originalHeight}");

      // Calculate target dimensions (maintain aspect ratio)
      int targetWidth = AppConstants.targetImageWidth;
      int targetHeight = AppConstants.targetImageHeight;

      final aspectRatio = originalWidth / originalHeight;
      if (aspectRatio > (AppConstants.targetImageWidth / AppConstants.targetImageHeight)) {
        targetHeight = (targetWidth / aspectRatio).round();
      } else {
        targetWidth = (targetHeight * aspectRatio).round();
      }

      // Only resize if image is larger than target
      if (originalWidth <= targetWidth && originalHeight <= targetHeight) {
        debugPrint("✅ Image already at or below target size, keeping original");
        return imageBytes;
      }

      debugPrint("🔄 Resizing from ${originalWidth}x${originalHeight} to ${targetWidth}x${targetHeight}...");

      final resizedImage = img.copyResize(
        decodedImage,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );

      final jpegBytes = img.encodeJpg(
        resizedImage,
        quality: AppConstants.jpegQuality,
      );
      final resizedBytes = jpegBytes is Uint8List ? jpegBytes : Uint8List.fromList(jpegBytes);

      debugPrint("✅ Image resized: ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB → ${(resizedBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
      return resizedBytes;
    } catch (e) {
      debugPrint("⚠️ Image resize failed: $e, using original");
      return imageBytes;
    }
  }

  /// Convert image bytes to base64 data URL
  String imageToBase64DataUrl(Uint8List imageBytes) {
    final base64Image = base64Encode(imageBytes);
    return "data:image/jpeg;base64,$base64Image";
  }

  /// Upload image to server
  Future<ImageUploadResponseModel?> uploadImage(
    XFile imageFile,
    String fieldName,
  ) async {
    try {
      final token = await _storage.read(key: AppConstants.accessTokenKey);
      if (token == null || token.isEmpty) {
        throw Exception('No access token found');
      }

      final uploadUrl = Uri.parse(ApiConstants.imageUpload);
      var request = http.MultipartRequest('POST', uploadUrl);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = ApiConstants.acceptHeader;

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

      debugPrint("📤 Uploading $fieldName to $uploadUrl");
      var streamed = await _client.send(request);
      var responseBody = await streamed.stream.bytesToString();
      final response = http.Response(responseBody, streamed.statusCode);

      debugPrint("📤 Upload response (${response.statusCode}): ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);
          final uploadResponse = ImageUploadResponseModel.fromJson(data);
          final imageId = uploadResponse.getImageId(fieldName);

          if (imageId != null) {
            debugPrint("✅ Image uploaded successfully, ID: $imageId");
            return uploadResponse;
          } else {
            debugPrint("⚠️ Upload succeeded but no ID found in response: $data");
          }
        } catch (e) {
          debugPrint("❌ Failed to parse upload response: $e");
        }
      } else {
        debugPrint("❌ Upload failed with status ${response.statusCode}: ${response.body}");
      }

      return null;
    } catch (e) {
      debugPrint("❌ Error uploading image: $e");
      return null;
    }
  }
}

