import 'dart:async';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facelogin/core/constants/app_constants.dart';

/// Dialog shown on new device (Device B - e.g., Oppo) 
/// Displays QR code and OTP that needs to be scanned/entered on existing device (Device A - e.g., Vivo)
/// Polling is handled by the login screen via bootstrap API polling
class DevicePairingDialog extends StatefulWidget {
  final String otp;
  final String? pairingToken;
  final VoidCallback? onCancel;
  final VoidCallback? onApproved; // Called when pairing is approved (from parent polling)
  final Function(String newOtp, String? newPairingToken)? onRegenerate; // Called when QR code is regenerated

  const DevicePairingDialog({
    Key? key,
    required this.otp,
    this.pairingToken,
    this.onCancel,
    this.onApproved,
    this.onRegenerate,
  }) : super(key: key);

  @override
  State<DevicePairingDialog> createState() => _DevicePairingDialogState();
}

class _DevicePairingDialogState extends State<DevicePairingDialog> {
  bool _isPolling = true;
  bool _isApproved = false;
  Timer? _qrCodeTimer;
  String _currentOtp;
  String? _currentPairingToken;
  int _remainingSeconds = 300; // 5 minutes = 300 seconds

  _DevicePairingDialogState() : _currentOtp = '', _currentPairingToken = null;

  @override
  void initState() {
    super.initState();
    _currentOtp = widget.otp;
    _currentPairingToken = widget.pairingToken;
    
    // Start timer for QR code expiration (5 minutes)
    _startQrCodeTimer();
  }

  @override
  void dispose() {
    _qrCodeTimer?.cancel();
    super.dispose();
  }

  void _startQrCodeTimer() {
    _remainingSeconds = 300; // Reset to 5 minutes
    _qrCodeTimer?.cancel();
    
    _qrCodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _remainingSeconds--;
      });
      
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _regenerateQrCode();
      }
    });
  }

  Future<void> _regenerateQrCode() async {
    try {
      debugPrint('🔄 [PAIRING] Regenerating QR code after 5 minutes...');
      
      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(AppConstants.accessTokenKey);
      
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ [PAIRING] No access token found for QR regeneration');
        return;
      }
      
      // Request new pairing
      final e2eService = E2EService();
      final newPairingResult = await e2eService.requestDevicePairing(accessToken);
      
      if (newPairingResult.isSuccess && newPairingResult.otp != null) {
        setState(() {
          _currentOtp = newPairingResult.otp!;
          _currentPairingToken = newPairingResult.pairingToken;
        });
        
        // Restart timer
        _startQrCodeTimer();
        
        // Notify parent if callback provided
        if (widget.onRegenerate != null) {
          widget.onRegenerate!(_currentOtp, _currentPairingToken);
        }
        
        debugPrint('✅ [PAIRING] QR code regenerated successfully');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR code regenerated. Please scan the new code.'),
              backgroundColor: ColorConstants.gradientEnd4,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint('❌ [PAIRING] Failed to regenerate QR code: ${newPairingResult.error}');
      }
    } catch (e) {
      debugPrint('❌ [PAIRING] Error regenerating QR code: $e');
    }
  }

  /// Generate pairing URL that Device A can scan
  /// Format: https://idp.pollus.tech/pair?pairingToken=<token>
  String _generatePairingUrl(String pairingToken) {
    final baseUrl = ApiConstants.baseUrl.replaceAll('/api', '');
    return '$baseUrl/pair?pairingToken=$pairingToken';
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
                'E2E encryption is set up on another device.\nScan the QR code or enter the OTP on your existing device.',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 14,
                  color: ColorConstants.primaryTextColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // QR Code Section (if pairingToken is available)
              if (widget.pairingToken != null && widget.pairingToken!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ColorConstants.gradientEnd4.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Scan this QR code on your existing device:',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Generate URL with pairingToken
                      QrImageView(
                        data: _generatePairingUrl(_currentPairingToken ?? widget.pairingToken!),
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _remainingSeconds > 0
                            ? 'QR code valid for ${(_remainingSeconds ~/ 60)}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}'
                            : 'Regenerating QR code...',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                        Clipboard.setData(ClipboardData(text: _currentOtp));
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
                              _currentOtp,
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

