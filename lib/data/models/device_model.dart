class DeviceModel {
  final String deviceId;
  final String? deviceName;
  final String? deviceType;
  final String? platform;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final bool isCurrentDevice;

  DeviceModel({
    required this.deviceId,
    this.deviceName,
    this.deviceType,
    this.platform,
    this.createdAt,
    this.lastActiveAt,
    this.isCurrentDevice = false,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    // Parse dates from various formats
    DateTime? parseDate(dynamic dateValue) {
      if (dateValue == null) return null;
      if (dateValue is DateTime) return dateValue;
      if (dateValue is String) {
        return DateTime.tryParse(dateValue);
      }
      return null;
    }

    // Determine platform from device_id if not provided
    String? determinePlatform(String? deviceId) {
      if (deviceId == null) return null;
      final lowerId = deviceId.toLowerCase();
      if (lowerId.startsWith('ios-') || lowerId.contains('iphone') || lowerId.contains('ipad')) {
        return 'iOS';
      } else if (lowerId.startsWith('android-') || lowerId.contains('android')) {
        return 'Android';
      }
      return null;
    }

    final deviceId = json['deviceId'] ?? json['device_id'] ?? '';
    
    return DeviceModel(
      deviceId: deviceId,
      deviceName: json['deviceName'] ?? json['device_name'],
      deviceType: json['deviceType'] ?? json['device_type'],
      platform: json['platform'] ?? json['os'] ?? determinePlatform(deviceId),
      createdAt: parseDate(json['createdAt']) ?? 
                 parseDate(json['created_at']) ?? 
                 parseDate(json['paired_at']),
      lastActiveAt: parseDate(json['lastActiveAt']) ?? 
                   parseDate(json['last_active_at']) ?? 
                   parseDate(json['last_updated']),
      isCurrentDevice: json['isCurrentDevice'] ?? json['is_current_device'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'platform': platform,
      'createdAt': createdAt?.toIso8601String(),
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'isCurrentDevice': isCurrentDevice,
    };
  }
}

