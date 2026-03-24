import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_care_harmony/app/pet_care_root.dart';

class PetCareApp extends StatelessWidget {
  const PetCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B8CFF);
    return MaterialApp(
      title: 'Pet Care Harmony',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          surface: const Color(0xFFF8F5F0),
          surfaceContainerHighest: const Color(0xFFF3F4F8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F2EC),
        useMaterial3: true,
        textTheme: const TextTheme(
          displaySmall: TextStyle(fontSize: 34, height: 1.04),
          headlineSmall: TextStyle(fontSize: 27, height: 1.1),
          titleLarge: TextStyle(fontSize: 22, height: 1.2),
          titleMedium: TextStyle(fontSize: 18, height: 1.25),
          bodyLarge: TextStyle(fontSize: 16, height: 1.35),
          bodyMedium: TextStyle(fontSize: 14, height: 1.45),
          bodySmall: TextStyle(fontSize: 12, height: 1.45),
          labelLarge: TextStyle(fontSize: 14, height: 1.1),
          labelMedium: TextStyle(fontSize: 12, height: 1.1),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111218),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF727888),
            minimumSize: const Size(0, 46),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F7FA),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          hintStyle: const TextStyle(color: Color(0xFF9AA0AC)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: accent, width: 1.3),
          ),
        ),
      ),
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: PetCareRoot(),
      ),
    );
  }
}
