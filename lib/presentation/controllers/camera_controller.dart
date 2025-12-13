import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/message_constants.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FaceLoginCameraController extends GetxController
    with GetSingleTickerProviderStateMixin {
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final RxBool isCameraInitialized = false.obs;
  final RxBool isFaceDetected = false.obs;
  final RxBool isProcessing = false.obs;
  final RxBool hasAutoStarted = false.obs;
  final RxInt retryCount = 0.obs;
  final RxBool showTryAgainButton = false.obs;
  final RxString statusMessage = ''.obs;
  final RxString subStatusMessage = ''.obs;

  bool _isDetectingFrame = false;
  DateTime? _lastProcessedFrameTime;
  static const Duration _frameThrottleDuration = Duration(milliseconds: 200);
  static const int _maxRetries = AppConstants.maxRetries;

  Animation<double> get pulseAnimation => _pulseAnimation;

  @override
  void onInit() {
    super.onInit();
    _initializePulseAnimation();
    _initializeFaceDetector();
    _initializeCamera();
  }

  void _initializePulseAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: AppConstants.pulseAnimationDuration,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: AppConstants.pulseAnimationMin,
      end: AppConstants.pulseAnimationMax,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast, // Fast mode for real-time detection
        enableContours: AppConstants.enableContours,
        enableLandmarks: AppConstants.enableLandmarks,
        minFaceSize: AppConstants.faceDetectionMinSize,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
        debugPrint("✅ Camera focus and exposure set to auto");
      } catch (e) {
        debugPrint("⚠️ Could not set focus/exposure mode: $e");
      }

      await Future.delayed(AppConstants.cameraStabilizationDelay);
      isCameraInitialized.value = true;
      _startFaceDetectionStream();
      debugPrint("✅ Camera initialized successfully");
    } catch (e) {
      debugPrint("❌ Camera initialization failed: $e");
      isCameraInitialized.value = false;
    }
  }

  void _startFaceDetectionStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;

    _cameraController!.startImageStream((CameraImage cameraImage) async {
      // Frame throttling - skip frames if processing too frequently
      final now = DateTime.now();
      if (_lastProcessedFrameTime != null && 
          now.difference(_lastProcessedFrameTime!) < _frameThrottleDuration) {
        return; // Skip this frame to prevent overload
      }
      
      if (_isDetectingFrame || isFaceDetected.value || isProcessing.value) return;
      _isDetectingFrame = true;
      _lastProcessedFrameTime = now;

      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in cameraImage.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final metadata = InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: InputImageRotationValue.fromRawValue(
                  _cameraController!.description.sensorOrientation) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormatValue.fromRawValue(cameraImage.format.raw) ??
              InputImageFormat.nv21,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        );

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );

        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty && !isFaceDetected.value && !isProcessing.value) {
          final face = faces.first;
          if (_isFaceGoodQuality(face, cameraImage.width, cameraImage.height)) {
            isFaceDetected.value = true;
            debugPrint("✅ GOOD FACE DETECTED — capturing...");

            try {
              await _cameraController!.stopImageStream();
            } catch (_) {}

            if (!hasAutoStarted.value) {
              hasAutoStarted.value = true;
              retryCount.value = 0;
              // Trigger capture callback
              onFaceDetected?.call();
            }
          } else {
            debugPrint("⚠️ Face detected but quality not good enough");
          }
        }
      } catch (e) {
        debugPrint("❌ Face detection error: $e");
      } finally {
        _isDetectingFrame = false;
      }
    });
  }

  bool _isFaceGoodQuality(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;
    final faceArea = faceWidth * faceHeight;
    final imageArea = imageWidth * imageHeight;
    final faceSizeRatio = faceArea / imageArea;

    if (faceSizeRatio < AppConstants.minFaceSize) {
      debugPrint("⚠️ Face too small: ${(faceSizeRatio * 100).toStringAsFixed(1)}%");
      return false;
    }

    final centerX = boundingBox.left + (faceWidth / 2);
    final centerY = boundingBox.top + (faceHeight / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.3 || offsetY > 0.3) {
      debugPrint("⚠️ Face too off-center: X=${(offsetX * 100).toStringAsFixed(1)}%, Y=${(offsetY * 100).toStringAsFixed(1)}%");
      return false;
    }

    return true;
  }

  Future<XFile?> captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    try {
      XFile? capturedImage;
      await Future.delayed(AppConstants.captureDelay);

      for (int attempt = 1; attempt <= 3; attempt++) {
        debugPrint("📸 Capture attempt $attempt");

        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();

        if (bytes.lengthInBytes > AppConstants.minImageSizeBytes) {
          capturedImage = image;
          debugPrint("✅ Captured image with good quality: ${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
          break;
        } else {
          debugPrint("⚠️ Image quality low (${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB), trying again...");
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      return capturedImage;
    } catch (e) {
      debugPrint("❌ Error capturing: $e");
      return null;
    }
  }

  void handleRetry() {
    retryCount.value++;
    debugPrint("🔄 Retry attempt ${retryCount.value}/$_maxRetries");

    if (retryCount.value < _maxRetries) {
      // Auto-retry logic handled by parent
      onRetryNeeded?.call();
    } else {
      showTryAgainButton.value = true;
      statusMessage.value = MessageConstants.faceRecognitionFailed;
      subStatusMessage.value = MessageConstants.centerFaceMessage;
      debugPrint("❌ Max retries reached. Showing try again button.");
    }
  }

  void restartProcess() {
    retryCount.value = 0;
    showTryAgainButton.value = false;
    hasAutoStarted.value = false;
    isProcessing.value = false;
    isFaceDetected.value = false;
    statusMessage.value = '';
    subStatusMessage.value = '';

    if (isCameraInitialized.value && _cameraController != null) {
      _startFaceDetectionStream();
    }
  }

  // Callbacks
  VoidCallback? onFaceDetected;
  VoidCallback? onRetryNeeded;

  @override
  void onClose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    super.onClose();
  }
}

