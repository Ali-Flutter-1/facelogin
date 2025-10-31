import 'dart:io';
import 'dart:typed_data';
import 'package:facelogin/components/kyc.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class KycScreen extends StatelessWidget {
  const KycScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<KycController>();
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'KYC Verification',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
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
        child: SafeArea(
          child: Obx(() => SingleChildScrollView(
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
                           _buildStepIndicator(3, "Review", controller.frontImageId.value.isNotEmpty && controller.backImageId.value.isNotEmpty),
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
                          style: TextStyle(color: Colors.white70, fontSize: 16),
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
                        child: ElevatedButton(
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: controller.isLoading.value 
                                ? Colors.blue.withValues(alpha: 0.6)
                                : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: controller.step.value == 3 && controller.isLoading.value
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      "Verifying...",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        controller.step.value == 3 ? "Verify" : "Continue",
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      controller.step.value == 3 ? Icons.check_circle : Icons.arrow_forward,
                                      size: 20,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )),
        ),
      ),
    );
  }

  double _calculateProgress({required bool frontUploaded, required bool backUploaded}) {
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
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
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
              color: Colors.blue.withOpacity(0.2),
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
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      
      const SizedBox(height: 24),
      
      // Upload status
      if (isUploading)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Uploading image...",
                style: TextStyle(
                  color: Colors.blue.shade300,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        )
      else if (isUploaded)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                "Image uploaded successfully",
                style: TextStyle(
                  color: Colors.green.shade300,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      
      const SizedBox(height: 24),
      
      // Image preview
      GestureDetector(
        onTap: onPickGallery,
        child: Container(
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
                      "Tap to select from gallery",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
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
      ),
      
      const SizedBox(height: 16),
      
      // Camera button
      ElevatedButton.icon(
        onPressed: onPickCamera,
        icon: const Icon(Icons.camera_alt, size: 20),
        label: const Text("Capture from Camera"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
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
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Make sure both images are clear before submitting",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      
      const SizedBox(height: 24),
      
      Row(
        children: [
          Expanded(
            child: _buildPreviewCard("Front", frontImage, frontId.isNotEmpty, isUploadingFront),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildPreviewCard("Back", backImage, backId.isNotEmpty, isUploadingBack),
          ),
        ],
      ),
      
      const SizedBox(height: 20),
      
      // Upload status summary
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (isUploadingFront || isUploadingBack)
              ? Colors.blue.withValues(alpha: 0.1)
              : (frontId.isNotEmpty && backId.isNotEmpty)
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isUploadingFront || isUploadingBack)
                ? Colors.blue.withValues(alpha: 0.3)
                : (frontId.isNotEmpty && backId.isNotEmpty)
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.orange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (isUploadingFront || isUploadingBack)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              )
            else
              Icon(
                (frontId.isNotEmpty && backId.isNotEmpty)
                    ? Icons.check_circle
                    : Icons.info_outline,
                color: (frontId.isNotEmpty && backId.isNotEmpty)
                    ? Colors.green
                    : Colors.orange,
                size: 24,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                (isUploadingFront || isUploadingBack)
                    ? "Uploading images... Please wait."
                    : (frontId.isNotEmpty && backId.isNotEmpty)
                        ? "Both images uploaded successfully. Ready to submit!"
                        : "Please wait for images to finish uploading.",
                style: TextStyle(
                  color: (isUploadingFront || isUploadingBack)
                      ? Colors.blue.shade300
                      : (frontId.isNotEmpty && backId.isNotEmpty)
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
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
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
                  height: 120,
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
                  height: 120,
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
                                  child: Text(
                                    "Error",
                                    style: TextStyle(
                                      color: Colors.red.shade300,
                                      fontSize: 12,
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
