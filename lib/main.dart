
import 'package:device_preview/device_preview.dart';
import 'package:facelogin/screens/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';




void main() => runApp(
  DevicePreview(

    builder: (context) => MyApp(), // Wrap your app
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Login Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
