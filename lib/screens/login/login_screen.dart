import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:facelogin/constant/constant.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/screens/profile/profile_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;


class GlassMorphismLoginScreen extends StatefulWidget {
  const GlassMorphismLoginScreen({Key? key}) : super(key: key);

  @override
  State<GlassMorphismLoginScreen> createState() =>
      _GlassMorphismLoginScreenState();
}

class _GlassMorphismLoginScreenState extends State<GlassMorphismLoginScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  final _storage = const FlutterSecureStorage();
  String _statusMessage = '';
  String _subStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeCameraSilently();
  }
  Future<void> _initializeCameraSilently() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      // Use higher quality
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      // await _cameraController?.setFocusMode(FocusMode.auto);
      // Give the camera a short delay to stabilize exposure
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

  } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
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
      _subStatusMessage = 'Hold your face towards Camera.';
    });

    try {
      XFile? capturedImage;
      for (int attempt = 1; attempt <= 3; attempt++) {
        debugPrint("📸 Capture attempt $attempt");
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();

        // If image size > 50KB (reasonable quality), break early
        if (bytes.lengthInBytes > 50 * 1024) {
          capturedImage = image;
          break;
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (capturedImage != null) {
        // Update status before processing
        setState(() {
          _statusMessage = 'Processing Face...';
          _subStatusMessage = 'We are hashing your vector...';
        });
        await Future.delayed(const Duration(milliseconds: 500)); // Show the hashing message
        
        await _sendToApi(capturedImage);
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        showCustomToast(context, "Unable to capture clear image.", isError: true);
      }
    } catch (e) {
      debugPrint("Error capturing: $e");
      setState(() {
        _isProcessing = false;
        _statusMessage = '';
        _subStatusMessage = '';
      });
      showCustomToast(context, "Error: $e", isError: true);
    }
  }

  Future<void> _sendToApi(XFile imageFile) async {
    const apiUrl = ApiConstants.loginOrRegister;

    try {
      // Update status to show backend fetching
      setState(() {
        _statusMessage = 'Authenticating...';
        _subStatusMessage = 'Fetching data from backend...';
      });

      http.Response response;

      if (kIsWeb) {
        // 🌐 For web → use base64 data URL (works on web)
        final bytes = await imageFile.readAsBytes();
        final base64Image = base64Encode(bytes);
        final dataUrl = "data:image/jpeg;base64,$base64Image";

        final body = jsonEncode({"face_image": dataUrl});

        response = await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: body,
        );
      } else {
        // 📱 For Android/iOS → use multipart/form-data
        var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
        
        // Read image bytes and create multipart file
        final bytes = await imageFile.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'face_image',
          bytes,
          filename: imageFile.name.isNotEmpty ? imageFile.name : 'face_image.jpg',
        ));

        debugPrint("📤 Sending face image (multipart)");
        var streamed = await request.send();
        var responseBody = await streamed.stream.bytesToString();
        response = http.Response(responseBody, streamed.statusCode);
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
              _statusMessage = '';
              _subStatusMessage = '';
            });
            showCustomToast(context, "Failed to save tokens: $e", isError: true);
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
        }
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
          _subStatusMessage = '';
        });
        debugPrint("Failed: ${response.statusCode} - ${response.body}");
        showCustomToast(context, "Face recognition failed: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '';
        _subStatusMessage = '';
      });
      debugPrint("Error sending API request: $e");
      showCustomToast(context, "Network error: $e", isError: true);
    }
  }
  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/2.jpeg'),
                fit: BoxFit.cover,
                opacity: 0.7,
              ),
            ),
          ),

          // Glass card
          Center(
            child: GestureDetector(
              onTap: _isProcessing ? null : _captureAndSendSilently,
              child: Container(
                width: 280,
                height: 350,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2), width: 1),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0A0E21),
                      Color(0xFF0D1B2A),
                      Color(0xFF1B263B),
                      Color(0xFF415A77),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/logo.png'),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withValues(alpha: 0.6),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Image.asset(
                        'assets/images/pngwing.com.png',
                        width: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isProcessing
                          ? (_statusMessage.isNotEmpty ? _statusMessage : 'Authenticating...')
                          : 'Tap to Unlock with Face ID',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isProcessing
                          ? (_subStatusMessage.isNotEmpty ? _subStatusMessage : 'Processing...')
                          : 'or use your device password',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
