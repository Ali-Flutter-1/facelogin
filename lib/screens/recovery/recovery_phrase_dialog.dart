import 'package:facelogin/core/constants/color_constants.dart';
import 'package:facelogin/customWidgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog to show recovery phrase after registration
class RecoveryPhraseDialog extends StatelessWidget {
  final String recoveryPhrase;
  final VoidCallback onContinue;

  const RecoveryPhraseDialog({
    Key? key,
    required this.recoveryPhrase,
    required this.onContinue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent closing without acknowledging
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ColorConstants.gradientEnd3,
                ColorConstants.gradientEnd2,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ColorConstants.gradientEnd4.withValues(alpha: 0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 3,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ColorConstants.gradientEnd4.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 36,
                    color: ColorConstants.gradientEnd4,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Title
                const Text(
                  'Save Your Recovery Phrase',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ColorConstants.primaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                
                // Warning message
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade300,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Write down these 12 words in order. You\'ll need them to recover your account if you lose access to all devices.',
                          style: TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 12,
                            color: ColorConstants.primaryTextColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                
                // Recovery phrase display
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
                    children: [
                      Text(
                        recoveryPhrase,
                        style: const TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ColorConstants.primaryTextColor,
                          height: 1.5,
                          letterSpacing: 0.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      // Copy button
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: recoveryPhrase));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Recovery phrase copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: ColorConstants.gradientEnd4.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.copy,
                                size: 16,
                                color: ColorConstants.primaryTextColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Copy',
                                style: TextStyle(
                                  fontFamily: 'OpenSans',
                                  fontSize: 12,
                                  color: ColorConstants.primaryTextColor.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Continue button
                CustomButton(
                  text: 'I\'ve Saved It',
                  onPressed: onContinue,
                  backgroundColor: const Color(0xFF415A77),
                  textColor: Colors.white,
                  height: 48,
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

