class LoginResponseModel {
  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? data;
  
  // New backend response fields (default to false if null)
  final bool isNewUser;
  final bool isDeviceFound;
  final bool isDeviceLinkedWithUser;
  final bool isPublicKeyMatched;

  LoginResponseModel({
    this.accessToken,
    this.refreshToken,
    this.data,
    this.isNewUser = false,
    this.isDeviceFound = false,
    this.isDeviceLinkedWithUser = false,
    this.isPublicKeyMatched = false,
  });

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) {
    final responseData = json['data'];
    
    // Parse new backend fields (handle both bool and string types)
    // If null, default to false
    bool parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is int) return value != 0;
      return value.toString().toLowerCase() == 'true';
    }
    
    return LoginResponseModel(
      accessToken: responseData?['access_token'],
      refreshToken: responseData?['refresh_token'],
      data: responseData,
      isNewUser: parseBool(responseData?['is_new_user'] ?? responseData?['isNewUser']),
      isDeviceFound: parseBool(responseData?['is_device_found'] ?? responseData?['isDeviceFound']),
      isDeviceLinkedWithUser: parseBool(responseData?['is_device_linked_with_user'] ?? responseData?['isDeviceLinkedWithUser']),
      isPublicKeyMatched: parseBool(responseData?['is_public_key_matched'] ?? responseData?['isPublicKeyMatched']),
    );
  }

  bool get hasValidTokens =>
      accessToken != null && accessToken!.isNotEmpty &&
      refreshToken != null && refreshToken!.isNotEmpty;
}

