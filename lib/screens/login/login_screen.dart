import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:facelogin/constant/constant.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/customWidgets/device_pairing_dialog.dart';
import 'package:facelogin/screens/profile/profile_screen.dart';
import 'package:facelogin/data/repositories/auth_repository.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class GlassMorphismLoginScreen extends StatefulWidget {
  const GlassMorphismLoginScreen({Key? key}) : super(key: key);

  @override
  State<GlassMorphismLoginScreen> createState() =>
      _GlassMorphismLoginScreenState();
}

class _GlassMorphismLoginScreenState extends State<GlassMorphismLoginScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;

  bool _faceDetected = false;
  bool _isProcessing = false;
  bool _isCameraInitialized = false;

  bool _hasAutoStarted = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _showTryAgainButton = false;

  final _storage = const FlutterSecureStorage();
  String _statusMessage = '';
  String _subStatusMessage = '';
  String _faceGuidanceMessage = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isDetectingFrame = false;
  DateTime? _lastProcessedFrameTime;
  static const Duration _frameThrottleDuration = Duration(milliseconds: 200);

  DateTime? _faceDetectionStartTime;
  static const Duration _faceDetectionTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
        minFaceSize: 0.15,
      ),
    );

    _initializeCameraSilently();
  }

  Future<void> _initializeCameraSilently() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      // Stream format: iOS BGRA, Android YUV
      final fmt = Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420;

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: fmt,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
        debugPrint("✅ Camera focus/exposure set to auto");
      } catch (e) {
        debugPrint("⚠️ Could not set focus/exposure mode: $e");
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;
      setState(() => _isCameraInitialized = true);

      _startFaceDetectionStream();
      debugPrint("✅ Camera initialized successfully");
    } catch (e) {
      debugPrint("❌ Camera initialization failed: $e");
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      }
    }
  }

  bool _isFaceGoodQuality(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;

    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;
    final faceArea = faceWidth * faceHeight;
    final imageArea = imageWidth * imageHeight;
    final faceSizePercentage = (faceArea / imageArea) * 100;

    if (faceSizePercentage < 15) {
      debugPrint("❌ Face too small: ${faceSizePercentage.toStringAsFixed(1)}%");
      return false;
    }

    if (faceSizePercentage > 60) {
      debugPrint("❌ Face too large: ${faceSizePercentage.toStringAsFixed(1)}%");
      return false;
    }

    final aspectRatio = faceWidth / faceHeight;
    if (aspectRatio < 0.6 || aspectRatio > 1.4) {
      debugPrint("❌ Face aspect ratio invalid: $aspectRatio");
      return false;
    }

    final centerX = boundingBox.left + (faceWidth / 2);
    final centerY = boundingBox.top + (faceHeight / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.4 || offsetY > 0.4) {
      debugPrint(
          "❌ Face too far from center: X=${offsetX.toStringAsFixed(2)}, Y=${offsetY.toStringAsFixed(2)}");
      return false;
    }

    debugPrint(
        "✅ Face quality check passed: ${faceSizePercentage.toStringAsFixed(1)}%, aspect=$aspectRatio, centered");
    return true;
  }

  String? _getFaceQualityGuidance(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;

    final faceArea = boundingBox.width * boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceSizePercentage = (faceArea / imageArea) * 100;

    if (faceSizePercentage < 15) return "Move closer to the camera";
    if (faceSizePercentage > 60) return "Move back from the camera";

    final aspectRatio = boundingBox.width / boundingBox.height;
    if (aspectRatio < 0.6 || aspectRatio > 1.4) return "Face your camera directly";

    final centerX = boundingBox.left + (boundingBox.width / 2);
    final centerY = boundingBox.top + (boundingBox.height / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.4 || offsetY > 0.4) {
      return offsetX > offsetY ? "Center your face horizontally" : "Center your face vertically";
    }

    return null;
  }

  /// ✅ Convert iOS BGRA8888 stream frame -> JPEG bytes (no shutter, no flash)
  Future<Uint8List> _bgrToJpegFromStream(CameraImage image) async {
    if (image.format.group != ImageFormatGroup.bgra8888) {
      throw Exception("Expected BGRA8888 on iOS, got ${image.format.group}");
    }

    final plane = image.planes.first;

    // Copy bytes immediately (buffer may change after await)
    final bgraBytes = Uint8List.fromList(plane.bytes);

    final converted = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: bgraBytes.buffer,
      rowStride: plane.bytesPerRow,
      bytesOffset: 0,
      order: img.ChannelOrder.bgra,
    );

    final jpg = img.encodeJpg(converted, quality: 95);
    return Uint8List.fromList(jpg);
  }

  void _startFaceDetectionStream() {
    if (_cameraController == null) return;
    if (_cameraController!.value.isStreamingImages) return;

    _faceDetectionStartTime = DateTime.now();

    _cameraController!.startImageStream((CameraImage cameraImage) async {
      final now = DateTime.now();

      if (_lastProcessedFrameTime != null &&
          now.difference(_lastProcessedFrameTime!) < _frameThrottleDuration) {
        return;
      }

      if (_faceDetectionStartTime != null &&
          now.difference(_faceDetectionStartTime!) > _faceDetectionTimeout) {
        debugPrint("⚠️ Face detection timeout - restarting stream");
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {}
        _faceDetectionStartTime = DateTime.now();
        if (mounted && !_isProcessing) _startFaceDetectionStream();
        return;
      }

      if (_isDetectingFrame || _faceDetected) return;
      _isDetectingFrame = true;
      _lastProcessedFrameTime = now;

      try {
        // Build bytes (no WriteBuffer issues; plain concat)
        final allBytes = <int>[];
        for (final plane in cameraImage.planes) {
          allBytes.addAll(plane.bytes);
        }
        final bytes = Uint8List.fromList(allBytes);

        // ✅ Correct MLKit format (iOS BGRA, Android YUV)
        final inputFormat =
        (cameraImage.format.group == ImageFormatGroup.bgra8888)
            ? InputImageFormat.bgra8888
            : InputImageFormat.yuv_420_888;

        final metadata = InputImageMetadata(
          size: ui.Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(
            _cameraController!.description.sensorOrientation,
          ) ??
              InputImageRotation.rotation0deg,
          format: inputFormat,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        );

        final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty && !_faceDetected && !_isProcessing) {
          final face = faces.first;

          if (_isFaceGoodQuality(face, cameraImage.width, cameraImage.height)) {
            _faceDetected = true;
            debugPrint("✅ GOOD FACE DETECTED — capturing...");

            _faceDetectionStartTime = null;

            if (mounted) {
              setState(() {
                _faceGuidanceMessage = '';
                _isProcessing = true;
                _statusMessage = 'Capturing Image...';
                _subStatusMessage =
                'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
              });
            }

            if (mounted && !_hasAutoStarted) {
              _hasAutoStarted = true;
              _retryCount = 0;

              // ✅ iOS: capture from stream (silent + no flash)
              if (Platform.isIOS) {
                await _captureFromStreamAndSend(cameraImage);
              } else {
                // Android: keep your existing takePicture behavior
                try {
                  await _cameraController!.stopImageStream();
                } catch (_) {}
                await _captureAndSendSilently();
              }
            }
          } else {
            final guidanceMessage =
            _getFaceQualityGuidance(face, cameraImage.width, cameraImage.height);
            if (mounted && guidanceMessage != null) {
              setState(() => _faceGuidanceMessage = guidanceMessage);
            }
          }
        } else if (faces.isEmpty && !_faceDetected && !_isProcessing) {
          if (mounted) {
            setState(() => _faceGuidanceMessage = 'Position your face in front of the camera');
          }
        }
      } catch (e) {
        debugPrint("Face detection error: $e");
      } finally {
        _isDetectingFrame = false;
      }
    });
  }

  /// ✅ iOS capture flow (same logic: "capture" -> resize -> send -> handle response)
  Future<void> _captureFromStreamAndSend(CameraImage frame) async {
    try {
      setState(() {
        _statusMessage = 'Processing Face...';
        _subStatusMessage =
        'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
      });

      Uint8List bytes = await _bgrToJpegFromStream(frame);
      
      // ✅ Validate raw image quality before resizing
      if (bytes.lengthInBytes < 20 * 1024) {
        throw Exception("Raw image quality too low: ${bytes.lengthInBytes} bytes");
      }
      
      bytes = await _resizeImageToWebResolution(bytes);

      await _sendBytesToApi(bytes);
    } catch (e) {
      debugPrint("❌ iOS stream capture failed: $e");
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
        _statusMessage = '';
        _subStatusMessage = '';
        _faceGuidanceMessage = '';
      });
      final errorMsg = e.toString().contains("quality too low") || e.toString().contains("dimensions too small")
          ? "Image quality is too low. Please position your face better and try again."
          : "Unable to capture image. Please try again.";
      showCustomToast(context, errorMsg, isError: true);
      _handleRetry();
    }
  }

  /// Your existing resize logic unchanged
  Future<Uint8List> _resizeImageToWebResolution(Uint8List imageBytes) async {
    try {
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        debugPrint("⚠️ Could not decode image, using original");
        return imageBytes;
      }

      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
      debugPrint("📐 Original image size: ${originalWidth}x${originalHeight}");
      
      // ✅ Validate minimum dimensions to prevent very small/low-quality images
      if (originalWidth < 320 || originalHeight < 240) {
        throw Exception("Image dimensions too small: ${originalWidth}x${originalHeight} (minimum: 320x240)");
      }

      int targetWidth = 1280;
      int targetHeight = 720;

      final aspectRatio = originalWidth / originalHeight;
      if (aspectRatio > (1280 / 720)) {
        targetHeight = (targetWidth / aspectRatio).round();
      } else {
        targetWidth = (targetHeight * aspectRatio).round();
      }

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

      final jpegBytes = img.encodeJpg(resizedImage, quality: 95);
      final resizedBytes =
      jpegBytes is Uint8List ? jpegBytes : Uint8List.fromList(jpegBytes);

      debugPrint(
          "✅ Image resized: ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB → ${(resizedBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
      
      // ✅ Final validation: ensure resized image meets quality threshold
      if (resizedBytes.lengthInBytes < 20 * 1024) {
        throw Exception("Resized image quality too low: ${resizedBytes.lengthInBytes} bytes");
      }
      
      return resizedBytes;
    } catch (e) {
      debugPrint("⚠️ Image resize/validation failed: $e");
      rethrow; // Re-throw to let caller handle the error
    }
  }

  /// Android capture unchanged (takePicture)
  Future<void> _captureAndSendSilently() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      showCustomToast(context, "Camera not initialized.", isError: true);
      return;
    }

    if (!_isProcessing && mounted) {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Capturing Image...';
        _subStatusMessage =
        'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
      });
    }

    try {
      XFile? capturedImage;
      await Future.delayed(const Duration(milliseconds: 800));

      for (int attempt = 1; attempt <= 3; attempt++) {
        debugPrint("📸 Capture attempt $attempt");

        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();

        if (bytes.lengthInBytes > 100 * 1024) {
          capturedImage = image;
          debugPrint(
              "✅ Captured image with good quality: ${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
          break;
        } else {
          debugPrint(
              "⚠️ Image quality low (${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB), trying again...");
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (capturedImage != null) {
        setState(() {
          _statusMessage = 'Processing Face...';
          _subStatusMessage =
          'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
        });
        await Future.delayed(const Duration(milliseconds: 500));

        await _sendToApi(capturedImage);
      } else {
        setState(() {
          _isProcessing = false;
          _faceDetected = false;
          _statusMessage = '';
          _subStatusMessage = '';
          _faceGuidanceMessage = '';
        });
        showCustomToast(context, "Unable to capture clear image.", isError: true);
        _handleRetry();
      }
    } catch (e) {
      debugPrint("Error capturing: $e");
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
        _statusMessage = '';
        _subStatusMessage = '';
        _faceGuidanceMessage = '';
      });
      showCustomToast(context, "Something went wrong. Please try again.", isError: true);
      if (_isCameraInitialized && _cameraController != null) {
        _hasAutoStarted = false;
        _startFaceDetectionStream();
      }
    }
  }

  /// ✅ iOS uses this (bytes directly) – SAME API payload
  Future<void> _sendBytesToApi(Uint8List bytes) async {
    const apiUrl = ApiConstants.loginOrRegister;

    try {
      setState(() {
        _statusMessage = 'Authenticating...';
        _subStatusMessage =
        'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
      });

      if (apiUrl.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Configuration error. Please contact support.", isError: true);
        debugPrint("❌ API URL is empty");
        return;
      }

      // ✅ Validate image quality: minimum 20KB to prevent low-quality images
      if (bytes.isEmpty || bytes.lengthInBytes < 20 * 1024) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Image quality is too low. Please try again.", isError: true);
        debugPrint("❌ Image too small: ${bytes.lengthInBytes} bytes (minimum: ${20 * 1024} bytes)");
        _handleRetry();
        return;
      }

      final base64Image = base64Encode(bytes);
      final dataUrl = "data:image/jpeg;base64,$base64Image";
      final jsonBody = jsonEncode({"face_image": dataUrl});

      http.Response response;
      try {
        response = await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonBody,
        ).timeout(const Duration(seconds: 30));
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Request failed. Please try again.", isError: true);
        debugPrint(" HTTP request failed: $e");
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseData = data["data"];

        if (responseData != null &&
            responseData["access_token"] != null &&
            responseData["refresh_token"] != null) {
          // Use AuthRepository to handle token storage and E2E bootstrap
          final authRepo = AuthRepository();
          final authResult = await authRepo.loginOrRegister(bytes);
          
          // Check if auth failed
          if (authResult.isError) {
            setState(() {
              _isProcessing = false;
              _faceDetected = false;
              _statusMessage = '';
              _subStatusMessage = '';
              _faceGuidanceMessage = '';
            });
            showCustomToast(context, authResult.error ?? "Failed to save session. Please try again.", isError: true);
            _handleRetry();
            return;
          }
          
          // Check if pairing is required
          if (authResult.needsPairing) {
            // Show pairing dialog
            await _handleDevicePairing(context, authRepo);
            return;
          }
          
          // Verify tokens were saved before navigating
          final savedToken = await authRepo.getAccessToken();
          if (savedToken == null) {
            setState(() {
              _isProcessing = false;
              _faceDetected = false;
              _statusMessage = '';
              _subStatusMessage = '';
              _faceGuidanceMessage = '';
            });
            showCustomToast(context, "Failed to save session. Please try again.", isError: true);
            _handleRetry();
            return;
          }
          
          // Success - navigate to profile
          showCustomToast(context, "Face login successful!");
          await Future.delayed(const Duration(milliseconds: 500));

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
          return;
        }

        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
          _faceGuidanceMessage = '';
        });
        showCustomToast(context, "No tokens received from server", isError: true);
        setState(() {
          _faceDetected = false;
          _faceGuidanceMessage = '';
        });
        _handleRetry();
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
          _faceGuidanceMessage = '';
        });

        String errorCode = "Face recognition failed. Please try again.";
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            if (errorData['error'] is Map && errorData['error'].containsKey('code')) {
              errorCode = errorData['error']['code'].toString();
            } else {
              errorCode = errorData['error'].toString();
            }
          }
        } catch (_) {}

        showCustomToast(context, errorCode, isError: true);

        setState(() {
          _faceDetected = false;
          _faceGuidanceMessage = '';
        });
        _handleRetry();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
        _statusMessage = '';
        _subStatusMessage = '';
        _faceGuidanceMessage = '';
      });
      debugPrint("❌ Unexpected error in _sendBytesToApi: $e");
      showCustomToast(context, "Something went wrong. Please try again.", isError: true);
      _handleRetry();
    }
  }

  /// Your original Android sender unchanged
  Future<void> _sendToApi(XFile imageFile) async {
    const apiUrl = ApiConstants.loginOrRegister;

    try {
      setState(() {
        _statusMessage = 'Authenticating...';
        _subStatusMessage =
        'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
      });

      if (apiUrl.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Configuration error. Please contact support.", isError: true);
        debugPrint("❌ API URL is empty");
        return;
      }

      Uint8List bytes = await imageFile.readAsBytes();
      bytes = await _resizeImageToWebResolution(bytes);

      // ✅ Validate image quality: minimum 20KB to prevent low-quality images
      if (bytes.isEmpty || bytes.lengthInBytes < 20 * 1024) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Image quality is too low. Please capture again.", isError: true);
        debugPrint("❌ Image too small: ${bytes.lengthInBytes} bytes (minimum: ${20 * 1024} bytes)");
        _handleRetry();
        return;
      }

      final base64Image = base64Encode(bytes);
      final dataUrl = "data:image/jpeg;base64,$base64Image";
      final jsonBody = jsonEncode({"face_image": dataUrl});

      http.Response response;
      try {
        response = await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonBody,
        ).timeout(const Duration(seconds: 30));
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Request failed. Please try again.", isError: true);
        debugPrint(" HTTP request failed: $e");
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseData = data["data"];

        if (responseData != null &&
            responseData["access_token"] != null &&
            responseData["refresh_token"] != null) {
          // Use AuthRepository to handle token storage and E2E bootstrap
          final authRepo = AuthRepository();
          final authResult = await authRepo.loginOrRegister(bytes);
          
          // Check if auth failed
          if (authResult.isError) {
            setState(() {
              _isProcessing = false;
              _faceDetected = false;
              _statusMessage = '';
              _subStatusMessage = '';
              _faceGuidanceMessage = '';
            });
            showCustomToast(context, authResult.error ?? "Failed to save session. Please try again.", isError: true);
            _handleRetry();
            return;
          }
          
          // Check if pairing is required
          if (authResult.needsPairing) {
            // Show pairing dialog
            await _handleDevicePairing(context, authRepo);
            return;
          }
          
          // Verify tokens were saved before navigating
          final savedToken = await authRepo.getAccessToken();
          if (savedToken == null) {
            setState(() {
              _isProcessing = false;
              _faceDetected = false;
              _statusMessage = '';
              _subStatusMessage = '';
              _faceGuidanceMessage = '';
            });
            showCustomToast(context, "Failed to save session. Please try again.", isError: true);
            _handleRetry();
            return;
          }
          
          // Success - navigate to profile
          showCustomToast(context, "Face login successful!");
          await Future.delayed(const Duration(milliseconds: 500));

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
          return;
        }

        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
          _faceGuidanceMessage = '';
        });
        showCustomToast(context, "No tokens received from server", isError: true);
        setState(() {
          _faceDetected = false;
          _faceGuidanceMessage = '';
        });
        _handleRetry();
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
          _faceGuidanceMessage = '';
        });

        String errorCode = "Face recognition failed. Please try again.";
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            if (errorData['error'] is Map && errorData['error'].containsKey('code')) {
              errorCode = errorData['error']['code'].toString();
            } else {
              errorCode = errorData['error'].toString();
            }
          }
        } catch (_) {}

        showCustomToast(context, errorCode, isError: true);

        setState(() {
          _faceDetected = false;
          _faceGuidanceMessage = '';
        });
        _handleRetry();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
        _statusMessage = '';
        _subStatusMessage = '';
        _faceGuidanceMessage = '';
      });
      debugPrint("❌ Unexpected error in _sendToApi: $e");
      final errorMsg = e.toString().contains("quality too low") || e.toString().contains("dimensions too small")
          ? "Image quality is too low. Please position your face better and try again."
          : "Something went wrong. Please try again.";
      showCustomToast(context, errorMsg, isError: true);
      _handleRetry();
    }
  }

  /// Retry logic: same idea, but restart stream (important because iOS stays streaming)
  Future<void> _handleRetry() async {
    _retryCount++;
    debugPrint("🔄 Retry attempt $_retryCount/$_maxRetries");

    // ✅ Always unlock the flow immediately
    if (mounted) {
      setState(() {
        _faceDetected = false;
        _isProcessing = false;
        _hasAutoStarted = false;
        _statusMessage = '';
        _subStatusMessage = '';
        _faceGuidanceMessage = '';
        _faceDetectionStartTime = DateTime.now();
      });
    }

    // ✅ Ensure stream is running again (safe even if already streaming)
    if (_isCameraInitialized && _cameraController != null) {
      _startFaceDetectionStream();
    }

    // If retries left, just wait a bit and let face detection trigger again
    if (_retryCount < _maxRetries) {
      await Future.delayed(const Duration(seconds: 2));
      return;
    }

    // Max retries: show Try Again button
    if (mounted) {
      setState(() {
        _showTryAgainButton = true;
        _statusMessage = 'Face recognition failed';
        _subStatusMessage =
        'Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account';
      });
    }
  }


  void _resetForNextAttempt() {
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _faceDetected = false;
      _statusMessage = '';
      _subStatusMessage = '';
      _faceGuidanceMessage = '';
      _faceDetectionStartTime = DateTime.now();
    });

    // On Android we stopped stream to take picture, so restart it.
    // On iOS stream never stopped; this is safe because start method checks isStreamingImages.
    if (_isCameraInitialized && _cameraController != null) {
      _startFaceDetectionStream();
    }
  }

  void _restartProcess() {
    setState(() {
      _retryCount = 0;
      _showTryAgainButton = false;
      _hasAutoStarted = false;
      _isProcessing = false;
      _faceDetected = false;
      _statusMessage = '';
      _subStatusMessage = '';
      _faceGuidanceMessage = '';
      _faceDetectionStartTime = DateTime.now();
    });

    if (_isCameraInitialized && _cameraController != null) {
      _startFaceDetectionStream();
    }
  }

  /// Handle device pairing flow when E2E is set up on another device
  Future<void> _handleDevicePairing(BuildContext context, AuthRepository authRepo) async {
    try {
      final accessToken = await authRepo.getAccessToken();
      if (accessToken == null) {
        showCustomToast(context, 'Session expired. Please try again.', isError: true);
        return;
      }

      final e2eService = E2EService();
      
      // Request pairing - this generates keys and gets OTP
      final pairingResult = await e2eService.requestDevicePairing(accessToken);
      
      if (!pairingResult.isSuccess || pairingResult.otp == null) {
        showCustomToast(
          context,
          pairingResult.error ?? 'Failed to request device pairing',
          isError: true,
        );
        return;
      }

      // Show pairing dialog with QR code and OTP
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DevicePairingDialog(
          otp: pairingResult.otp!,
          pairingToken: pairingResult.pairingToken,
          onCancel: () {
            Navigator.pop(dialogContext);
            setState(() {
              _isProcessing = false;
              _faceDetected = false;
            });
          },
          onApproved: () {
            // This will be called when polling detects approval
            Navigator.pop(dialogContext);
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }
          },
        ),
      );

      // Poll bootstrap API for pairing approval in background
      // Keep calling bootstrap until wrappedKu is received (after Device A approves)
      _pollForPairingApproval(
        context,
        accessToken,
      );
    } catch (e) {
      debugPrint('❌ Pairing error: $e');
      showCustomToast(context, 'Failed to start pairing: ${e.toString()}', isError: true);
    }
  }

  /// Poll bootstrap API for pairing approval
  /// Keeps calling bootstrap until wrappedKu is received (after Device A approves)
  Future<void> _pollForPairingApproval(
    BuildContext context,
    String accessToken,
  ) async {
    final e2eService = E2EService();
    const maxAttempts = 60; // 2 minutes max (60 attempts * 2 seconds)
    const pollInterval = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(pollInterval);

      if (!mounted) return;

      try {
        // Poll bootstrap API - it will return wrappedKu once pairing is approved
        final bootstrapResult = await e2eService.bootstrapForLogin(accessToken);

        if (bootstrapResult.isSuccess) {
          // Pairing approved and wrappedKu received!
          debugPrint('✅ Pairing approved - wrappedKu received via bootstrap');
          
          // Close dialog if still open
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          
          if (mounted) {
            showCustomToast(context, "Device paired successfully!");
            await Future.delayed(const Duration(milliseconds: 500));
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }
          }
          return;
        } else if (bootstrapResult.needsPairing) {
          // Still waiting for approval - continue polling
          debugPrint('⏳ Still waiting for pairing approval... (attempt ${attempt + 1}/$maxAttempts)');
          continue;
        } else {
          // Check if this is a key mismatch error (non-recoverable)
          final errorMessage = bootstrapResult.error ?? '';
          if (errorMessage.contains('keys mismatch') || 
              errorMessage.contains('different public key') ||
              errorMessage.contains('encrypted with a different')) {
            // Key mismatch - stop polling and show error
            debugPrint('❌ Key mismatch error - stopping polling: $errorMessage');
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            if (mounted) {
              showCustomToast(
                context, 
                'Pairing failed: Key mismatch. Please try pairing again.',
                isError: true,
              );
              setState(() {
                _isProcessing = false;
                _faceDetected = false;
              });
            }
            return;
          }
          
          // Some other error occurred - might be temporary, continue polling
          debugPrint('⚠️ Bootstrap error during polling: $errorMessage');
          // Continue polling in case it's a temporary error
          // Only stop if it's a critical error that won't resolve
          continue;
        }
      } catch (e) {
        debugPrint('❌ Polling error: $e');
        // Continue polling in case it's a temporary network error
        continue;
      }
    }

    // Timeout - pairing not approved within time limit
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
      showCustomToast(context, 'Pairing timeout. Please try again.', isError: true);
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF080B18),
              Color(0xFF0A0E21),
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: Image.asset('assets/images/2.jpeg', fit: BoxFit.cover),
              ),
            ),

            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    final clampedValue = value.clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: clampedValue,
                      child: Opacity(
                        opacity: clampedValue,
                        child: Image.asset(
                          'assets/images/valydlogo.png',
                          width: 120,
                          height: 120,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF415A77).withOpacity(_isProcessing ? 0.8 : 0.5),
                              const Color(0xFF1B263B).withOpacity(_isProcessing ? 0.7 : 0.5),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF415A77).withOpacity(_pulseAnimation.value * 0.9),
                              blurRadius: 40 * _pulseAnimation.value,
                              spreadRadius: 12 * _pulseAnimation.value,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(30),
                        child: Image.asset(
                          'assets/images/pngwing.com.png',
                          width: 75,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 35),

                  Text(
                    _isProcessing
                        ? (_statusMessage.isNotEmpty ? _statusMessage : 'Authenticating...')
                        : 'Face Recognition Active',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Text(
                      _isProcessing
                          ? (_subStatusMessage.isNotEmpty ? _subStatusMessage : 'Processing your face...')
                          : _faceGuidanceMessage.isNotEmpty
                          ? _faceGuidanceMessage
                          : _showTryAgainButton
                          ? "Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account"
                          : "Center your face and look at the camera for 5-6 s we are hashing your vector and creating your account",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w500,
                        color: _faceGuidanceMessage.isNotEmpty
                            ? Colors.orange.withOpacity(0.9)
                            : Colors.white.withOpacity(0.8),
                        letterSpacing: 0.2,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Text(
                      "Your video never leaves your device except for secure matching",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.1,
                        height: 1.4,
                      ),
                    ),
                  ),

                  if (_showTryAgainButton && !_isProcessing) ...[
                    const SizedBox(height: 30),
                    InkWell(
                      onTap: _restartProcess,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF415A77),
                              Color(0xFF1B263B),
                              Color(0xFF0D1B2A),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "Try Again",
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
