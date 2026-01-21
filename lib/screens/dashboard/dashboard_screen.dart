import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:facelogin/components/kyc.dart';
import 'package:facelogin/core/constants/app_constants.dart';
import 'package:facelogin/core/constants/api_constants.dart';
import 'package:facelogin/core/controllers/user_controller.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final KycController controller = Get.put(KycController());
  final UserController userController = Get.find<UserController>();
  bool _isSsoLoading = false;

  /// Call SSO authorize API and open the autologin URL in browser
  Future<void> _openWorkerCredentialBadge() async {
    if (_isSsoLoading) return;
    
    setState(() => _isSsoLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.accessTokenKey);

      if (token == null || token.isEmpty) {
        showCustomToast(context, 'Please login again', isError: true);
        setState(() => _isSsoLoading = false);
        return;
      }

      // Call the SSO authorize API
      final redirectUri = Uri.encodeComponent('${ApiConstants.vcBaseUrl}/autologin');
      final ssoUrl = '${ApiConstants.baseUrl}/auth/sso-authorize?redirect_uri=$redirectUri';
      
      debugPrint('🔐 [SSO] Calling: $ssoUrl');
      
      final response = await http.get(
        Uri.parse(ssoUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('🔐 [SSO] Response status: ${response.statusCode}');
      debugPrint('🔐 [SSO] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data']?['token'] != null) {
          final ssoToken = data['data']['token'];
          final autologinUrl = '${ApiConstants.vcBaseUrl}/autologin?code=$ssoToken';
          
          debugPrint('🔐 [SSO] Opening URL: $autologinUrl');
          
          // Open in browser
          final uri = Uri.parse(autologinUrl);
          try {
            final launched = await launchUrl(
              uri, 
              mode: LaunchMode.externalApplication,
            );
            if (!launched) {
              debugPrint('❌ [SSO] launchUrl returned false');
              if (mounted) {
                showCustomToast(context, 'Could not open browser', isError: true);
              }
            }
          } catch (launchError) {
            debugPrint('❌ [SSO] launchUrl error: $launchError');
            if (mounted) {
              showCustomToast(context, 'Could not open browser', isError: true);
            }
          }
        } else {
          showCustomToast(context, 'Failed to get SSO token', isError: true);
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['message'] ?? errorData['error'] ?? 'SSO authorization failed';
        showCustomToast(context, errorMsg.toString(), isError: true);
      }
    } catch (e) {
      debugPrint('❌ [SSO] Error: $e');
      showCustomToast(context, 'Failed to authorize. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSsoLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Obx(() => userController.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome message
                    Text(
                      'Welcome, ${userController.displayName}!',
                      style: const TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This is your dashboard',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // KYC Status Card
                    if (!userController.idVerified)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.withOpacity(0.2),
                              Colors.orange.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Verify Your Identity',
                                    style: TextStyle(
                                      fontFamily: 'OpenSans',
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Complete your KYC verification to unlock all features and secure your account.',
                              style: TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final result = await controller.showKycDialog(context);
                                  if (result == true) {
                                    await userController.refreshUserData();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Verify KYC',
                                  style: TextStyle(
                                    fontFamily: 'OpenSans',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Verified Status Card
                    if (userController.idVerified)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.withOpacity(0.2),
                              Colors.green.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.verified,
                                color: Colors.green,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Identity Verified',
                                    style: TextStyle(
                                      fontFamily: 'OpenSans',
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Your account is fully verified',
                                    style: TextStyle(
                                      fontFamily: 'OpenSans',
                                      fontSize: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 30),

                    // Valyd Applications Section
                    const Text(
                      'Valyd Applications',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Worker Credential Badge Card
                    _buildWorkerCredentialCard(),
                  ],
                ),
              ),
            )),
    );
  }

  Widget _buildWorkerCredentialCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D1B2A),
            Color(0xFF1B263B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF415A77).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Shield icon with badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF415A77).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.verified_user,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Worker Credential Badge',
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Verify your employment status and work history with trusted employers.',
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 13,
                color: Colors.white.withOpacity(0.7),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Learn More Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _isSsoLoading ? null : _openWorkerCredentialBadge,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSsoLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else ...[
                      const Text(
                        'Learn More',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new,
                        color: Colors.white.withOpacity(0.8),
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
