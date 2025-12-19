import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/data/models/device_model.dart';
import 'package:facelogin/data/services/device_service.dart' as device_api;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({Key? key}) : super(key: key);

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final device_api.DeviceApiService _deviceApiService = device_api.DeviceApiService();
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

  void _openQRScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QRScannerBottomSheet(
        controller: _scannerController!,
        onScan: (String code) async {
          Navigator.pop(context);
          _scannerController?.dispose();
          _scannerController = null;

          // Show loading
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: CircularProgressIndicator(
                  color: ColorConstants.gradientEnd4,
                ),
              ),
            );
          }

          try {
            await _deviceApiService.linkDevice(code);
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              showCustomToast(context, 'Device linked successfully!');
              _fetchDevices();
            }
          } catch (e) {
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              showCustomToast(context, 'Failed to link device: ${e.toString()}', isError: true);
            }
          }
        },
      ),
    ).then((_) {
      _scannerController?.dispose();
      _scannerController = null;
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
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Scanner
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: widget.controller,
                  onDetect: (capture) {
                    if (_isProcessing) return;

                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String code = barcodes.first.rawValue ?? '';
                      if (code.isNotEmpty) {
                        setState(() {
                          _isProcessing = true;
                        });
                        widget.onScan(code);
                      }
                    }
                  },
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

                // Instructions
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

