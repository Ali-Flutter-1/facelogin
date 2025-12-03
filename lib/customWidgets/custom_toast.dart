import 'package:flutter/material.dart';

// Extension on BuildContext for easy usage throughout the app
extension CustomSnackbarExtension on BuildContext {
  /// Show a custom snackbar with your theme colors
  void showCustomToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      _createCustomSnackBar(message, isError: isError),
    );
  }
}

/// Creates a custom SnackBar with your gradient theme colors
SnackBar _createCustomSnackBar(String message, {bool isError = false}) {
  // 🎨 Your theme gradient colors
  final LinearGradient successGradient = const LinearGradient(
    colors: [
      Color(0xFF0A0E21),
      Color(0xFF0D1B2A),
      Color(0xFF1B263B),
      Color(0xFF415A77),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Error gradient
  final LinearGradient errorGradient = LinearGradient(
    colors: [
      Colors.red.shade900,
      Colors.red.shade800,
      Colors.red.shade700,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final backgroundGradient = isError ? errorGradient : successGradient;
  final borderColor = isError
      ? Colors.red.shade400.withValues(alpha: 0.5)
      : const Color(0xFF415A77).withValues(alpha: 0.5);

  return SnackBar(
    content: Container(
      decoration: BoxDecoration(
        gradient: backgroundGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: Colors.white,
            height: 1.3,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
    duration: const Duration(seconds: 3),
    backgroundColor: Colors.transparent,
    elevation: 0,
    behavior: SnackBarBehavior.fixed,
    padding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
    ),
    clipBehavior: Clip.antiAlias,
  );
}

// Helper function to show custom toast (for backward compatibility)
void showCustomToast(BuildContext context, String message, {bool isError = false}) {
  context.showCustomToast(message, isError: isError);
}
