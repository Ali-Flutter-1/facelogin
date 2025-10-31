import 'dart:convert';
import 'package:facelogin/components/kyc.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:facelogin/screens/kyc/kyc_screen.dart';
import 'package:facelogin/screens/profile/profile_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constant/constant.dart';
import '../../customWidgets/custom_text_field.dart';
import '../../customWidgets/custom_toast.dart';
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
  bool _showPopup = false;
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
    _checkPopupStatus(); // check once at start
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

  Future<void> _checkPopupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool('popup_shown') ?? false;

    if (!alreadyShown) {
      await Future.delayed(const Duration(milliseconds: 600)); // small delay for smoother UI
      setState(() {
        _showPopup = true;
      });
      prefs.setBool('popup_shown', true);
    }
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
        showCustomToast(context, "Failed to load profile: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      debugPrint("ProfileScreen: Error fetching profile: $e");
      showCustomToast(context, "Error fetching profile: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 26,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => controller.showKycDialog(context),

            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(5)
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0,vertical: 4),
                  child: Text('Verify KYC',style: GoogleFonts.acme(textStyle: TextStyle(
                    color: Colors.white,fontSize: 14
                  )),),
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF415A77), Color(0xFF1B263B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.transparent,
                          child: Icon(
                            Icons.person,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _fullName ?? 'Full Name',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Text(
                        _joinedDate ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            CustomInnerInputField(
                              label: 'First Name',
                              controller: _firstNameController,
                              icon: Icons.person_outline,
                              readOnly: true,
                            ),
                            CustomInnerInputField(
                              label: 'Last Name',
                              controller: _lastNameController,
                              icon: Icons.person_outline,
                              readOnly: true,
                            ),
                            CustomInnerInputField(
                              label: 'Email',
                              controller: _emailController,
                              icon: Icons.email_outlined,
                              readOnly: true,
                            ),
                            CustomInnerInputField(
                              label: 'Phone Number',
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              icon: Icons.phone_outlined,
                              readOnly: true,
                            ),
                            CustomInnerInputField(
                              label: 'Date of Birth',
                              readOnly: true,
                              controller: _dobController,
                              icon: Icons.calendar_today_outlined,
                              hintText: 'Select Date of Birth',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF415A77),
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: Colors.blueAccent.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Edit Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: () async {
                              await logout(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF415A77),
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: Colors.blueAccent.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 🔹 Popup Layer (appears only first time)
          if (_showPopup)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: AlertDialog(
                  backgroundColor: const Color(0xFF007AFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Please verify your ID",
                          style: GoogleFonts.robotoCondensed(
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _showPopup = false);
                        },
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  content:  Text(
                    "Please upload your ID on Pollus ID to continue.",
                    style: GoogleFonts.roboto( textStyle: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold,fontSize: 16,)),
                  ),
                  actions: [
                      SizedBox(width: double.infinity,
                        child: CustomButton(text: "Verify ID",backgroundColor: Colors.black54, onPressed: (){
                               Navigator.push(context, MaterialPageRoute(builder: (context)=>KycScreen()));
                               setState(() => _showPopup = false);
                        }),
                      )
                  ],
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
      showCustomToast(context, "Error logging out: $e", isError: true);
    }
  }
}
