import 'dart:async';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Result class for QR code regeneration
class PairingRegenerateResult {
  final bool isSuccess;
  final String? pairingToken;
  final String? otp;
  final String? error;

  PairingRegenerateResult.success({required this.pairingToken, required this.otp})
      : isSuccess = true,
        error = null;

  PairingRegenerateResult.error(this.error)
      : isSuccess = false,
        pairingToken = null,
        otp = null;
}

/// Dialog shown on new device (Device B - e.g., Oppo) 
/// Displays QR code and OTP that needs to be scanned/entered on existing device (Device A - e.g., Vivo)
/// Polling is handled by the login screen via bootstrap API polling
class DevicePairingDialog extends StatefulWidget {
  final String otp;
  final String? pairingToken;
  final VoidCallback? onCancel;
  final VoidCallback? onApproved; // Called when pairing is approved (from parent polling)
  final Future<PairingRegenerateResult> Function()? onRegenerateQR; // Called to regenerate QR code

  const DevicePairingDialog({
    Key? key,
    required this.otp,
    this.pairingToken,
    this.onCancel,
    this.onApproved,
    this.onRegenerateQR,
  }) : super(key: key);

  @override
  State<DevicePairingDialog> createState() => _DevicePairingDialogState();
}

class _DevicePairingDialogState extends State<DevicePairingDialog> {
  bool _isPolling = true;
  bool _isApproved = false;
  String? _currentPairingToken;
  String? _currentOtp;
  Timer? _qrRegenerationTimer;
  int _qrGenerationCount = 0;

  @override
  void initState() {
    super.initState();
    _currentPairingToken = widget.pairingToken;
    _currentOtp = widget.otp;
    
    // Auto-regenerate QR code after 5 minutes
    if (widget.pairingToken != null && widget.pairingToken!.isNotEmpty) {
      _startQRRegenerationTimer();
    }
  }

  @override
  void dispose() {
    _qrRegenerationTimer?.cancel();
    super.dispose();
  }

  void _startQRRegenerationTimer() {
    _qrRegenerationTimer?.cancel();
    _qrRegenerationTimer = Timer(const Duration(minutes: 5), () {
      _regenerateQRCode();
    });
  }

  Future<void> _regenerateQRCode() async {
    if (!mounted) return;
    
    setState(() {
      _isPolling = true; // Show loading state
    });
    
    try {
      debugPrint('🔄 [QR] Auto-regenerating QR code after 5 minutes...');
      
      if (widget.onRegenerateQR != null) {
        final result = await widget.onRegenerateQR!();
        if (result.isSuccess && mounted) {
          setState(() {
            _currentPairingToken = result.pairingToken;
            _currentOtp = result.otp;
            _qrGenerationCount++;
            _isPolling = false;
          });
          debugPrint('🔄 [QR] QR code regenerated successfully (count: $_qrGenerationCount)');
          // Restart timer for next regeneration
          _startQRRegenerationTimer();
        } else {
          debugPrint('❌ [QR] Failed to regenerate QR code: ${result.error}');
          if (mounted) {
            setState(() {
              _isPolling = false;
            });
          }
        }
      } else {
        // No callback provided, just restart timer
        _qrGenerationCount++;
        if (mounted) {
          setState(() {
            _isPolling = false;
          });
          _startQRRegenerationTimer();
        }
      }
    } catch (e) {
      debugPrint('❌ [QR] Failed to regenerate QR code: $e');
      if (mounted) {
        setState(() {
          _isPolling = false;
        });
      }
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
              if ((_currentPairingToken ?? widget.pairingToken) != null && 
                  (_currentPairingToken ?? widget.pairingToken)!.isNotEmpty) ...[
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
                      // Generate URL with current pairingToken
                      QrImageView(
                        data: _generatePairingUrl(_currentPairingToken ?? widget.pairingToken!),
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'QR code valid for 5 minutes',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if (_qrGenerationCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Auto-regenerated ${_qrGenerationCount}x',
                          style: TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Loading indicator when regenerating QR
              if (_isPolling && _qrGenerationCount > 0) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Regenerating QR code...',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 12,
                    color: ColorConstants.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 16),
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
                        Clipboard.setData(ClipboardData(text: _currentOtp ?? widget.otp));
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
                              _currentOtp ?? widget.otp,
                              style: const TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: ColorConstants.primaryTextColor,
                                letterSpacing: 4,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.copy,
                              color: ColorConstants.gradientEnd4,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap to copy',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 11,
                        color: ColorConstants.primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Status message
              if (_isPolling && !_isApproved)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ColorConstants.gradientEnd4.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ColorConstants.gradientEnd4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Waiting for approval...',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 12,
                          color: ColorConstants.primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),

              if (_isApproved)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 12),
                      Text(
                        'Pairing approved!',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 12,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Cancel button
              CustomButton(
                text: 'Cancel',
                onPressed: () {
                  widget.onCancel?.call();
                },
                backgroundColor: Colors.red.withOpacity(0.3),
                textColor: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
