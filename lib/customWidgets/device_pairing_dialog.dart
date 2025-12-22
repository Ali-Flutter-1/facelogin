import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog shown on new device (Device B - e.g., Oppo) 
/// Displays OTP that needs to be entered on existing device (Device A - e.g., Vivo)
/// Polling is handled by the login screen via bootstrap API polling
class DevicePairingDialog extends StatefulWidget {
  final String otp;
  final VoidCallback? onCancel;
  final VoidCallback? onApproved; // Called when pairing is approved (from parent polling)

  const DevicePairingDialog({
    Key? key,
    required this.otp,
    this.onCancel,
    this.onApproved,
  }) : super(key: key);

  @override
  State<DevicePairingDialog> createState() => _DevicePairingDialogState();
}

class _DevicePairingDialogState extends State<DevicePairingDialog> {
  bool _isPolling = true;
  bool _isApproved = false;

  @override
  void initState() {
    super.initState();
    // Polling is handled by parent (login screen) via bootstrap API
    // This dialog just displays the OTP and waits for onApproved callback
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onCancel?.call();
        return true;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ColorConstants.gradientEnd3,
                ColorConstants.gradientEnd2,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ColorConstants.gradientEnd4.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ColorConstants.gradientEnd4.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.devices,
                  size: 48,
                  color: ColorConstants.primaryTextColor,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Device Pairing Required',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: ColorConstants.primaryTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                'E2E encryption is set up on another device.\nPlease approve this login from your existing device.',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 14,
                  color: ColorConstants.primaryTextColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // OTP Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ColorConstants.gradientEnd4.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Enter this OTP on your existing device:',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 14,
                        color: ColorConstants.primaryTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // OTP Display
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.otp));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('OTP copied to clipboard!'),
                            backgroundColor: ColorConstants.gradientEnd4,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: ColorConstants.gradientEnd4.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ColorConstants.gradientEnd4,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.otp,
                              style: const TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                                color: ColorConstants.primaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.copy,
                              color: ColorConstants.primaryTextColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap to copy',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 12,
                        color: ColorConstants.primaryTextColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Status
              if (_isPolling && !_isApproved)
                Column(
                  children: [
                    const CircularProgressIndicator(
                      color: ColorConstants.gradientEnd4,
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Waiting for approval...',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 14,
                        color: ColorConstants.primaryTextColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),

              if (_isApproved)
                Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Device paired successfully!',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),

              // Cancel Button
              CustomButton(
                text: 'Cancel',
                onPressed: () {
                  widget.onCancel?.call();
                  Navigator.pop(context);
                },
                backgroundColor: ColorConstants.gradientEnd4.withOpacity(0.3),
                textColor: ColorConstants.primaryTextColor,
                height: 48,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

