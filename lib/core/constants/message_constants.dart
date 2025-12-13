class MessageConstants {
  // Camera messages
  static const String cameraNotInitialized = "Camera not initialized.";
  static const String unableToCaptureImage = "Unable to capture clear image.";
  static const String somethingWentWrong = "Something went wrong. Please try again.";

  // Face detection messages
  static const String faceRecognitionActive = 'Face Recognition Active';
  static const String capturingImage = 'Capturing Image...';
  static const String processingFace = 'Processing Face...';
  static const String authenticating = 'Authenticating...';
  static const String faceRecognitionFailed = 'Face recognition failed';

  // Status messages
  static const String centerFaceMessage =
      'Center your face and look at the camera for 5-6 s\nwe are hashing your vector and creating your account';
  static const String processingFaceMessage = 'Processing your face...';
  static const String privacyMessage =
      "Your video never leaves your device except for secure matching";

  // Success messages
  static const String faceLoginSuccess = "Face login successful!";
  static const String kycSubmittedSuccess = " KYC submitted successfully!";

  // Error messages
  static const String configurationError =
      "Configuration error. Please contact support.";
  static const String unableToProcessImage =
      "Unable to process image. Please try again.";
  static const String imageFileEmpty = "Image file is empty. Please capture again.";
  static const String imageQualityTooLow =
      "Image quality is too low. Please capture again.";
  static const String requestTimeout =
      "Request timeout. Check your internet connection.";
  static const String networkError =
      "Network error. Check your internet connection.";
  static const String requestFailed = "Request failed. Please try again.";
  static const String noTokensReceived = "No tokens received from server";
  static const String loginSuccessButSessionFailed =
      "Login successful but failed to save session. Please try again.";
  static const String faceRecognitionFailedGeneric =
      "Face recognition failed. Please try again.";

  // KYC messages
  static const String noAccessToken = "No access token found.";
  static const String waitForImagesUpload =
      "Please wait for images to finish uploading";
  static const String uploadBothImages = "Please upload both images first";
  static const String failedToUploadFrontImage = "Failed to upload front image";
  static const String failedToUploadBackImage = "Failed to upload back image";
  static const String failedToSelectImage =
      "Failed to select image. Please try again.";
  static const String kycSubmissionFailed = 'KYC submission failed.';
  static const String unableToAuthenticate =
      "Unable to authenticate. Please log in again.";
  static const String noAccessTokenFound =
      "No access token found. Please log in again.";

  // Button labels
  static const String tryAgain = "Try Again";
}

