import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/app_state.dart';
import 'screens/auth_screens.dart';

class ExamTrackerApp extends StatelessWidget {
  const ExamTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'ExamTracker',
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: kPrimaryBlue),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(),
            scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: kPrimaryBlue,
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData(brightness: Brightness.dark).textTheme,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
