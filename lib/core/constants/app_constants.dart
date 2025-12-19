class AppConstants {
  // Image paths
  static const String logoPath = 'assets/images/valydlogo.png';

  static const String backgroundImagePath = 'assets/images/2.jpeg';
  static const String faceIconPath = 'assets/images/pngwing.com.png';

  // Camera settings
  static const double minFaceSize = 0.15;
  static const int maxRetries = 3;
  static const int imageQuality = 80;
  static const int targetImageWidth = 1280;
  static const int targetImageHeight = 720;
  static const int jpegQuality = 95;
  static const int minImageSizeBytes = 100 * 1024; // 100KB

  // Timeouts and delays
  static const Duration cameraStabilizationDelay = Duration(milliseconds: 1000);
  static const Duration captureDelay = Duration(milliseconds: 800);
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration statusMessageDelay = Duration(milliseconds: 500);

  // Storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  // Face detection settings
  static const double faceDetectionMinSize = 0.15;
  static const bool enableContours = false;
  static const bool enableLandmarks = false;

  // UI Constants
  static const double logoWidth = 120.0;
  static const double logoHeight = 120.0;
  static const double faceIconWidth = 75.0;
  static const double pulseAnimationMin = 0.5;
  static const double pulseAnimationMax = 1.0;
  static const Duration pulseAnimationDuration = Duration(milliseconds: 1500);
  static const Duration logoAnimationDuration = Duration(milliseconds: 800);
}

