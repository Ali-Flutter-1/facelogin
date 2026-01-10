import 'package:facelogin/screens/profile/profile_update_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:facelogin/core/controllers/user_controller.dart';

class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({Key? key}) : super(key: key);

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen>
    with SingleTickerProviderStateMixin {
  final UserController _userController = Get.find<UserController>();

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  String _formatJoinedDate(String createdAt) {
    if (createdAt.isEmpty) return '';
    try {
      final date = DateTime.parse(createdAt);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return createdAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileUpdateScreen(),
                ),
              );
              // Refresh profile if update was successful
              if (result == true && mounted) {
                _userController.refreshUserData();
              }
            },
          ),
        ],
      ),
      body: Obx(() => _userController.isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Profile image
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _userController.faceImageUrl != null && _userController.faceImageUrl!.isNotEmpty
                              ? Image.network(
                                  _userController.faceImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white70,
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.white70,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Profile info cards
                    _buildProfileInfoCard(
                      icon: Icons.person,
                      label: 'First Name',
                      value: _userController.firstName.isNotEmpty ? _userController.firstName : 'Not set',
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoCard(
                      icon: Icons.person_outline,
                      label: 'Last Name',
                      value: _userController.lastName.isNotEmpty ? _userController.lastName : 'Not set',
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoCard(
                      icon: Icons.email,
                      label: 'Email',
                      value: _userController.email.isNotEmpty ? _userController.email : 'Not set',
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoCard(
                      icon: Icons.phone,
                      label: 'Phone',
                      value: _userController.phone.isNotEmpty ? _userController.phone : 'Not set',
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoCard(
                      icon: Icons.calendar_today,
                      label: 'Date of Birth',
                      value: _userController.dob.isNotEmpty ? _userController.dob : 'Not set',
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoCard(
                      icon: Icons.verified,
                      label: 'ID Verified',
                      value: _userController.idVerified ? 'Yes' : 'No',
                    ),
                    if (_userController.createdAt.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildProfileInfoCard(
                        icon: Icons.calendar_today_outlined,
                        label: 'Joined Date',
                        value: _formatJoinedDate(_userController.createdAt),
                      ),
                    ],
                  ],
                ),
              ),
            )),
    );
  }

  Widget _buildProfileInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
