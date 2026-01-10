import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:facelogin/screens/dashboard/dashboard_screen.dart';
import 'package:facelogin/screens/settings/settings_screen.dart';
import 'package:facelogin/screens/profile/profile_view_screen.dart';
import 'package:facelogin/core/controllers/user_controller.dart';
import 'package:facelogin/core/services/token_expiration_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  // Initialize the shared UserController at the MainScreen level
  final UserController _userController = Get.put(UserController());

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ProfileViewScreen(),
    const SettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    
    // Initialize token expiration service and start checking
    final tokenExpirationService = TokenExpirationService();
    final navigatorKey = GlobalKey<NavigatorState>();
    TokenExpirationService.setNavigatorKey(navigatorKey);
    
    // Check if token is already expired on app start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isExpired = await tokenExpirationService.isTokenExpired();
      if (isExpired) {
        debugPrint('🔐 [MainScreen] Token already expired on app start');
        // Token expiration service will handle logout
      } else {
        // Start expiration check if token exists
        final prefs = await SharedPreferences.getInstance();
        final hasToken = prefs.getString('access_token') != null;
        if (hasToken) {
          // Check if expiration time is set, if not set it (for existing sessions)
          final expirationTime = await tokenExpirationService.getTokenExpiration();
          if (expirationTime == null) {
            await tokenExpirationService.setTokenExpiration();
          } else {
            tokenExpirationService.startExpirationCheck();
          }
        }
      }
    });
    
    // Debug: Print local storage keys after 10 seconds (will hide later)
    Future.delayed(const Duration(seconds: 10), () {
      _printDebugStorageInfo();
    });
  }
  
  /// Debug function to print local storage public key and states
  Future<void> _printDebugStorageInfo() async {
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('📦 DEBUG: LOCAL STORAGE INFO (after 10 seconds)');
    debugPrint('═══════════════════════════════════════════════════════════');
    
    try {
      // SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      debugPrint('');
      debugPrint('📋 SharedPreferences:');
      debugPrint('───────────────────────────────────────────────────────────');
      debugPrint('  access_token: ${prefs.getString('access_token') != null ? "SET (${prefs.getString('access_token')!.length} chars)" : "NOT SET"}');
      debugPrint('  refresh_token: ${prefs.getString('refresh_token') != null ? "SET" : "NOT SET"}');
      debugPrint('  e2e_setup_complete: ${prefs.getBool('e2e_setup_complete') ?? false}');
      debugPrint('  device_owner_user_id: ${prefs.getString('device_owner_user_id') ?? "NOT SET"}');
      
      // FlutterSecureStorage
      const secureStorage = FlutterSecureStorage();
      debugPrint('');
      debugPrint('🔐 FlutterSecureStorage:');
      debugPrint('───────────────────────────────────────────────────────────');
      
      final publicKey = await secureStorage.read(key: 'e2e_public_key');
      final privateKey = await secureStorage.read(key: 'e2e_private_key');
      final kuSession = await secureStorage.read(key: 'e2e_ku_session');
      final deviceId = await secureStorage.read(key: 'e2e_device_id');
      
      debugPrint('  e2e_public_key: ${publicKey != null ? publicKey : "NOT SET"}');
      debugPrint('  e2e_private_key: ${privateKey != null ? "SET (${privateKey.length} chars)" : "NOT SET"}');
      debugPrint('  e2e_ku_session (Ku): ${kuSession != null ? "SET (${kuSession.length} chars)" : "NOT SET"}');
      debugPrint('  e2e_device_id: ${deviceId ?? "NOT SET"}');
      
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('');
    } catch (e) {
      debugPrint('❌ Error reading storage: $e');
    }
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    debugPrint('MainScreen: Pull-to-refresh triggered');
    await _userController.refreshUserData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: Colors.blue,
        backgroundColor: const Color(0xFF1B263B),
        // Wrap in CustomScrollView to enable pull-to-refresh
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B263B),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.dashboard,
                  label: 'Dashboard',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.person,
                  label: 'Profile',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.settings,
                  label: 'Settings',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.white70,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue : Colors.white70,
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
