import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pet_care_harmony/app/app_theme.dart';
import 'package:pet_care_harmony/app/pet_care_root.dart';
import 'package:pet_care_harmony/state/app_settings_controller.dart';

class PetCareApp extends StatefulWidget {
  const PetCareApp({super.key});

  @override
  State<PetCareApp> createState() => _PetCareAppState();
}

class _PetCareAppState extends State<PetCareApp> {
  AppSettingsController? _settingsController;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final controller = await AppSettingsController.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settingsController = controller;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = _settingsController;
    if (settingsController == null) {
      return MaterialApp(
        title: 'Pet Care Harmony',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: buildPetCareTheme(Brightness.light),
        darkTheme: buildPetCareTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const PetCareRoot(),
      );
    }

    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Pet Care Harmony',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: buildPetCareTheme(Brightness.light),
          darkTheme: buildPetCareTheme(Brightness.dark),
          themeMode: settingsController.themeMode,
          home: PetCareRoot(settingsController: settingsController),
        );
      },
    );
  }
}
