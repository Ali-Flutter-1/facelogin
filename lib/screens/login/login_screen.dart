import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:facelogin/constant/constant.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/screens/profile/profile_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
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
  bool _hasAutoStarted = false; // Track if auto-capture has started
  int _retryCount = 0; // Track retry attempts
  static const int _maxRetries = 3; // Maximum retry attempts
  bool _showTryAgainButton = false; // Show button after max retries
  final _storage = const FlutterSecureStorage();
  String _statusMessage = '';
  String _subStatusMessage = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize pulse animation for visual feedback
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initializeCameraSilently();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast, // Changed from accurate to fast
        enableContours: false,
        enableLandmarks: false,
        minFaceSize: 0.15, // Minimum 15% of image - prevents thumbs/small objects
      ),
    );



  }
  Future<void> _initializeCameraSilently() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      // Use high quality - good balance that matches web camera resolutions
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high, // High quality, matches typical web camera (720p-1080p)
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg, // Explicitly set JPEG format
      );

      await _cameraController!.initialize();

      // Set auto focus mode for better image quality
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
        debugPrint(" Camera focus and exposure set to auto");
      } catch (e) {
        debugPrint(" Could not set focus/exposure mode: $e");
      }

      // Give the camera more time to stabilize exposure and focus
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _startFaceDetectionStream();

        debugPrint("Camera initialized successfully");
        // Don't capture immediately - wait for face detection
      }
    } catch (e) {
      debugPrint(" Camera initialization failed: $e");
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }
  bool _isDetectingFrame = false;
  DateTime? _lastProcessedFrameTime;
  static const Duration _frameThrottleDuration = Duration(milliseconds: 200);

  /// Check if detected face meets quality requirements
  /// This prevents false positives like thumbs, small objects, etc.
  bool _isFaceGoodQuality(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;

    // Calculate face size as percentage of image
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;
    final faceArea = faceWidth * faceHeight;
    final imageArea = imageWidth * imageHeight;
    final faceSizePercentage = (faceArea / imageArea) * 100;

    // Face should be at least 15% of image (prevents thumbs/small objects)
    if (faceSizePercentage < 15) {
      debugPrint("❌ Face too small: ${faceSizePercentage.toStringAsFixed(1)}%");
      return false;
    }

    // Face should not be too large (too close to camera)
    if (faceSizePercentage > 60) {
      debugPrint("❌ Face too large: ${faceSizePercentage.toStringAsFixed(1)}%");
      return false;
    }

    // Check face aspect ratio (should be roughly square, not too wide or tall)
    final aspectRatio = faceWidth / faceHeight;
    if (aspectRatio < 0.6 || aspectRatio > 1.4) {
      debugPrint("❌ Face aspect ratio invalid: $aspectRatio");
      return false;
    }

    // Check face position - should be reasonably centered
    final centerX = boundingBox.left + (faceWidth / 2);
    final centerY = boundingBox.top + (faceHeight / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    // Allow face to be within 40% of center
    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.4 || offsetY > 0.4) {
      debugPrint("❌ Face too far from center: X=${offsetX.toStringAsFixed(2)}, Y=${offsetY.toStringAsFixed(2)}");
      return false;
    }

    debugPrint("✅ Face quality check passed: ${faceSizePercentage.toStringAsFixed(1)}%, aspect=$aspectRatio, centered");
    return true;
  }

  void _startFaceDetectionStream() {
    if (_cameraController == null) return;
    if (_cameraController!.value.isStreamingImages) return;

    _cameraController!.startImageStream((CameraImage cameraImage) async {
      // Frame throttling - skip frames if processing too frequently
      final now = DateTime.now();
      if (_lastProcessedFrameTime != null && 
          now.difference(_lastProcessedFrameTime!) < _frameThrottleDuration) {
        return; // Skip this frame to prevent overload
      }
      
      if (_isDetectingFrame || _faceDetected) return;
      _isDetectingFrame = true;
      _lastProcessedFrameTime = now;

      try {
        // Convert planes to bytes
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in cameraImage.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        // Metadata for MLKit
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

        // Create input image
        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );

        // Detect face
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty && !_faceDetected && !_isProcessing) {
          final face = faces.first;

          // Check if face quality is good enough
          if (_isFaceGoodQuality(face, cameraImage.width, cameraImage.height)) {
            _faceDetected = true;
            debugPrint("✅ GOOD FACE DETECTED — capturing...");

            try {
              await _cameraController!.stopImageStream();
            } catch (_) {}

            if (mounted && !_hasAutoStarted) {
              _hasAutoStarted = true;
              _retryCount = 0;
              await _captureAndSendSilently();
            }
          } else {
            debugPrint("⚠️ Face detected but quality not good enough (too small/off-center)");
          }
        }
      } catch (e) {
        debugPrint("Face detection error: $e");
      } finally {
        _isDetectingFrame = false;
      }
    });
  }

  /// Resize image to max 1280x720 (HD) to match web resolution and avoid "face too close" errors
  /// while maintaining good quality for face recognition using proper JPEG compression
  Future<Uint8List> _resizeImageToWebResolution(Uint8List imageBytes) async {
    try {
      // Decode JPEG image
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        debugPrint(" Could not decode image, using original");
        return imageBytes;
      }

      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
      debugPrint("📐 Original image size: ${originalWidth}x${originalHeight}");

      // Calculate target dimensions (max 1280x720, maintain aspect ratio)
      int targetWidth = 1280;
      int targetHeight = 720;

      // Maintain aspect ratio
      final aspectRatio = originalWidth / originalHeight;
      if (aspectRatio > (1280 / 720)) {
        // Image is wider than 16:9
        targetHeight = (targetWidth / aspectRatio).round();
      } else {
        // Image is taller than 16:9
        targetWidth = (targetHeight * aspectRatio).round();
      }

      // Only resize if image is larger than target
      if (originalWidth <= targetWidth && originalHeight <= targetHeight) {
        debugPrint("✅ Image already at or below target size, keeping original");
        return imageBytes;
      }

      debugPrint("🔄 Resizing from ${originalWidth}x${originalHeight} to ${targetWidth}x${targetHeight}...");

      // Resize using high-quality Lanczos resampling
      final resizedImage = img.copyResize(
        decodedImage,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear, // Good balance of quality and speed
      );

      // Encode back to JPEG with high quality (95% quality)
      // Using encodeJpg from image package
      final jpegBytes = img.encodeJpg(
        resizedImage,
        quality: 95,
      );
      final resizedBytes = jpegBytes is Uint8List ? jpegBytes : Uint8List.fromList(jpegBytes);

      debugPrint("✅ Image resized: ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB → ${(resizedBytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
      return resizedBytes;

    } catch (e) {
      debugPrint("⚠️ Image resize failed: $e, using original");
      return imageBytes;
    }
  }

  Future<void> _captureAndSendSilently() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      showCustomToast(context, "Camera not initialized.", isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturing Image...';
      _subStatusMessage = 'Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account';
    });

    try {
      XFile? capturedImage;
      // Wait a bit more for camera to stabilize exposure and focus
      await Future.delayed(const Duration(milliseconds: 800));

      for (int attempt = 1; attempt <= 3; attempt++) {
        debugPrint("📸 Capture attempt $attempt");

        // Take picture
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();

        // Check for reasonable quality - increased threshold for better quality
        // VeryHigh preset should produce images > 200KB typically
        if (bytes.lengthInBytes > 100 * 1024) { // At least 100KB for good quality
          capturedImage = image;
          debugPrint("✅ Captured image with good quality: ${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB");
          break;
        } else {
          debugPrint("⚠️ Image quality low (${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB), trying again...");
        }

        // Wait longer between attempts for better stabilization
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (capturedImage != null) {
        // Update status before processing
        setState(() {
          _statusMessage = 'Processing Face...';
          _subStatusMessage = 'Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account';
        });
        await Future.delayed(const Duration(milliseconds: 500)); // Show the hashing message

        await _sendToApi(capturedImage);
      } else {
        setState(() {
          _isProcessing = false;
          _faceDetected = false; // Reset to allow face detection again
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Unable to capture clear image.", isError: true);

        // Auto-retry with limit - restart face detection
        _handleRetry();
      }
    } catch (e) {
      debugPrint("Error capturing: $e");
      setState(() {
        _isProcessing = false;
        _faceDetected = false; // Reset to allow face detection again
        _statusMessage = '';
        _subStatusMessage = '';
      });
      showCustomToast(context, "Something went wrong. Please try again.", isError: true);
      // Restart face detection on error
      if (_isCameraInitialized && _cameraController != null) {
        _hasAutoStarted = false;
        _startFaceDetectionStream();
      }
    }
  }

  Future<void> _sendToApi(XFile imageFile) async {
    const apiUrl = ApiConstants.loginOrRegister;

    try {
      // Update status to show backend fetching
      setState(() {
        _statusMessage = 'Authenticating...';
        _subStatusMessage = 'Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account';
      });

      // Validate API URL
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

      debugPrint("📤 Preparing to send image to: $apiUrl");

      // Read image bytes
      Uint8List? bytes;
      try {
        bytes = await imageFile.readAsBytes();
        debugPrint("✅ Image read successfully: ${bytes.lengthInBytes} bytes (${(bytes.lengthInBytes / 1024).toStringAsFixed(2)} KB)");

        // Resize to web resolution (1280x720) to avoid "face too close" errors
        // while maintaining good quality for face recognition
        final originalSize = bytes.lengthInBytes;
        bytes = await _resizeImageToWebResolution(bytes);
        final newSize = bytes.lengthInBytes;

        if (newSize != originalSize) {
          debugPrint("✅ Image resized: ${(originalSize / 1024).toStringAsFixed(2)} KB → ${(newSize / 1024).toStringAsFixed(2)} KB");
        } else {
          debugPrint("✅ Image size is good: ${(originalSize / 1024).toStringAsFixed(2)} KB - maintaining quality");
        }
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Unable to process image. Please try again.", isError: true);
        debugPrint("❌ Cannot read image file: $e");
        return;
      }

      // Validate image size
      if (bytes.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Image file is empty. Please capture again.", isError: true);
        debugPrint("❌ Image file is empty");
        return;
      }

      if (bytes.lengthInBytes < 1024) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Image quality is too low. Please capture again.", isError: true);
        debugPrint("❌ Image too small: ${bytes.lengthInBytes} bytes");
        return;
      }

      // Use base64 encoding for both web and mobile (like web)
      String base64Image;
      try {
        base64Image = base64Encode(bytes);
        debugPrint("✅ Base64 encoding successful: ${base64Image.length} characters");
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Unable to process image. Please try again.", isError: true);
        debugPrint("❌ Base64 encoding failed: $e");
        return;
      }

      // Validate base64 string
      if (base64Image.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Image processing failed. Please try again.", isError: true);
        debugPrint("❌ Base64 string is empty");
        return;
      }

      // Create data URL
      final dataUrl = "data:image/jpeg;base64,$base64Image";
      debugPrint("✅ Data URL created (length: ${dataUrl.length})");

      // Create request body
      Map<String, dynamic> requestBody;
      String jsonBody;
      try {
        requestBody = {"face_image": dataUrl};
        jsonBody = jsonEncode(requestBody);
        debugPrint("✅ JSON body created (length: ${jsonBody.length})");
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Unable to prepare request. Please try again.", isError: true);
        debugPrint("❌ JSON encoding failed: $e");
        return;
      }

      // Send HTTP request
      http.Response response;
      try {
        debugPrint("📤 Sending POST request to: $apiUrl");
        debugPrint("📤 Content-Type: application/json");
        debugPrint("📤 Body size: ${jsonBody.length} characters");

        response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonBody,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException("Request timeout after 30 seconds");
          },
        );

        debugPrint("✅ Response received: Status ${response.statusCode}");
        debugPrint("📥 Response body length: ${response.body.length}");
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });

        if (e.toString().contains('TimeoutException')) {
          showCustomToast(context, "Request timeout. Check your internet connection.", isError: true);
        } else if (e.toString().contains('SocketException') || e.toString().contains('network')) {
          showCustomToast(context, "Network error. Check your internet connection.", isError: true);
        } else {
          showCustomToast(context, "Request failed. Please try again.", isError: true);
        }
        debugPrint(" HTTP request failed: $e");
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("API Response: $data");

        // Access tokens from the nested "data" object
        final responseData = data["data"];
        if (responseData != null && responseData["access_token"] != null && responseData["refresh_token"] != null) {
          try {
            await _storage.write(key: "access_token", value: responseData["access_token"]);
            await _storage.write(key: "refresh_token", value: responseData["refresh_token"]);
            // Verify tokens were saved
            final savedAccessToken = await _storage.read(key: "access_token");
            final savedRefreshToken = await _storage.read(key: "refresh_token");
            debugPrint("✅ Tokens saved: access_token=$savedAccessToken, refresh_token=$savedRefreshToken");
          } catch (e) {
            debugPrint("Error saving tokens: $e");
            setState(() {
              _isProcessing = false;
              _faceDetected = false; // Reset face detection
              _statusMessage = '';
              _subStatusMessage = '';
            });
            showCustomToast(context, "Login successful but failed to save session. Please try again.", isError: true);
            // Restart face detection
            if (_isCameraInitialized && _cameraController != null) {
              _hasAutoStarted = false;
              _startFaceDetectionStream();
            }
            return;
          }

          showCustomToast(context, "Face login successful!");

          await Future.delayed(const Duration(milliseconds: 500));

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        } else {
          setState(() {
            _isProcessing = false;
            _statusMessage = '';
            _subStatusMessage = '';
          });
          debugPrint("No tokens found in response: ${response.body}");
          showCustomToast(context, "No tokens received from server", isError: true);

          // Reset face detection for retry
          setState(() {
            _faceDetected = false;
          });
          // Auto-retry with limit
          _handleRetry();
        }
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });

        debugPrint("❌ API Error: Status ${response.statusCode}");
        debugPrint("❌ Response body: ${response.body}");

        // Parse and show error code
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
        } catch (parseError) {
          // If can't parse JSON, show generic message
          errorCode = "Face recognition failed. Please try again.";
          debugPrint("Could not parse error response: $parseError");
        }

        // Show error code
        showCustomToast(context, errorCode, isError: true);

        // Reset face detection for retry
        setState(() {
          _faceDetected = false;
        });
        // Auto-retry with limit
        _handleRetry();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _faceDetected = false; // Reset face detection
        _statusMessage = '';
        _subStatusMessage = '';
      });
      debugPrint("❌ Unexpected error in _sendToApi: $e");
      showCustomToast(context, "Something went wrong. Please try again.", isError: true);

      // Auto-retry with limit
      _handleRetry();
    }
  }

  // Handle retry logic with max attempts
  Future<void> _handleRetry() async {
    _retryCount++;
    debugPrint("🔄 Retry attempt $_retryCount/$_maxRetries");

    if (_retryCount < _maxRetries) {
      // Auto-retry - wait 2 seconds then retry
      await Future.delayed(const Duration(seconds: 2));
      if (mounted && !_isProcessing && !_showTryAgainButton) {
        debugPrint("🔄 Auto-retrying...");
        // Reset the auto-start flag to allow retry
        _hasAutoStarted = false;
        // Auto-start capture again
        if (_isCameraInitialized) {
          _hasAutoStarted = true;
          _captureAndSendSilently();
        }
      }
    } else {
      // Max retries reached - show try again button
      if (mounted) {
        setState(() {
          _showTryAgainButton = true;
          _statusMessage = 'Face recognition failed';
          _subStatusMessage = 'Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account';
        });
        debugPrint("❌ Max retries reached. Showing try again button.");
      }
    }
  }

  // Reset and restart the process
  void _restartProcess() {
    setState(() {
      _retryCount = 0;
      _showTryAgainButton = false;
      _hasAutoStarted = false;
      _isProcessing = false;
      _faceDetected = false; // Reset face detection
      _statusMessage = '';
      _subStatusMessage = '';
    });

    // Restart face detection stream instead of capturing immediately
    if (_isCameraInitialized && _cameraController != null) {
      _startFaceDetectionStream();
    }
  }
  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF0A0E21), // Ensure consistent background
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
              // Subtle background image overlay
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: Image.asset(
                    'assets/images/2.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Logo positioned above the glass card
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

              // Glass card with premium effects
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // 🔵 Pulsing animated face icon (same as before)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF415A77)
                                    .withOpacity(_isProcessing ? 0.8 : 0.5),
                                const Color(0xFF1B263B)
                                    .withOpacity(_isProcessing ? 0.7 : 0.5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF415A77)
                                    .withOpacity(_pulseAnimation.value * 0.9),
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

                    // 🔵 MAIN TITLE (big)
                    Text(
                      _isProcessing
                          ? (_statusMessage.isNotEmpty
                          ? _statusMessage
                          : 'Authenticating...')
                          : 'Face Recognition Active',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 🔵 SUB TEXT
                    Text(
                      _isProcessing
                          ? (_subStatusMessage.isNotEmpty
                          ? _subStatusMessage
                          : 'Processing your face...')
                          : _showTryAgainButton
                          ? "Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account"
                          : "Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.75),
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      "Your video never leaves your device except for secure matching",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),

                    ),

                    // 🔵 TRY AGAIN button (only when failed)
                    if (_showTryAgainButton && !_isProcessing) ...[
                      const SizedBox(height: 30),
                      InkWell(
                        onTap: _restartProcess,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 30, vertical: 14),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )


            ],
          ),
        ));
  }
}

