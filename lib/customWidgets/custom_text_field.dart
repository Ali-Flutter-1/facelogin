import 'package:flutter/material.dart';

class CustomInnerInputField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final String? hintText;
  final double height;

  const CustomInnerInputField({
    Key? key,
    required this.label,
    this.height = 60,
    this.controller,
    this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.validator,
    this.hintText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label above the textfield
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          // Fixed height container for the text field
          SizedBox(
            height: height,
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: 1,
              readOnly: readOnly,
              onTap: onTap,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              validator: validator ??
                      (value) {
                    if (!readOnly && (value?.isEmpty ?? true)) {
                      return 'Please enter $label';
                    }
                    return null;
                  },
              decoration: InputDecoration(
                hintText: hintText ?? 'Enter $label',
                prefixIcon: icon != null
                    ? Icon(icon, color: Colors.white70, size: 22)
                    : null,
                hintStyle: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF415A77)),
                ),
                filled: true,
                fillColor: const Color(0xFF1B263B).withValues(alpha: 0.5),
                // 👇 ensures uniform vertical spacing within the 60 height
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18, // Perfect balance for 60px height
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
