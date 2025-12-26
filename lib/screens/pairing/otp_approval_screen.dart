import 'dart:convert';
import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/data/services/pairing_service.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screen shown on existing device (Device A - e.g., Vivo)
/// User enters OTP to approve pairing request from new device (Device B - e.g., Oppo)
class OtpApprovalScreen extends StatefulWidget {
  const OtpApprovalScreen({Key? key}) : super(key: key);

  @override
  State<OtpApprovalScreen> createState() => _OtpApprovalScreenState();
}

class _OtpApprovalScreenState extends State<OtpApprovalScreen> {
  final PairingService _pairingService = PairingService();
  final E2EService _e2eService = E2EService();
  final TextEditingController _otpController = TextEditingController();
  bool _isProcessing = false;
  String? _pairingToken;
  String? _newDevicePublicKey;
  String? _newDeviceId;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _lookupPairing() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      showCustomToast(context, 'Please enter the OTP', isError: true);
      return;
    }

    if (otp.length != 6) {
      showCustomToast(context, 'OTP must be 6 digits', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await _pairingService.lookupByOtp(otp);

      if (result.isSuccess && result.pairingToken != null) {
        setState(() {
          _pairingToken = result.pairingToken;
          _newDevicePublicKey = result.publicKey;
          _newDeviceId = result.deviceId;
          _isProcessing = false;
        });

        // Proceed to approval
        await _approvePairing();
      } else {
        setState(() {
          _isProcessing = false;
        });
        showCustomToast(
          context,
          result.error ?? 'Invalid OTP. Please check and try again.',
          isError: true,
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      showCustomToast(
        context,
        'Failed to lookup pairing: ${e.toString()}',
        isError: true,
      );
    }
  }

  Future<void> _approvePairing() async {
    if (_pairingToken == null || _newDevicePublicKey == null) {
      showCustomToast(context, 'Missing pairing information', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Get current session Ku
      final ku = await _e2eService.getSessionKu();
      if (ku == null) {
        // Need to recover Ku first
        showCustomToast(
          context,
          'Please login first to approve pairing',
          isError: true,
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Encrypt Ku with new device's public key
      // The public key is already base64 encoded, decode it
      final publicKeyBytes = base64Decode(_newDevicePublicKey!);
      
      // Encrypt Ku with the new device's public key
      // Returns base64 encoded JSON with ephemeral format: {epk, iv, ct}
      final wrappedKuBase64 = await _e2eService.encryptKuWithPublicKey(
        ku,
        publicKeyBytes,
      );

      // Approve the pairing
      final success = await _pairingService.approvePairing(
        pairingToken: _pairingToken!,
        wrappedKu: wrappedKuBase64,
      );

      setState(() {
        _isProcessing = false;
      });

      if (success) {
        showCustomToast(context, 'Device pairing approved successfully!');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        showCustomToast(context, 'Failed to approve pairing', isError: true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      showCustomToast(
        context,
        'Failed to approve pairing: ${e.toString()}',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // App Bar
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: ColorConstants.primaryTextColor,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Approve Device Pairing',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: ColorConstants.primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ColorConstants.gradientEnd4.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 64,
                    color: ColorConstants.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'Approve New Device',
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
                  'A new device is requesting access to your account.\nEnter the OTP shown on the new device to approve.',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 14,
                    color: ColorConstants.primaryTextColor.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // OTP Input
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ColorConstants.gradientEnd4.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter OTP',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ColorConstants.primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: ColorConstants.primaryTextColor,
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          hintStyle: TextStyle(
                            color: ColorConstants.primaryTextColor.withValues(alpha: 0.3),
                            letterSpacing: 8,
                          ),
                          filled: true,
                          fillColor: ColorConstants.gradientEnd4.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: ColorConstants.gradientEnd4.withValues(alpha: 0.5),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: ColorConstants.gradientEnd4.withValues(alpha: 0.5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: ColorConstants.gradientEnd4,
                              width: 2,
                            ),
                          ),
                          counterText: '',
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onSubmitted: (_) => _lookupPairing(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Approve Button
                CustomButton(
                  text: _isProcessing ? 'Processing...' : 'Approve',
                  onPressed: _isProcessing ? () {} : () => _lookupPairing(),
                  backgroundColor: ColorConstants.gradientEnd4,
                  textColor: Colors.white,
                  height: 56,
                  borderRadius: BorderRadius.circular(16),
                ),

                const Spacer(),

                // Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: ColorConstants.primaryTextColor.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This will allow the new device to access your encrypted data.',
                          style: TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 12,
                            color: ColorConstants.primaryTextColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

