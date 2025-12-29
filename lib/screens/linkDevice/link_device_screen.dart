import 'dart:convert';
import 'dart:io' show Platform;
import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/data/models/device_model.dart';
import 'package:facelogin/data/services/device_service.dart' as device_api;
import 'package:facelogin/data/services/pairing_service.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({Key? key}) : super(key: key);

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final device_api.DeviceApiService _deviceApiService = device_api.DeviceApiService();
  final PairingService _pairingService = PairingService();
  final E2EService _e2eService = E2EService();
  List<DeviceModel> _devices = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  /// Handle pairing token from QR code scan
  /// Extracts pairing token, looks up pairing details, and approves pairing
  Future<void> _handlePairingToken(String qrCodeData) async {
    if (!mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: ColorConstants.gradientEnd4,
        ),
      ),
    );

    try {
      // Extract pairingToken and deviceIdB from QR code
      // QR code might be:
      // 1. URL: https://example.com/pair?pairingToken=xxx&deviceId=yyy
      // 2. JSON: {"pairingToken": "xxx", "deviceId": "yyy"}
      // 3. Plain pairingToken (legacy)
      String pairingToken = qrCodeData.trim();
      String? deviceIdB;
      
      // Check if it's a URL
      if (qrCodeData.startsWith('http://') || qrCodeData.startsWith('https://')) {
        final uri = Uri.tryParse(qrCodeData);
        pairingToken = uri?.queryParameters['pairingToken'] ?? 
                       uri?.pathSegments.last ?? 
                       qrCodeData.trim();
        deviceIdB = uri?.queryParameters['deviceId'];
        debugPrint('🔗 Extracted from URL - pairingToken: $pairingToken, deviceIdB: $deviceIdB');
      } else {
        // Try to parse as JSON
        try {
          final jsonData = jsonDecode(qrCodeData);
          if (jsonData is Map) {
            pairingToken = jsonData['pairingToken']?.toString() ?? qrCodeData.trim();
            deviceIdB = jsonData['deviceId']?.toString();
            debugPrint('🔗 Extracted from JSON - pairingToken: $pairingToken, deviceIdB: $deviceIdB');
          }
        } catch (e) {
          // Not JSON, treat as plain pairingToken (legacy support)
          pairingToken = qrCodeData.trim();
          debugPrint('🔗 Treating QR code as plain pairingToken: $pairingToken');
        }
      }

      debugPrint('🔗 Processing pairing - pairingToken: $pairingToken, deviceIdB: $deviceIdB');

      // Step 1: Lookup pairing by token to get PKd2 (Device B's public key)
      final lookupResult = await _pairingService.lookupByPairingToken(pairingToken);
      
      // Use deviceIdB from QR code if available, otherwise fallback to lookup result
      final finalDeviceIdB = deviceIdB ?? lookupResult.deviceId;
      
      if (finalDeviceIdB == null) {
        if (!mounted) return;
        Navigator.pop(context);
        showCustomToast(
          context,
          'Device ID not found in QR code or lookup response',
          isError: true,
        );
        return;
      }
      
      debugPrint('🔗 Using deviceIdB: $finalDeviceIdB (from QR: ${deviceIdB != null}, from lookup: ${lookupResult.deviceId != null})');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (!lookupResult.isSuccess) {
        showCustomToast(
          context,
          lookupResult.error ?? 'Failed to lookup pairing',
          isError: true,
        );
        return;
      }

      // Step 2: Get current session Ku
      final ku = await _e2eService.getSessionKu();
      if (ku == null) {
        showCustomToast(
          context,
          'Please login first to approve pairing',
          isError: true,
        );
        return;
      }

      // Step 3: Encrypt Ku with new device's public key
      final publicKeyBytes = base64Decode(lookupResult.publicKey!);
      final wrappedKuBase64 = await _e2eService.encryptKuWithPublicKey(
        ku,
        publicKeyBytes,
      );

      // Step 4: Approve pairing
      final success = await _pairingService.approvePairing(
        pairingToken: lookupResult.pairingToken!,
        wrappedKu: wrappedKuBase64,
      );

      if (!mounted) return;

      if (success) {
        showCustomToast(context, 'Device pairing approved successfully!');
        // Refresh devices list
        await _fetchDevices();
      } else {
        showCustomToast(context, 'Failed to approve pairing', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        showCustomToast(
          context,
          'Failed to process pairing: ${e.toString()}',
          isError: true,
        );
      }
      debugPrint('❌ Error handling pairing token: $e');
    }
  }

  Future<void> _fetchDevices() async {
    if (!_isRefreshing) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final devices = await _deviceApiService.getAllDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      if (mounted) {
        showCustomToast(context, 'Failed to load devices: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _isRefreshing = true;
    });
    await _fetchDevices();
  }

  Future<void> _openQRScanner() async {
    // Request camera permission on Android only
    // iOS handles permissions automatically when camera is accessed
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          showCustomToast(
            context,
            'Camera permission is required to scan QR codes. Please enable it in app settings.',
            isError: true,
          );
        }
        return;
      }
    }

    // Dispose existing controller if any
    if (_scannerController != null) {
      try {
        await _scannerController?.stop();
      } catch (e) {
        debugPrint('⚠️ Error stopping scanner: $e');
      }
      try {
        _scannerController?.dispose();
      } catch (e) {
        debugPrint('⚠️ Error disposing scanner: $e');
      }
      _scannerController = null;
    }

    // Create new controller
    // iOS: Keep original behavior (!Platform.isAndroid = true)
    // Android: Changed to true to fix black screen (was false)
    _scannerController = MobileScannerController(
      detectionSpeed: Platform.isAndroid
          ? DetectionSpeed.normal   // allow repeats so your 1-second confirm logic works
          : DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: Platform.isAndroid ? [BarcodeFormat.qrCode] : [],
      autoStart: Platform.isAndroid ? true : (!Platform.isAndroid), // iOS: unchanged (true), Android: fixed (true)
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QRScannerBottomSheet(
        controller: _scannerController!,
        onScan: (String code) async {
          debugPrint('📱 QR Code Scanned: $code');
          debugPrint('📱 QR Code Length: ${code.length}');

          // Close scanner first
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          
          // Wait a bit for the bottom sheet to close
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Stop and dispose scanner safely
          if (_scannerController != null) {
            try {
              await _scannerController?.stop();
            } catch (e) {
              debugPrint('⚠️ Error stopping scanner: $e');
            }
            try {
              _scannerController?.dispose();
            } catch (e) {
              debugPrint('⚠️ Error disposing scanner: $e');
            }
            _scannerController = null;
          }

          // Process the QR code as a pairing token
          if (mounted) {
            await _handlePairingToken(code);
          }
        },
      ),
    ).then((_) {
      // Cleanup if user closes without scanning
      // Wait a bit to ensure widget is fully closed
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _scannerController != null) {
          try {
            _scannerController?.stop();
          } catch (e) {
            debugPrint('⚠️ Error stopping scanner on close: $e');
          }
          try {
            _scannerController?.dispose();
          } catch (e) {
            debugPrint('⚠️ Error disposing scanner on close: $e');
          }
          _scannerController = null;
        }
      });
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _getPlatformIcon(String? platform) {
    if (platform == null) return '📱';
    final lowerPlatform = platform.toLowerCase();
    if (lowerPlatform.contains('ios') || lowerPlatform.contains('iphone') || lowerPlatform.contains('ipad')) {
      return '🍎';
    } else if (lowerPlatform.contains('android')) {
      return '🤖';
    } else if (lowerPlatform.contains('web')) {
      return '🌐';
    }
    return '📱';
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
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
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
                      'Link Device',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: ColorConstants.primaryTextColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: ColorConstants.primaryTextColor,
                      ),
                      onPressed: _isRefreshing ? null : _refreshDevices,
                    ),
                  ],
                ),
              ),

              // Add Device Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: CustomButton(
                  text: 'Add Device',
                  onPressed: _openQRScanner,
                  backgroundColor: const Color(0xFF415A77),
                  textColor: Colors.white,
                  height: 56,
                  borderRadius: BorderRadius.circular(16),
                  image: const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Devices List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ColorConstants.gradientEnd4,
                        ),
                      )
                    : _devices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.devices_other,
                                  size: 80,
                                  color: ColorConstants.primaryTextColor.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'No devices found',
                                  style: TextStyle(
                                    fontFamily: 'OpenSans',
                                    fontSize: 18,
                                    color: ColorConstants.primaryTextColor.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Tap "Add Device" to link a new device',
                                  style: TextStyle(
                                    fontFamily: 'OpenSans',
                                    fontSize: 14,
                                    color: ColorConstants.primaryTextColor.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshDevices,
                            color: ColorConstants.gradientEnd4,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                              itemCount: _devices.length,
                              itemBuilder: (context, index) {
                                final device = _devices[index];
                                return _buildDeviceCard(device);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(DeviceModel device) {
    final isCurrent = device.isCurrentDevice;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF415A77).withValues(alpha: 0.2),
            const Color(0xFF1B263B).withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF415A77).withValues(alpha: 0.5)
              : const Color(0xFF415A77).withValues(alpha: 0.3),
          width: isCurrent ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF415A77).withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF415A77).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getPlatformIcon(device.platform),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.deviceName ?? device.deviceId,
                            style: const TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: ColorConstants.primaryTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF415A77).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ColorConstants.primaryTextColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (device.platform != null)
                      Text(
                        device.platform!,
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 14,
                          color: ColorConstants.primaryTextColor.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  icon: Icons.calendar_today,
                  label: 'Added',
                  value: _formatDate(device.createdAt),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoItem(
                  icon: Icons.access_time,
                  label: 'Last Active',
                  value: _formatDate(device.lastActiveAt),
                ),
              ),
            ],
          ),
          if (device.deviceId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fingerprint,
                    size: 16,
                    color: ColorConstants.primaryTextColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.deviceId,
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 12,
                        color: ColorConstants.primaryTextColor.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: ColorConstants.primaryTextColor.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 12,
                color: ColorConstants.primaryTextColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ColorConstants.primaryTextColor.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

class _QRScannerBottomSheet extends StatefulWidget {
  final MobileScannerController controller;
  final Function(String) onScan;

  const _QRScannerBottomSheet({
    required this.controller,
    required this.onScan,
  });

  @override
  State<_QRScannerBottomSheet> createState() => _QRScannerBottomSheetState();
}

class _QRScannerBottomSheetState extends State<_QRScannerBottomSheet> {
  bool _isProcessing = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  String? _pendingCode;
  DateTime? _pendingCodeTime;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    // Controller auto-starts, scanner widget handles initialization
  }

  @override
  void dispose() {
    // Don't dispose controller here - let parent handle it
    // Just stop it safely
    try {
      widget.controller.stop();
    } catch (e) {
      debugPrint('⚠️ Error stopping scanner in dispose: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: ColorConstants.backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ColorConstants.primaryTextColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const Text(
                  'Scan QR Code',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ColorConstants.primaryTextColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: ColorConstants.primaryTextColor,
                  ),
                  onPressed: () {
                    try {
                      widget.controller.stop();
                    } catch (e) {
                      debugPrint('⚠️ Error stopping scanner on close: $e');
                    }
                    if (mounted && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),

          // Scanner
          Expanded(
            child: Stack(
              children: [
                // MobileScanner widget - always show, let it handle initialization
                SizedBox.expand(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: MobileScanner(
                      controller: widget.controller,
                      fit: BoxFit.cover,
                      onDetect: (capture) async {
                    // Prevent processing if already processing
                    if (_isProcessing) return;

                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isEmpty) {
                      // Clear pending code if no barcode detected
                      _pendingCode = null;
                      _pendingCodeTime = null;
                      return;
                    }

                    final String? code = barcodes.first.rawValue;
                    if (code == null || code.isEmpty) {
                      _pendingCode = null;
                      _pendingCodeTime = null;
                      return;
                    }

                    final now = DateTime.now();

                    // If we have a pending code, check if it's the same
                    if (_pendingCode != null && _pendingCodeTime != null) {
                      // If same code detected again, check if 1 second has passed
                      if (_pendingCode == code) {
                        final timeDiff = now.difference(_pendingCodeTime!);
                        if (timeDiff.inSeconds >= 1) {
                          // 1 second has passed with same code - process it
                          setState(() {
                            _isProcessing = true;
                            _isConfirming = false;
                            _lastScannedCode = code;
                            _lastScanTime = now;
                          });

                          // Stop the scanner to prevent further detections
                          try {
                            await widget.controller.stop();
                          } catch (e) {
                            debugPrint('⚠️ Error stopping scanner: $e');
                          }

                          debugPrint('📱 QR Code Scanned (after 1s delay): $code');

                          // Small delay to show processing state
                          await Future.delayed(const Duration(milliseconds: 300));

                          // Call the callback
                          widget.onScan(code);
                          return;
                        }
                        // Same code but less than 1 second - keep waiting
                        // Show confirming state
                        if (!_isConfirming) {
                          setState(() {
                            _isConfirming = true;
                          });
                        }
                        return;
                      } else {
                        // Different code detected - reset pending
                        setState(() {
                          _pendingCode = code;
                          _pendingCodeTime = now;
                          _isConfirming = false;
                        });
                        return;
                      }
                    }

                    // First time detecting this code - set as pending
                    setState(() {
                      _pendingCode = code;
                      _pendingCodeTime = now;
                      _isConfirming = true;
                    });
                    debugPrint('📱 QR Code detected, waiting 1 second to confirm: $code');
                  },
                    ),
                  ),
                ),

                // Overlay with scanning area
                Container(
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(
                        color: ColorConstants.gradientEnd4,
                        width: 3,
                      ),
                    ),
                  ),
                  margin: const EdgeInsets.all(40),
                ),

                // Loading overlay when confirming/processing
                if (_isConfirming || _isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: ColorConstants.gradientEnd4,
                              strokeWidth: 4,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _isProcessing 
                                  ? 'Processing...'
                                  : 'Confirming QR code...',
                              style: const TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: ColorConstants.primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_pendingCode != null && !_isProcessing)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 40),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _pendingCode!.length > 40 
                                      ? '${_pendingCode!.substring(0, 40)}...'
                                      : _pendingCode!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'OpenSans',
                                    fontSize: 12,
                                    color: ColorConstants.primaryTextColor.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Instructions (only show when not confirming/processing)
                if (!_isConfirming && !_isProcessing)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Position the QR code within the frame',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 16,
                          color: ColorConstants.primaryTextColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

