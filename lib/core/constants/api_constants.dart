import 'package:facelogin/core/constants/app_config.dart';

class ApiConstants {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get vcBaseUrl => AppConfig.vcBaseUrl;
  static String get loginOrRegister => "$baseUrl/auth/login_or_register/";
  static String get profileUpdate => "$baseUrl/auth/me/";
  static String get kyc => '$baseUrl/auth/verify-id/';
  static String get imageUpload => '$baseUrl/auth/images/upload/';
  
  // E2E Encryption endpoints
  static String get e2eBootstrap => '$baseUrl/e2e/bootstrap';
  static String get e2eBootstrapComplete => '$baseUrl/e2e/bootstrap/complete';
  static String get e2eRecovery => '$baseUrl/e2e/recovery';
  static String get e2eRecoveryPhraseEncoded => '$baseUrl/e2e/recovery-phrase-encoded';


  // Link Devices endpoints
  static String get allDevices => '$baseUrl/e2e/devices';

  // Device Pairing endpoints (for cross-device E2E setup)
  static String get pairingRequest => '$baseUrl/e2e/pairing/request';
  static String get pairingLookupByOtp => '$baseUrl/e2e/pairing/lookup-by-otp';
  static String get pairingApprove => '$baseUrl/e2e/pairing/approve';
  static String get pairingLookup => '$baseUrl/e2e/pairing/lookup';

  // Account deletion endpoints
  static String get verifyFace => '$baseUrl/auth/verify-face';
  static String get deleteAccount => '$baseUrl/auth/delete-account';

  // Request headers
  static const String contentTypeJson = "application/json";
  static const String acceptHeader = "application/json, text/plain, */*";
}

