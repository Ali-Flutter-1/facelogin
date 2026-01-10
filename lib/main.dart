import 'package:facelogin/screens/splash/splash_screen.dart';
import 'package:facelogin/core/services/token_expiration_service.dart';
import 'package:facelogin/core/services/http_interceptor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set navigator keys for global services
  TokenExpirationService.setNavigatorKey(navigatorKey);
  HttpInterceptorService.setNavigatorKey(navigatorKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      navigatorKey: navigatorKey,
      useInheritedMediaQuery: true,
      debugShowCheckedModeBanner: false,
      title: 'Valyd',
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


//  flutter run -d 00008030-000224D10C86402E --profile
// flutter run -d 510223E5-B19D-43BF-B71B-30854FDA9811
