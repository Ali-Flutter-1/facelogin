import 'dart:typed_data';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/message_constants.dart';
import 'package:facelogin/data/repositories/auth_repository.dart';
import 'package:facelogin/presentation/controllers/camera_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';


class LoginController extends GetxController {
  final AuthRepository _authRepository;
  final FaceLoginCameraController _cameraController;

  LoginController({
    AuthRepository? authRepository,
    FaceLoginCameraController? cameraController,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _cameraController = cameraController ?? FaceLoginCameraController() {
    _setupCameraCallbacks();
  }

  void _setupCameraCallbacks() {
    _cameraController.onFaceDetected = _handleFaceDetected;
    _cameraController.onRetryNeeded = _handleRetryNeeded;
  }

  void _handleFaceDetected() {
    _captureAndLogin();
  }

  void _handleRetryNeeded() {
    if (_cameraController.retryCount.value < AppConstants.maxRetries) {
      Future.delayed(AppConstants.retryDelay, () {
        if (!_cameraController.isProcessing.value &&
            !_cameraController.showTryAgainButton.value) {
          _cameraController.hasAutoStarted.value = true;
          _captureAndLogin();
        }
      });
    }
  }

  Future<void> _captureAndLogin() async {
    _cameraController.isProcessing.value = true;
    _cameraController.statusMessage.value = MessageConstants.capturingImage;
    _cameraController.subStatusMessage.value = MessageConstants.centerFaceMessage;

    try {
      final capturedImage = await _cameraController.captureImage();

      if (capturedImage != null) {
        _cameraController.statusMessage.value = MessageConstants.processingFace;
        _cameraController.subStatusMessage.value = MessageConstants.centerFaceMessage;
        await Future.delayed(AppConstants.statusMessageDelay);

        final imageBytes = await capturedImage.readAsBytes();
        await _loginWithImage(imageBytes);
      } else {
        _cameraController.isProcessing.value = false;
        _cameraController.isFaceDetected.value = false;
        _cameraController.statusMessage.value = '';
        _cameraController.subStatusMessage.value = '';
        onError?.call(MessageConstants.unableToCaptureImage);
        _cameraController.handleRetry();
      }
    } catch (e) {
      debugPrint("❌ Error capturing: $e");
      _cameraController.isProcessing.value = false;
      _cameraController.isFaceDetected.value = false;
      _cameraController.statusMessage.value = '';
      _cameraController.subStatusMessage.value = '';
      onError?.call(MessageConstants.somethingWentWrong);
      _cameraController.handleRetry();
    }
  }

  Future<void> _loginWithImage(Uint8List imageBytes) async {
    _cameraController.statusMessage.value = MessageConstants.authenticating;
    _cameraController.subStatusMessage.value = MessageConstants.centerFaceMessage;

    final result = await _authRepository.loginOrRegister(imageBytes);

    _cameraController.isProcessing.value = false;

    if (result.isSuccess) {
      onSuccess?.call();
    } else {
      _cameraController.isFaceDetected.value = false;
      _cameraController.statusMessage.value = '';
      _cameraController.subStatusMessage.value = '';
      onError?.call(result.error ?? MessageConstants.faceRecognitionFailedGeneric);
      _cameraController.handleRetry();
    }
  }

  void restartLogin() {
    _cameraController.restartProcess();
  }

  // Callbacks
  VoidCallback? onSuccess;
  Function(String)? onError;

  FaceLoginCameraController get cameraController => _cameraController;

  @override
  void onClose() {
    _cameraController.onClose();
    super.onClose();
  }
}

