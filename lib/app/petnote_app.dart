import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/state/app_settings_controller.dart';

class PetNoteApp extends StatefulWidget {
  const PetNoteApp({super.key});

  @override
  State<PetNoteApp> createState() => _PetNoteAppState();
}

class _PetNoteAppState extends State<PetNoteApp> {
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
        title: 'PetNote',
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
        theme: buildPetNoteTheme(Brightness.light),
        darkTheme: buildPetNoteTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const PetNoteRoot(),
      );
    }

    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        return MaterialApp(
          title: 'PetNote',
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
          theme: buildPetNoteTheme(Brightness.light),
          darkTheme: buildPetNoteTheme(Brightness.dark),
          themeMode: settingsController.themeMode,
          home: PetNoteRoot(settingsController: settingsController),
        );
      },
    );
  }
}
