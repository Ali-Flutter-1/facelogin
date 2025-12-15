import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  final double height;
  final Color backgroundColor;
  final TextStyle? textStyle;
  final Color textColor;
  final double fontSize;
  final BorderRadius borderRadius;
  final BoxBorder? border;
  final Widget? image;

  const CustomButton(
      {super.key,
        required this.text,
        required this.onPressed,

        this.height = 56,
        this.backgroundColor = Colors.blue,
        this.textColor = Colors.white,
        this.fontSize = 16,
        this.border,
        this.borderRadius = const BorderRadius.all(Radius.circular(10)),
        this.textStyle,
        this.image});

  @override
  Widget build(BuildContext context) {
    return Container(

      height: height,
      decoration: BoxDecoration(
        border: border,
        borderRadius: borderRadius,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null) ...[
              image!,
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: textStyle ??
                  TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
