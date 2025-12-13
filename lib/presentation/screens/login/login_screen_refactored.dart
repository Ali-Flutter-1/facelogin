import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/core/constants/message_constants.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/presentation/controllers/login_controller.dart';
import 'package:facelogin/screens/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LoginController());

    // Setup callbacks
    controller.onSuccess = () {
      showCustomToast(context, MessageConstants.faceLoginSuccess);
      Future.delayed(AppConstants.statusMessageDelay, () {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        }
      });
    };

    controller.onError = (String error) {
      showCustomToast(context, error, isError: true);
    };

    return Scaffold(
      backgroundColor: ColorConstants.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ColorConstants.gradientStart,
              ColorConstants.gradientEnd1,
              ColorConstants.gradientEnd2,
              ColorConstants.gradientEnd3,
              ColorConstants.gradientEnd4,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Background image overlay
            Positioned.fill(
              child: Opacity(
                opacity: ColorConstants.backgroundImageOpacity,
                child: Image.asset(
                  AppConstants.backgroundImagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            // Logo
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: AppConstants.logoAnimationDuration,
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    final clampedValue = value.clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: clampedValue,
                      child: Opacity(
                        opacity: clampedValue,
                        child: Image.asset(
                          AppConstants.logoPath,
                          width: AppConstants.logoWidth,
                          height: AppConstants.logoHeight,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Face icon with pulse animation
                  Obx(() => _buildPulsingFaceIcon(controller)),

                  const SizedBox(height: 35),

                  // Status messages
                  Obx(() => _buildStatusMessages(controller)),

                  const SizedBox(height: 20),

                  // Privacy message
                  _buildPrivacyMessage(),

                  // Try again button
                  Obx(() => _buildTryAgainButton(controller, context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulsingFaceIcon(LoginController controller) {
    return AnimatedBuilder(
      animation: controller.cameraController.pulseAnimation,
      builder: (context, child) {
        final isProcessing = controller.cameraController.isProcessing.value;
        final pulseValue = controller.cameraController.pulseAnimation.value;

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                ColorConstants.gradientEnd4.withOpacity(
                  isProcessing ? ColorConstants.shadowOpacityHigh : ColorConstants.shadowOpacityLow,
                ),
                ColorConstants.gradientEnd3.withOpacity(
                  isProcessing ? ColorConstants.shadowOpacityMedium : ColorConstants.shadowOpacityLow,
                ),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: ColorConstants.shadowColor.withOpacity(
                  pulseValue * ColorConstants.shadowOpacity,
                ),
                blurRadius: 40 * pulseValue,
                spreadRadius: 12 * pulseValue,
              ),
            ],
          ),
          padding: const EdgeInsets.all(30),
          child: Image.asset(
            AppConstants.faceIconPath,
            width: AppConstants.faceIconWidth,
            color: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildStatusMessages(LoginController controller) {
    final isProcessing = controller.cameraController.isProcessing.value;
    final statusMessage = controller.cameraController.statusMessage.value;
    final subStatusMessage = controller.cameraController.subStatusMessage.value;
    final showTryAgain = controller.cameraController.showTryAgainButton.value;

    return Column(
      children: [
        Text(
          isProcessing
              ? (statusMessage.isNotEmpty
                  ? statusMessage
                  : MessageConstants.authenticating)
              : MessageConstants.faceRecognitionActive,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ColorConstants.primaryTextColor,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isProcessing
              ? (subStatusMessage.isNotEmpty
                  ? subStatusMessage
                  : MessageConstants.processingFaceMessage)
              : MessageConstants.centerFaceMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: ColorConstants.primaryTextColor.withOpacity(
              ColorConstants.primaryTextOpacity,
            ),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyMessage() {
    return Text(
      MessageConstants.privacyMessage,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: ColorConstants.primaryTextColor.withOpacity(
          ColorConstants.secondaryTextOpacity,
        ),
      ),
    );
  }

  Widget _buildTryAgainButton(
    LoginController controller,
    BuildContext context,
  ) {
    final showTryAgain = controller.cameraController.showTryAgainButton.value;
    final isProcessing = controller.cameraController.isProcessing.value;

    if (!showTryAgain || isProcessing) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 30),
        InkWell(
          onTap: controller.restartLogin,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  ColorConstants.gradientEnd4,
                  ColorConstants.gradientEnd3,
                  ColorConstants.gradientEnd2,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              MessageConstants.tryAgain,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ColorConstants.primaryTextColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

