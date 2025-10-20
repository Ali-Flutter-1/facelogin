import 'package:delightful_toast/delight_toast.dart';
import 'package:delightful_toast/toast/components/toast_card.dart';
import 'package:delightful_toast/toast/utils/enums.dart';
import 'package:flutter/material.dart';

void showCustomToast(BuildContext context, String message, {bool isError = false}) {
  // 🎨 Define color scheme
  final Color iconColor = Colors.white;

  // ✅ For success → gradient blend of your theme colors
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

  // ✅ For error → solid red tone
  final Color errorColor = Colors.red.shade700;

  DelightToastBar(
    builder: (context) {
      return Container(
        decoration: BoxDecoration(
          gradient: isError ? null : successGradient,
          color: isError ? errorColor : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ToastCard(
          shadowColor: Colors.transparent,
          color: Colors.transparent, // handled by container
          title: Text(
            message,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          leading: Icon(
            isError ? Icons.error : Icons.check_circle,
            size: 26,
            color: iconColor,
          ),
        ),
      );
    },
    position: DelightSnackbarPosition.bottom,
    autoDismiss: true,
    animationDuration: const Duration(milliseconds: 300),
    snackbarDuration: const Duration(seconds: 2),
  ).show(context);
}
