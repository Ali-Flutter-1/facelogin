import 'dart:convert';

import 'package:facelogin/screens/profile/profile_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../constant/constant.dart';
import '../../customWidgets/custom_text_field.dart';
import '../../customWidgets/custom_toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController=TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();


  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  String? _fullName;
  String? _joinedDate;


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


  Future<void> _fetchProfile() async {
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
        final user = data['user'];

        setState(() {
          _firstNameController.text = user['first_name'] ?? '';
          _lastNameController.text = user['last_name'] ?? '';
          _emailController.text = user['email'] ?? '';
          _phoneController.text = user['phone'] ?? '';
          _dobController.text = user['dob'] ?? '';
          _fullName = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();
          final rawDate = user['date_joined'] ?? user['joined_date'] ?? user['created_at'];
          if (rawDate != null && rawDate.toString().isNotEmpty) {
            try {
              final parsedDate = DateTime.parse(rawDate);
              _joinedDate = "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
            } catch (e) {
              _joinedDate = rawDate; // fallback if format is unexpected
            }
          } else {
            _joinedDate = '';
          }


        });
      } else {
        showCustomToast(context, "Failed to load profile.", isError: true);
        debugPrint("Error: ${response.body}");
      }
    } catch (e) {
      debugPrint("Network error: $e");
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
      ),
      body: Container(
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

                  // 🔹 Profile Avatar with Glow + Edit Button

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
                  SizedBox(height: 5,),
                  Text(_fullName??'loading..',style: TextStyle(color: Colors.white,fontSize: 16,),),
                  Text(_joinedDate??'',style: TextStyle(color: Colors.white,fontSize: 16,),),


                  const SizedBox(height: 30),

                  // 🔹 Glass-like Card for Inputs
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

                  // 🔹 Update Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileUpdateScreen()),
                        );

                        if (result == true) {
                          // Re-fetch updated data
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
