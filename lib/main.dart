import 'package:facelogin/screens/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      useInheritedMediaQuery: true,
      debugShowCheckedModeBanner: false,
      title: 'Face Login Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        fontFamily: 'OpenSans',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w700),
          displayMedium: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w700),
          displaySmall: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w700),
          headlineLarge: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          headlineSmall: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          titleSmall: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w400),
          bodyMedium: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w400),
          bodySmall: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w400),
          labelLarge: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w600),
          labelSmall: TextStyle(fontFamily: 'OpenSans', fontWeight: FontWeight.w400),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}


// flutter run -d 00008030-000224D10C86402E --profile