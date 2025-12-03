import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../constant/constant.dart';
import '../../customWidgets/custom_text_field.dart';
import '../../customWidgets/custom_toast.dart';
import '../../customWidgets/premium_loading.dart';
import '../login/login_screen.dart';

class ProfileUpdateScreen extends StatefulWidget {
  const ProfileUpdateScreen({Key? key}) : super(key: key);

  @override
  State<ProfileUpdateScreen> createState() => _ProfileUpdateScreenState();
}

class _ProfileUpdateScreenState extends State<ProfileUpdateScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();

  DateTime? _selectedDate;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _idVerified = false; // Track ID verification status

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
    _fetchExistingProfile();
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF415A77),
              onPrimary: Colors.white,
              surface: Color(0xFF1B263B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }


  Future<void> _fetchExistingProfile() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');

    if (token == null) {
      showCustomToast(context, "No access token found.", isError: true);
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("ProfileScreen: Parsed response: $data");

        // Access nested user data
        final user = data['data']?['user'];
        if (user == null) {
          debugPrint("ProfileScreen: No user data found in response");
          showCustomToast(context, "No user data found in response.", isError: true);
          setState(() => _isLoading = false);
          return;
        }

        setState(() {
          _firstNameController.text = user['first_name']?.toString() ?? '';
          _lastNameController.text = user['last_name']?.toString() ?? '';
          _emailController.text = user['email']?.toString() ?? '';
          _phoneController.text = user['phone']?.toString() ?? '';
          _dobController.text = user['dob']?.toString() ?? '';
          _idVerified = user['id_verified'] ?? false; // Get ID verification status
          _isLoading = false;
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
        setState(() => _isLoading = false);
      }} catch (e) {
      debugPrint("Network error: $e");
      showCustomToast(context, "Unable to load profile. Please check your connection and try again.", isError: true);
      setState(() => _isLoading = false,);

    }}


  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');

    if (token == null) {
      showCustomToast(context, "No access token found.", isError: true);
      setState(() => _isSaving = false);
      return;
    }

    // Only include first_name and last_name if id_verified is false
    // If id_verified is true, these fields are read-only and shouldn't be updated
    final Map<String, dynamic> bodyData = {
      "dob": _dobController.text.trim(),
      "phone": _phoneController.text.trim(),
      "email": _emailController.text.trim(),
    };
    
    // Only add first_name and last_name if user is not verified
    if (!_idVerified) {
      bodyData["first_name"] = _firstNameController.text.trim();
      bodyData["last_name"] = _lastNameController.text.trim();
    }
    
    final body = jsonEncode(bodyData);

    try {
      final response = await http.patch(
        Uri.parse(ApiConstants.profileUpdate),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: body,
      );

      if (response.statusCode == 200) {
        showCustomToast(context, "Profile updated successfully!");
        Navigator.pop(context, true);
      } else {
        debugPrint("Update failed: ${response.body}");
        showCustomToast(context, "Failed to update profile.", isError: true);
      }
    } catch (e) {
      debugPrint("Error updating profile: $e");
      showCustomToast(context, "Network error. Please check your connection and try again.", isError: true);
    } finally {
      setState(() => _isSaving = false); // 🔹 Stop loading
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0A0E21),
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF415A77),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 10),



                  // 🔹 Glass-like Input Card with premium design
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF415A77).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 0,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          CustomInnerInputField(
                            label: 'First Name',
                            controller: _firstNameController,
                            icon: Icons.person_outline,
                            readOnly: _idVerified, // Read-only if id_verified is true
                          ),
                          CustomInnerInputField(
                            label: 'Last Name',
                            controller: _lastNameController,
                            icon: Icons.person_outline,
                            readOnly: _idVerified, // Read-only if id_verified is true
                          ),
                          CustomInnerInputField(
                            label: 'Email',
                            controller: _emailController,
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          CustomInnerInputField(
                            label: 'Phone',
                            controller: _phoneController,
                            icon: Icons.phone_android_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          CustomInnerInputField(
                            label: 'Date of Birth',
                            controller: _dobController,
                            readOnly: _idVerified,
                            onTap: () => _selectDate(context),
                            icon: Icons.calendar_today_outlined,
                            hintText: 'Select your birth date',
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // 🔹 Save Button with premium design
                  PremiumButton(
                    text: "Save Changes",
                    icon: Icons.save_outlined,
                    height: 56,
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _saveProfile,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
