import 'dart:convert';
import 'package:facelogin/components/kyc.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/screens/kyc/kyc_screen.dart';
import 'package:facelogin/screens/linkDevice/link_device_screen.dart';
import 'package:facelogin/screens/pairing/otp_approval_screen.dart';
import 'package:facelogin/screens/profile/profile_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constant/constant.dart';
import '../../customWidgets/custom_toast.dart';
import '../../customWidgets/premium_loading.dart';
import '../login/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  String? _fullName;
  String? _joinedDate;
  String? _faceImageUrl; // Store face image URL from API
  bool _idVerified = false; // Track ID verification status
  final KycController controller = Get.put(KycController());

  bool _isInitialLoad = true;
  DateTime? _lastFetchTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();

    _fetchProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh profile when app resumes (user might have updated data on web)
    if (state == AppLifecycleState.resumed) {
      // Only refresh if it's been more than 5 seconds since last fetch
      if (_lastFetchTime == null ||
          DateTime.now().difference(_lastFetchTime!) > const Duration(seconds: 5)) {
        debugPrint("ProfileScreen: App resumed - refreshing profile data");
        _fetchProfile();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark initial load as complete after first build
    if (_isInitialLoad) {
      _isInitialLoad = false;
    }
  }

  // Build individual profile info card with premium design
  Widget _buildProfileInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF415A77).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: const Color(0xFF5B8FA8),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null) {
      debugPrint("ProfileScreen: No access token found");
      if (mounted) {
        showCustomToast(context, "No access token found.", isError: true);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
              (route) => false,
        );
      }
      return;
    }

    try {
      final response = await http.patch(
        Uri.parse(ApiConstants.profileUpdate),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint("ProfileScreen: Response status: ${response.statusCode}, body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("ProfileScreen: Parsed response: $data");

        // Access nested user data
        final user = data['data']?['user'];
        if (user == null) {
          debugPrint("ProfileScreen: No user data found in response");
          if (mounted) {
            showCustomToast(context, "No user data found in response.", isError: true);
          }
          return;
        }

        // Update last fetch time
        _lastFetchTime = DateTime.now();

        if (mounted) {
          setState(() {
            _firstNameController.text = user['first_name']?.toString() ?? '';
            _lastNameController.text = user['last_name']?.toString() ?? '';
            _emailController.text = user['email']?.toString() ?? '';
            _phoneController.text = user['phone']?.toString() ?? '';
            _dobController.text = user['dob']?.toString() ?? '';
            _fullName = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();
            _idVerified = user['id_verified'] ?? false; // Get ID verification status
            _faceImageUrl = user['face_image_url']?.toString(); // Get face image URL

            final rawDate = user['date_joined'] ?? user['joined_date'] ?? user['created_at'];
            if (rawDate != null && rawDate.toString().isNotEmpty) {
              try {
                final parsedDate = DateTime.parse(rawDate);
                _joinedDate = "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
              } catch (e) {
                debugPrint("ProfileScreen: Error parsing date: $e");
                _joinedDate = rawDate?.toString() ?? '';
              }
            } else {
              _joinedDate = '';
            }
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        debugPrint("ProfileScreen: Access token invalid, expired, or user deleted - Status: ${response.statusCode}");

        // Check if user is deleted (404) or unauthorized (401/403)
        String errorMessage = "Session expired. Please log in again.";
        if (response.statusCode == 404) {
          errorMessage = "Your account has been deleted or is no longer available. Please contact support.";
        } else if (response.statusCode == 403) {
          errorMessage = "Access denied. Your account may have been deleted. Please contact support.";
        }

        showCustomToast(context, errorMessage, isError: true);

        // Clear all tokens and E2E session keys (preserve device keys for re-registration)
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('access_token');
        await prefs.remove('refresh_token');
        const secureStorage = FlutterSecureStorage();
        await secureStorage.delete(key: 'e2e_ku_session');

        // Navigate to login screen
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
                (route) => false,
          );
        }
      } else {
        debugPrint("ProfileScreen: Failed to load profile: ${response.statusCode} - ${response.body}");
        showCustomToast(context, "Failed to load profile. Please try again.", isError: true);
      }
    } catch (e) {
      debugPrint("ProfileScreen: Error fetching profile: $e");
      showCustomToast(context, "Unable to load profile. Please check your connection and try again.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21), //
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'OpenSans',
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 26,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          // Only show Verify KYC button if user is not verified
          if (!_idVerified)
            GestureDetector(
              onTap: () async {
                final result = await controller.showKycDialog(context);
                // If KYC was successfully submitted, refresh the profile
                if (result == true) {
                  await _fetchProfile();
                }
              },

              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(5)
                  ),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0,vertical: 4),
                      child: Text('Verify KYC', style: TextStyle(
                        fontFamily: 'OpenSans',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ))
                  ),
                ),
              ),
            )
        ],
      ),
      body: Stack(
        children: [
          // 🔹 Background + Profile Body
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF080B18),
                  Color(0xFF0A0E21),
                  Color(0xFF0D1B2A),
                  Color(0xFF1B263B),
                  Color(0xFF415A77),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _fetchProfile();
                  },
                  color: const Color(0xFF415A77),
                  backgroundColor: const Color(0xFF1B263B),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow effect
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Color(0xFF415A77).withValues(alpha: 0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            // Avatar
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF415A77), Color(0xFF1B263B)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF415A77).withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.transparent,
                                backgroundImage: _faceImageUrl != null &&
                                    _faceImageUrl!.isNotEmpty
                                    ? NetworkImage(_faceImageUrl!)
                                    : null,
                                child: (_faceImageUrl == null ||
                                    _faceImageUrl!.isEmpty)
                                    ? Icon(Icons.person, size: 80, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ],
                        ),


                        const SizedBox(height: 5),
                        Text(
                          _fullName ?? 'Full Name',
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            height: 1.4,
                          ),
                        ),
                        Text(
                          _joinedDate ?? '',
                          style: TextStyle(
                            fontFamily: 'OpenSans',
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.1,
                            height: 1.4,
                          ),
                        ),

                        // Show verification banner if not verified (using dialog box style)
                        if (!_idVerified) ...[
                          const SizedBox(height: 20),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0A0E21),
                                  Color(0xFF0D1B2A),
                                  Color(0xFF1B263B),
                                  Color(0xFF415A77),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 6),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF415A77).withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFF415A77).withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF415A77).withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFF415A77),
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.verified_user_rounded,
                                          color: Color(0xFF5B8FA8),
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Verify Your ID",
                                              style: const TextStyle(
                                                fontFamily: 'OpenSans',
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 20,
                                                letterSpacing: 0.3,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              "Please verify your identity to continue",
                                              style: TextStyle(
                                                fontFamily: 'OpenSans',
                                                color: Colors.white.withOpacity(0.8),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w400,
                                                letterSpacing: 0.2,
                                                height: 1.4,
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            PremiumButton(
                                              text: "Verify",
                                              icon: Icons.upload_file_rounded,
                                              height: 48,
                                              width: null,
                                              onPressed: () async {
                                                final result = await controller.showKycDialog(context);
                                                // If KYC was successfully submitted, refresh the profile
                                                if (result == true) {
                                                  await _fetchProfile();
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),


                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 30),
                        // Profile Information - Individual styled cards
                        Column(
                          children: [
                            _buildProfileInfoCard(
                              icon: Icons.person_outline,
                              label: 'First Name',
                              value: _firstNameController.text.isEmpty
                                  ? '...'
                                  : _firstNameController.text,
                              color: const Color(0xFF415A77),
                            ),
                            const SizedBox(height: 16),
                            _buildProfileInfoCard(
                              icon: Icons.person_outline,
                              label: 'Last Name',
                              value: _lastNameController.text.isEmpty
                                  ? '...'
                                  : _lastNameController.text,
                              color: const Color(0xFF1B263B),
                            ),
                            const SizedBox(height: 16),
                            _buildProfileInfoCard(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: _emailController.text.isEmpty
                                  ? '...'
                                  : _emailController.text,
                              color: const Color(0xFF0D1B2A),
                            ),
                            const SizedBox(height: 16),
                            _buildProfileInfoCard(
                              icon: Icons.phone_outlined,
                              label: 'Phone Number',
                              value: _phoneController.text.isEmpty
                                  ? '...'
                                  : _phoneController.text,
                              color: const Color(0xFF415A77),
                            ),
                            const SizedBox(height: 16),
                            _buildProfileInfoCard(
                              icon: Icons.calendar_today_outlined,
                              label: 'Date of Birth',
                              value: _dobController.text.isEmpty
                                  ? '...'
                                  : _dobController.text,
                              color: const Color(0xFF1B263B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        PremiumButton(
                          backgroundColor: Colors.blue,
                          textColor: Colors.white,
                          text: 'Link Devices',
                          icon: Icons.link,
                          height: 60,
                          onPressed: () {
                            _showLinkDeviceOptions(context);
                          },
                        ),

                        
                        const SizedBox(height: 16),
                        PremiumButton(
                          text: 'Edit Information',
                          icon: Icons.edit_outlined,
                          height: 60,
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                  const ProfileUpdateScreen()),
                            );
                            // Always refresh profile when returning from edit screen
                            // This ensures we have the latest data even if user updated on web
                            _fetchProfile();
                          },
                        ),
                        const SizedBox(height: 16),
                        PremiumButton(
                          text: 'Logout',
                          icon: Icons.logout_rounded,
                          height: 60,
                          onPressed: () async {
                            await logout(context);
                          },
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  void _showLinkDeviceOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1B263B),
              Color(0xFF415A77),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            const Text(
              'Link New Device',
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you want to link your device',
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            
            // Scan QR Code Option
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LinkDeviceScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF415A77).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Scan QR Code',
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scan the QR code from your new device',
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Enter OTP Option
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OtpApprovalScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF415A77).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.pin,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enter OTP',
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter the 6-digit code from your new device',
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> logout(BuildContext context) async {
    try {
      // 1. Clear auth tokens and session keys
      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();

      // Clear auth tokens
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await secureStorage.delete(key: 'e2e_ku_session'); // Clear session key only

      // CRITICAL: Save device owner BEFORE clearing SharedPreferences
      // We need to preserve device_owner_user_id across logout
      final e2eService = E2EService();
      final deviceOwner = await e2eService.getDeviceOwnerUserId();
      
      // DO NOT clear device owner - owner can log back in
      // Device owner persists even after logout
      // Only the original owner can login on this device
      debugPrint('🔐 [LOGOUT] Device owner preserved - Only owner can log back in');

      // DO NOT delete:
      // - e2e_skd (Device Private Key - must stay for owner to log back in)
      // - device_id (Device ID - must stay on device)
      // - device_owner_user_id (Device Owner - must stay so owner can log back in)

      // 2. Clear SharedPreferences (non-sensitive app data)
      // BUT preserve device_owner_user_id
      await prefs.clear();
      
      // 3. Restore device owner after clearing SharedPreferences
      if (deviceOwner != null) {
        await e2eService.setDeviceOwner(deviceOwner);
        debugPrint('🔐 [LOGOUT] Device owner restored: $deviceOwner');
      }

      // 3. Show logout confirmation
      showCustomToast(context, "Logged out successfully!");

      // 4. Navigate to login screen (remove all previous routes)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
            (route) => false,
      );
    } catch (e) {
      showCustomToast(context, "Unable to log out. Please try again.", isError: true);
    }
  }
}
