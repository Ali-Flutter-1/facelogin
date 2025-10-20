import 'dart:convert';

import 'package:facelogin/screens/login/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../profile/profile_screen.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin{
  final _storage = const FlutterSecureStorage();
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 0));

    _controller.forward();
    _checkTokenAndNavigate();
  }

  Future<void> _checkTokenAndNavigate() async {
    final accessToken = await _storage.read(key: "access_token");

    await Future.delayed(const Duration(seconds: 3)); // smooth transition

    if (accessToken != null && accessToken.isNotEmpty) {
      final isExpired = _isTokenExpired(accessToken);
      if (!isExpired) {

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        return;
      } else {

        await _storage.deleteAll();
      }
    }


    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GlassMorphismLoginScreen()),
    );
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );

      final exp = payload['exp'];
      if (exp == null) return true;

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      debugPrint("JWT decode error: $e");
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 👇 Your logo image
              Image.asset(
                'assets/images/logo.png',
                width: 120,
                height: 120,
              ),

              Text(
                  "The AI era is drowning in noise.",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,

                  ),
                ),

              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child:  Center(
                  child: Text(
                    "Pollus verifies identity, credentials, and responses—instantly—so you can trust every insight and eliminate friction.",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: 40),

            ],
          ),
        ),
      ),
    );
  }
}