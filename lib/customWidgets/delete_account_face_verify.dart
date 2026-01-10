import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class DeleteAccountFaceVerifyDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const DeleteAccountFaceVerifyDialog({
    Key? key,
    required this.onSuccess,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<DeleteAccountFaceVerifyDialog> createState() =>
      _DeleteAccountFaceVerifyDialogState();
}

class _DeleteAccountFaceVerifyDialogState
    extends State<DeleteAccountFaceVerifyDialog>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _faceDetected = false;
  String _statusMessage = 'Position your face';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  FaceDetector? _faceDetector;
  bool _isDetecting = false;
  DateTime? _lastProcessedFrameTime;
  final Duration _frameThrottleDuration = const Duration(milliseconds: 200);
  DateTime? _faceDetectionStartTime;
  final Duration _faceDetectionTimeout = const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initializeFaceDetector();
    _initializeCamera();
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        _startFaceDetectionStream();
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Camera error';
        });
        await Future.delayed(const Duration(seconds: 2));
        widget.onCancel();
      }
    }
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
        debugPrint("⚠️ Face detection timeout");
        if (mounted) {
          setState(() {
            _statusMessage = 'Timeout. Please try again.';
          });
        }
        return;
      }

      if (_isDetecting || _isProcessing) return;
      _isDetecting = true;
      _lastProcessedFrameTime = now;

      try {
        final inputImage = _convertCameraImage(cameraImage);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }

        final faces = await _faceDetector!.processImage(inputImage);

        if (mounted && !_isProcessing) {
          if (faces.isNotEmpty) {
            final face = faces.first;
            final isValid = _isFaceValid(face, cameraImage.width, cameraImage.height);

            if (isValid) {
              setState(() {
                _faceDetected = true;
                _statusMessage = 'Face detected';
              });

              // Capture image from stream (silent, no shutter sound)
              await _captureFromStream(cameraImage);
            } else {
              final guidance = _getFaceQualityGuidance(face, cameraImage.width, cameraImage.height);
              setState(() {
                _faceDetected = false;
                _statusMessage = guidance ?? 'Position your face';
              });
            }
          } else {
            setState(() {
              _faceDetected = false;
              _statusMessage = 'No face detected';
            });
          }
        }
      } catch (e) {
        debugPrint('Face detection error: $e');
      }

      _isDetecting = false;
    });
  }

  bool _isFaceValid(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;
    final faceArea = faceWidth * faceHeight;
    final imageArea = imageWidth * imageHeight;
    final faceSizePercentage = (faceArea / imageArea) * 100;

    if (faceSizePercentage < 15 || faceSizePercentage > 60) {
      return false;
    }

    final aspectRatio = faceWidth / faceHeight;
    if (aspectRatio < 0.6 || aspectRatio > 1.4) {
      return false;
    }

    final centerX = boundingBox.left + (faceWidth / 2);
    final centerY = boundingBox.top + (faceHeight / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.4 || offsetY > 0.4) {
      return false;
    }

    return true;
  }

  String? _getFaceQualityGuidance(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;
    final faceArea = boundingBox.width * boundingBox.height;
    final imageArea = imageWidth * imageHeight;
    final faceSizePercentage = (faceArea / imageArea) * 100;

    if (faceSizePercentage < 15) return "Move closer";
    if (faceSizePercentage > 60) return "Move back";

    final aspectRatio = boundingBox.width / boundingBox.height;
    if (aspectRatio < 0.6 || aspectRatio > 1.4) return "Face camera directly";

    final centerX = boundingBox.left + (boundingBox.width / 2);
    final centerY = boundingBox.top + (boundingBox.height / 2);
    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.4 || offsetY > 0.4) {
      return offsetX > offsetY ? "Center horizontally" : "Center vertically";
    }

    return null;
  }

  Future<void> _captureFromStream(CameraImage cameraImage) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Verifying...';
    });

    try {
      // Stop stream before processing
      await _cameraController!.stopImageStream();

      Uint8List imageBytes;
      
      if (Platform.isAndroid) {
        // Android: Use takePicture() for reliable JPEG capture (same as login screen)
        // This is more reliable than converting NV21 stream format
        try {
          debugPrint('📸 Android: Taking picture...');
          final XFile capturedFile = await _cameraController!.takePicture();
          imageBytes = await capturedFile.readAsBytes();
          debugPrint('✅ Android: Captured image via takePicture: ${imageBytes.lengthInBytes} bytes');
        } catch (e) {
          debugPrint('❌ Android takePicture failed: $e');
          // Re-throw to show error to user
          throw Exception('Failed to capture image: $e');
        }
      } else {
        // iOS: Convert BGRA8888 to JPEG from stream
        debugPrint('📸 iOS: Converting stream to JPEG...');
        imageBytes = await _bgrToJpegFromStream(cameraImage);
        debugPrint('✅ iOS: Converted image: ${imageBytes.lengthInBytes} bytes');
      }

      // Validate image quality
      if (imageBytes.isEmpty || imageBytes.lengthInBytes < 20 * 1024) {
        debugPrint('⚠️ Image quality too low: ${imageBytes.lengthInBytes} bytes (minimum: ${20 * 1024})');
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Image quality too low. Retrying...';
        });
        _startFaceDetectionStream();
        return;
      }
      
      debugPrint('✅ Image captured successfully: ${imageBytes.lengthInBytes} bytes');

      final base64Image = base64Encode(imageBytes);
      final dataUrl = "data:image/jpeg;base64,$base64Image";

      setState(() {
        _statusMessage = 'Verifying identity...';
      });

      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null || token.isEmpty) {
        if (mounted) {
          showCustomToast(context, 'No access token found. Please login again.', isError: true);
        }
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Authentication error';
        });
        await Future.delayed(const Duration(seconds: 2));
        widget.onCancel();
        return;
      }

      // Call verify-face API
      final response = await http.post(
        Uri.parse(ApiConstants.verifyFace),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "face_image": dataUrl,
          "action": "delete",
        }),
      ).timeout(const Duration(seconds: 30));

      debugPrint('Verify face response: ${response.statusCode}');
      debugPrint('Verify face response body: ${response.body}');

      // Handle 401/403 authentication errors
      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('⚠️ Authentication error (${response.statusCode}) - token may be expired');
        
        // Try to parse error message
        String errorMessage = 'Session expired. Please login again.';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['message'] ?? 
                        errorData['error']?['message'] ?? 
                        errorData['error']?.toString() ??
                        'Session expired. Please login again.';
        } catch (e) {
          debugPrint('Could not parse error response: $e');
        }
        
        if (mounted) {
          showCustomToast(context, errorMessage, isError: true);
        }
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Authentication error';
        });
        await Future.delayed(const Duration(seconds: 2));
        widget.onCancel();
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final trackingId = data['data']?['tracking_id'] ?? data['tracking_id'];

        if (trackingId != null) {
          await _deleteAccount(trackingId.toString());
        } else {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Verification failed. Retrying...';
          });
          await Future.delayed(const Duration(seconds: 1));
          _startFaceDetectionStream();
        }
      } else {
        // Handle other errors (400, 500, etc.)
        String errorMessage = 'Face verification failed';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['message'] ?? 
                        errorData['error']?['message'] ?? 
                        errorData['error']?.toString() ??
                        'Face verification failed';
        } catch (e) {
          debugPrint('Could not parse error response: $e');
          errorMessage = 'Face verification failed (${response.statusCode})';
        }
        
        debugPrint('⚠️ Verify face error: $errorMessage');
        
        if (mounted) {
          showCustomToast(context, errorMessage, isError: true);
        }
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Verification failed. Retrying...';
        });
        await Future.delayed(const Duration(seconds: 1));
        _startFaceDetectionStream();
      }
    } catch (e) {
      debugPrint('Capture/verify error: $e');
      if (mounted) {
        showCustomToast(context, 'Verification failed. Please try again.', isError: true);
      }
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error. Retrying...';
      });
      await Future.delayed(const Duration(seconds: 1));
      _startFaceDetectionStream();
    }
  }

  Future<Uint8List> _nv21ToJpeg(CameraImage image) async {
    // NV21 format: Y plane (luminance) + interleaved VU plane
    // Plane 0: Y data
    // Plane 1: Interleaved VU data (V and U values are interleaved: V, U, V, U, ...)
    final yPlane = image.planes[0];
    final uvPlane = image.planes.length > 1 ? image.planes[1] : null;
    
    if (uvPlane == null) {
      throw Exception('NV21 format requires at least 2 planes');
    }

    final yBuffer = yPlane.bytes;
    final uvBuffer = uvPlane.bytes;

    final yuvImage = img.Image(
      width: image.width,
      height: image.height,
    );

    // NV21: UV data is interleaved as V, U, V, U, ...
    // For each 2x2 block, we have one U and one V value
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvRow = y ~/ 2;
        final uvCol = x ~/ 2;
        final uvIndex = uvRow * uvPlane.bytesPerRow + (uvCol * 2);

        if (yIndex >= yBuffer.length || uvIndex + 1 >= uvBuffer.length) {
          continue; // Skip out of bounds pixels
        }

        final yValue = yBuffer[yIndex];
        // NV21: V comes first, then U (interleaved)
        final vValue = uvBuffer[uvIndex] - 128;
        final uValue = uvBuffer[uvIndex + 1] - 128;

        // Convert YUV to RGB
        int r = (yValue + (1.402 * vValue)).round().clamp(0, 255);
        int g = (yValue - (0.344 * uValue) - (0.714 * vValue)).round().clamp(0, 255);
        int b = (yValue + (1.772 * uValue)).round().clamp(0, 255);

        yuvImage.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    final jpg = img.encodeJpg(yuvImage, quality: 95);
    return Uint8List.fromList(jpg);
  }

  Future<Uint8List> _bgrToJpegFromStream(CameraImage image) async {
    if (image.format.group != ImageFormatGroup.bgra8888) {
      throw Exception("Expected BGRA8888 on iOS, got ${image.format.group}");
    }

    final plane = image.planes.first;
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

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );
      if (rotation == null) return null;

      // For Android NV21, we need to combine all planes
      // For iOS BGRA8888, we can use the first plane
      final allBytes = <int>[];
      for (final plane in image.planes) {
        allBytes.addAll(plane.bytes);
      }
      final bytes = Uint8List.fromList(allBytes);

      // Determine format based on actual image format (more reliable than platform check)
      final inputFormat = (image.format.group == ImageFormatGroup.bgra8888)
          ? InputImageFormat.bgra8888  // iOS uses BGRA format
          : InputImageFormat.yuv_420_888;  // Android uses YUV format

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: inputFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  Future<void> _deleteAccount(String trackingId) async {
    try {
      setState(() {
        _statusMessage = 'Deleting account...';
      });

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      // Use DELETE method with tracking_id as query parameter
      final deleteUrl = Uri.parse('${ApiConstants.deleteAccount}?tracking_id=$trackingId');
      final response = await http.delete(
        deleteUrl,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
      ).timeout(const Duration(seconds: 30));

      debugPrint('Delete account response: ${response.statusCode}');
      debugPrint('Delete account response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _statusMessage = 'Account deleted';
        });

        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          widget.onSuccess();
        }
      } else {
        String errorMessage = 'Failed to delete account';
        
        // Try to parse JSON error, but handle HTML responses
        try {
          if (response.body.trim().startsWith('{') || response.body.trim().startsWith('[')) {
            final errorData = jsonDecode(response.body);
            errorMessage = errorData['message'] ?? 
                          errorData['error']?['message'] ?? 
                          errorData['error']?.toString() ??
                          'Failed to delete account';
          } else {
            // HTML response or other format
            errorMessage = 'Server error (${response.statusCode}). Please try again.';
          }
        } catch (e) {
          // Not JSON, use status code message
          if (response.statusCode == 405) {
            errorMessage = 'Method not allowed. Please contact support.';
          } else if (response.statusCode == 404) {
            errorMessage = 'Endpoint not found. Please contact support.';
          } else {
            errorMessage = 'Server error (${response.statusCode}). Please try again.';
          }
        }
        
        if (mounted) {
          showCustomToast(context, errorMessage, isError: true);
        }
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Deletion failed';
        });
      }
    } catch (e) {
      debugPrint('Delete account error: $e');
      if (mounted) {
        showCustomToast(context, 'Failed to delete account. Please try again.', isError: true);
      }
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error. Retrying...';
      });
      await Future.delayed(const Duration(seconds: 1));
      _startFaceDetectionStream();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1B263B),
              Color(0xFF0D1B2A),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated face icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.red.withOpacity(_pulseAnimation.value),
                            Colors.red.withOpacity(_pulseAnimation.value * 0.3),
                            Colors.transparent,
                          ],
                          stops: const [0.3, 0.6, 1.0],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1B263B),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/images/pngwing.com.png',
                              width: 50,
                              height: 50,
                              color: Colors.red,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.face,
                                  color: Colors.red,
                                  size: 50,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 24),
              
              // Status message
              Text(
                _statusMessage,
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _faceDetected ? Colors.green : Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // Loading indicator
              if (_isProcessing)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                )
              else
                Text(
                  'Face verification required',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // Cancel button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isProcessing ? null : widget.onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _isProcessing
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
