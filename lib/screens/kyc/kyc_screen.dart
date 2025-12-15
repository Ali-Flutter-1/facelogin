import 'dart:io';
import 'dart:typed_data';
import 'package:facelogin/components/kyc.dart';
import 'package:facelogin/customWidgets/custom_loading.dart';
import 'package:facelogin/customWidgets/premium_loading.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({Key? key}) : super(key: key);

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  late KycController controller;

  @override
  void initState() {
    super.initState();
    // Get or create controller
    controller = Get.put(KycController());
    // Clear images when screen opens to ensure fresh start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.clearImages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21), // Ensure consistent background color
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(() => AppBar(
          title: const Text(
            'KYC Verification',
            style: TextStyle(
              fontFamily: 'OpenSans',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          // Hide back button when verifying
          automaticallyImplyLeading: !(controller.step.value == 3 && controller.isLoading.value),
        )),
      ),
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
        child: Obx(() => Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(), // Prevent white space when scrolling
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                      
                    // Progress indicator
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStepIndicator(1, "Front", controller.frontImageId.value.isNotEmpty),
                              _buildStepIndicator(2, "Back", controller.backImageId.value.isNotEmpty),
                              _buildStepIndicator(3, "Review", controller.step.value == 3),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _calculateProgress(
                              frontUploaded: controller.frontImageId.value.isNotEmpty,
                              backUploaded: controller.backImageId.value.isNotEmpty,
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                      
                    const SizedBox(height: 30),
                      
                    // Step content
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          if (controller.step.value == 1)
                            _uploadStep(
                              title: "Upload Front of ID",
                              description: "Take a clear photo of the front side of your ID card",
                              icon: Icons.badge,
                              imageFile: controller.frontImage.value,
                              onPickCamera: () => controller.pickImage(true, ImageSource.camera),
                              onPickGallery: () => controller.pickImage(true, ImageSource.gallery),
                              isUploaded: controller.frontImageId.value.isNotEmpty,
                              isUploading: controller.isUploadingFront.value,
                            ),
                          if (controller.step.value == 2)
                            _uploadStep(
                              title: "Upload Back of ID",
                              description: "Take a clear photo of the back side of your ID card",
                              icon: Icons.badge_outlined,
                              imageFile: controller.backImage.value,
                              onPickCamera: () => controller.pickImage(false, ImageSource.camera),
                              onPickGallery: () => controller.pickImage(false, ImageSource.gallery),
                              isUploaded: controller.backImageId.value.isNotEmpty,
                              isUploading: controller.isUploadingBack.value,
                            ),
                          if (controller.step.value == 3)
                            _reviewStep(
                              frontImage: controller.frontImage.value,
                              backImage: controller.backImage.value,
                              frontId: controller.frontImageId.value,
                              backId: controller.backImageId.value,
                              isUploadingFront: controller.isUploadingFront.value,
                              isUploadingBack: controller.isUploadingBack.value,
                            ),
                        ],
                      ),
                    ),
                      
                    const SizedBox(height: 30),
                      
                    // Navigation buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (controller.step.value > 1)
                          TextButton.icon(
                            onPressed: controller.prevStep,
                            icon: const Icon(Icons.arrow_back, color: Colors.white70),
                            label: const Text(
                              "Previous",
                              style: TextStyle(
                                fontFamily: 'OpenSans',
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          )
                        else
                          const SizedBox(width: 90),
                      
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: PremiumButton(
                              text: controller.step.value == 3 ? "Verify" : "Continue",
                              icon: controller.step.value == 3 ? Icons.check_circle : Icons.arrow_forward,
                              height: 50,
                              isLoading: controller.step.value == 3 && controller.isLoading.value ||
                                  controller.isUploadingFront.value ||
                                  controller.isUploadingBack.value,
                              loadingText: controller.step.value == 3 && controller.isLoading.value
                                  ? "Verifying..."
                                  : controller.isUploadingFront.value
                                  ? "Uploading "
                                  : controller.isUploadingBack.value
                                  ? "Uploading "
                                  : null,
                              onPressed: (controller.isLoading.value ||
                                  controller.isUploadingFront.value ||
                                  controller.isUploadingBack.value ||
                                  (controller.step.value == 1 && controller.frontImage.value == null) ||
                                  (controller.step.value == 2 && controller.backImage.value == null))
                                  ? null
                                  : () {
                                if (controller.step.value == 3) {
                                  controller.submitKyc(context: context);
                                } else {
                                  controller.nextStep();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Add bottom padding to prevent white space when scrolling
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            // Simple full page loading overlay when verifying
            if (controller.step.value == 3 && controller.isLoading.value)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7), // Fullscreen dark overlay
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DotCircleLoader(size: 40),
                      const SizedBox(height: 16),
                       Text(
                        'Verifying...',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          color: Colors.blue.shade600,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          ],
        )),
      ),
    );
  }

  double _calculateProgress({required bool frontUploaded, required bool backUploaded}) {
    // Progress based on actual image uploads, not just step navigation
    if (frontUploaded && backUploaded) return 1.0;
    if (frontUploaded) return 0.5;
    return 0.0;
  }

  Widget _buildStepIndicator(int step, String label, bool isCompleted) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? Colors.blue : Colors.white.withValues(alpha: 0.2),
            border: Border.all(
              color: isCompleted ? Colors.blue : Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
              '$step',
              style: TextStyle(
                fontFamily: 'OpenSans',
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'OpenSans',
            color: Colors.white.withOpacity(0.8),
            fontSize: 13,
            fontWeight: isCompleted ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: 0.2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

Widget _uploadStep({
  required String title,
  required String description,
  required IconData icon,
  required XFile? imageFile,
  required VoidCallback onPickCamera,
  required VoidCallback onPickGallery,
  required bool isUploaded,
  required bool isUploading,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      const SizedBox(height: 24),

      // Image preview
      GestureDetector(
        onTap: isUploading ? null : onPickGallery,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: imageFile != null ? Colors.blue : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: imageFile == null
                  ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isUploading ? "Uploading..." : "Tap to select from gallery",
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              )
                  : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: kIsWeb
                    ? FutureBuilder<Uint8List>(
                  future: imageFile?.readAsBytes(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      );
                    }
                    return Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.blue),
                      ),
                    );
                  },
                )
                    : Image.file(
                  File(imageFile!.path),
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            // Loading overlay when uploading
            if (isUploading)
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Uploading image...",
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),

      const SizedBox(height: 16),

      // Camera button
      PremiumButton(
        text: "Capture from Camera",
        icon: Icons.camera_alt,
        height: 50,
        isLoading: isUploading,
        loadingText: isUploading ? "Uploading..." : null,
        onPressed: isUploading ? null : onPickCamera,
      ),
    ],
  );
}

