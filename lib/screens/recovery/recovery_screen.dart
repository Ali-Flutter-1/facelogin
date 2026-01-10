import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/core/services/e2e_service.dart';
import 'package:facelogin/core/services/recovery_key_service.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:facelogin/customWidgets/custom_toast.dart';
import 'package:facelogin/screens/main/main_screen.dart';
import 'package:facelogin/screens/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({Key? key}) : super(key: key);

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final TextEditingController _phraseController = TextEditingController();
  final E2EService _e2eService = E2EService();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // No bootstrap polling needed for recovery
    // Recovery is a direct process: enter phrase -> call /e2e/recovery -> decrypt -> generate keys -> bootstrap/complete
    // Bootstrap polling is only needed for pairing scenarios (waiting for QR scan or OTP entry)
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _recoverAccount() async {
    final phrase = _phraseController.text.trim();
    
    if (phrase.isEmpty) {
      showCustomToast(context, 'Please enter your recovery phrase', isError: true);
      return;
    }

    if (!RecoveryKeyService.isValidRecoveryPhrase(phrase)) {
      showCustomToast(
        context,
        'Invalid recovery phrase. Please enter 12 valid words separated by spaces.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null || accessToken.isEmpty) {
        showCustomToast(context, 'Please login first', isError: true);
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Call recovery
      final result = await _e2eService.recoverWithPhrase(phrase, accessToken);

      if (!mounted) return;

      if (result.isSuccess) {
        // Recovery successful - verify E2E keys are set up
        final hasE2EKeys = await _e2eService.hasE2EKeys();
        final hasSessionKu = await _e2eService.getSessionKu() != null;

        if (hasE2EKeys && hasSessionKu) {
          if (!mounted) return;
          
          // Show success loading dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1B263B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Recovery Successful!',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Setting up your account...',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
          
          // Wait for everything to sync (5 seconds)
          await Future.delayed(const Duration(milliseconds: 5000));
          
          if (!mounted) return;
          
          // Close the dialog
          Navigator.of(context).pop();
          
        setState(() {
          _isProcessing = false;
        });
        
          // Navigate to profile and clear entire navigation stack
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false, // Remove all previous routes
          );
        } else {
          // Keys not properly stored - recovery failed
          setState(() {
            _isProcessing = false;
          });
          showCustomToast(
            context,
            'Recovery completed but keys not properly stored. Please try again.',
            isError: true,
          );
        }
      } else {
        // Recovery failed - show error and stay on recovery screen
        setState(() {
          _isProcessing = false;
        });
        showCustomToast(
          context,
          result.error ?? 'Recovery failed',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        showCustomToast(
          context,
          'Recovery failed: ${e.toString()}',
          isError: true,
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ColorConstants.gradientStart,
              ColorConstants.gradientEnd1,
              ColorConstants.gradientEnd2,
              ColorConstants.gradientEnd3,
              ColorConstants.gradientEnd4,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: ColorConstants.primaryTextColor,
                        size: 20,
                      ),
                      onPressed: () {
                        // Navigate to splash screen instead of going back
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const SplashScreen()),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Account Recovery',
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: ColorConstants.primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Icon
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ColorConstants.gradientEnd4.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_reset,
                            size: 48,
                            color: ColorConstants.gradientEnd4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      const Text(
                        'Recover Your Account',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: ColorConstants.primaryTextColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // Description
                      Text(
                        'Enter your 12-word recovery phrase to restore access to your account. This will generate new device keys.',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 14,
                          color: ColorConstants.primaryTextColor.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Recovery phrase input
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ColorConstants.gradientEnd4.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recovery Phrase',
                              style: TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: ColorConstants.primaryTextColor.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _phraseController,
                              style: const TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 14,
                                color: ColorConstants.primaryTextColor,
                              ),
                              decoration: InputDecoration(
                                hintText: 'word1 word2 word3 ... word12',
                                hintStyle: TextStyle(
                                  fontFamily: 'OpenSans',
                                  fontSize: 14,
                                  color: ColorConstants.primaryTextColor.withValues(alpha: 0.4),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: ColorConstants.gradientEnd4.withValues(alpha: 0.3),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: ColorConstants.gradientEnd4.withValues(alpha: 0.3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: ColorConstants.gradientEnd4,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.2),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              textCapitalization: TextCapitalization.none,
                              autocorrect: false,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter all 12 words separated by spaces',
                              style: TextStyle(
                                fontFamily: 'OpenSans',
                                fontSize: 11,
                                color: ColorConstants.primaryTextColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Recover button
                      CustomButton(
                        text: _isProcessing ? 'Recovering...' : 'Recover Account',
                        onPressed: _isProcessing ? () {} : () => _recoverAccount(),
                        backgroundColor: const Color(0xFF415A77),
                        textColor: Colors.white,
                        height: 48,
                        borderRadius: BorderRadius.circular(12),
                        image: _isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(
                                Icons.restore,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

