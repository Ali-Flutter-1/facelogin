class ApiConstants {
  static const String baseUrl = "https://idp.pollus.tech/api";
  static const String loginOrRegister = "$baseUrl/auth/login_or_register/";
  static const String profileUpdate = "$baseUrl/auth/me/";
  static const String kyc = '$baseUrl/auth/verify-id/';
  static const String imageUpload = '$baseUrl/auth/images/upload/';

  // Request headers
  static const String contentTypeJson = "application/json";
  static const String acceptHeader = "application/json, text/plain, */*";
}