Widget _reviewStep({
  required XFile? frontImage,
  required XFile? backImage,
  required String frontId,
  required String backId,
  required bool isUploadingFront,
  required bool isUploadingBack,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.preview, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Review Your Uploads",
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Make sure both images are clear before submitting",
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      const SizedBox(height: 24),

      Column(
        children: [
          _buildPreviewCard("Front", frontImage, frontId.isNotEmpty, isUploadingFront),
          const SizedBox(height: 16),
          _buildPreviewCard("Back", backImage, backId.isNotEmpty, isUploadingBack),
        ],
      ),

    ],
  );
}

Widget _buildPreviewCard(String label, XFile? file, bool isUploaded, bool isUploading) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isUploaded ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2),
        width: 1.5,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'OpenSans',
                color: Colors.white.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                height: 1.4,
              ),
            ),
            if (isUploading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              )
            else if (isUploaded)
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: file == null
              ? Container(
            height: 200,
            color: Colors.white.withValues(alpha: 0.1),
            child: Center(
              child: Icon(
                Icons.image_not_supported,
                color: Colors.white.withValues(alpha: 0.3),
                size: 32,
              ),
            ),
          )
              : SizedBox(
            height: 200,
            child: kIsWeb
                ? FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    color: Colors.white.withValues(alpha: 0.1),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.blue),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Container(
                    color: Colors.white.withValues(alpha: 0.1),
                    child: Center(
                      child:                       Text(
                        "Error",
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          color: Colors.red.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  );
                } else if (snapshot.hasData) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  );
                }
                return Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  ),
                );
              },
            )
                : Image.file(
              File(file.path),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
      ],
    ),
  );
}
