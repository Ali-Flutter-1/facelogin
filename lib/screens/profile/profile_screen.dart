import 'dart:convert';
import 'package:facelogin/components/kyc.dart';
import 'package:facelogin/screens/kyc/kyc_screen.dart';
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
    with SingleTickerProviderStateMixin {

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

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
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
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');

    if (token == null) {
      debugPrint("ProfileScreen: No access token found");
      showCustomToast(context, "No access token found.", isError: true);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
            (route) => false,
      );
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
          showCustomToast(context, "No user data found in response.", isError: true);
          return;
        }

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
      } else if (response.statusCode == 401) {
        debugPrint("ProfileScreen: Access token invalid or expired");
        showCustomToast(context, "Session expired. Please log in again.", isError: true);
        await storage.deleteAll();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
              (route) => false,
        );
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
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
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
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (context) => const KycScreen()),
                                              );
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
                          if (result == true) {
                            _fetchProfile();
                          }
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

        ],
      ),
    );
  }

  Future<void> logout(BuildContext context) async {
    try {
      // 1. Clear secure storage tokens
      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();

      // 2. Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

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
