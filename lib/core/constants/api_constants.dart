class ApiConstants {
  static const String baseUrl = "https://idp.pollus.tech/api";
  static const String loginOrRegister = "$baseUrl/auth/login_or_register/";
  static const String profileUpdate = "$baseUrl/auth/me/";
  static const String kyc = '$baseUrl/auth/verify-id/';
  static const String imageUpload = '$baseUrl/auth/images/upload/';
  
  // E2E Encryption endpoints
  static const String e2eBootstrap = '$baseUrl/e2e/bootstrap';
  static const String e2eBootstrapComplete = '$baseUrl/e2e/bootstrap/complete';


  // Link Devices endpoints
  static const String allDevices='$baseUrl/e2e/devices';

  // Request headers
  static const String contentTypeJson = "application/json";
  static const String acceptHeader = "application/json, text/plain, */*";
}

