import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/app_version_info.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';
import 'package:petnote/app/pet_device_home.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

const String _appTaskTitle = '宠记';

class PetNoteApp extends StatefulWidget {
  const PetNoteApp({
    super.key,
    this.settingsController,
    this.aiSecretStore,
    this.aiConnectionTester,
    this.aiInsightsService,
    this.nativePetPhotoPicker,
    this.appVersionInfo = AppVersionInfo.empty,
    this.storeLoader,
  });

  final AppSettingsController? settingsController;
  final AiSecretStore? aiSecretStore;
  final AiConnectionTester? aiConnectionTester;
  final AiInsightsService? aiInsightsService;
  final NativePetPhotoPicker? nativePetPhotoPicker;
  final AppVersionInfo appVersionInfo;
  final Future<PetNoteStore> Function()? storeLoader;

  @override
  State<PetNoteApp> createState() => _PetNoteAppState();
}

class _PetNoteAppState extends State<PetNoteApp> {
  AppSettingsController? _settingsController;
  late AppVersionInfo _appVersionInfo;
  PetNoteStore? _preloadedStore;

  @override
  void initState() {
    super.initState();
    _appVersionInfo = widget.appVersionInfo;
    if (widget.settingsController != null) {
      _settingsController = widget.settingsController;
      if (_appVersionInfo == AppVersionInfo.empty) {
        _loadAppVersionInfo();
      }
    } else {
      _loadControllers();
    }
  }

  Future<void> _loadControllers() async {
    final storeFuture = (widget.storeLoader ?? PetNoteStore.load)();
    final versionFuture = _appVersionInfo == AppVersionInfo.empty
        ? AppVersionInfo.load()
        : Future<AppVersionInfo>.value(_appVersionInfo);
    final store = await storeFuture;
    final controller = await AppSettingsController.load(
      hasExistingLocalData: _hasExistingLocalData(store),
    );
    final appVersionInfo = await versionFuture;
    if (!mounted) {
      return;
    }
    setState(() {
      _preloadedStore = store;
      _settingsController = controller;
      _appVersionInfo = appVersionInfo;
    });
  }

  Future<void> _loadAppVersionInfo() async {
    final appVersionInfo = await AppVersionInfo.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _appVersionInfo = appVersionInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = _settingsController;
    if (settingsController == null) {
      return MaterialApp(
        title: _appTaskTitle,
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
        home: PetNoteRoot(
          appVersionInfo: _appVersionInfo,
          nativePetPhotoPicker: widget.nativePetPhotoPicker,
          storeLoader: widget.storeLoader,
          aiSettingsCoordinator: _settingsController == null
              ? null
              : AiSettingsCoordinator(
                  settingsController: _settingsController!,
                  secretStore:
                      widget.aiSecretStore ?? MethodChannelAiSecretStore(),
                  connectionTester:
                      widget.aiConnectionTester ?? AiConnectionTester(),
                ),
          aiInsightsService: widget.aiInsightsService,
        ),
      );
    }

    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final secretStore =
            widget.aiSecretStore ?? MethodChannelAiSecretStore();
        final home = settingsController.deviceRole == DeviceRole.pet
            ? PetDeviceHome(
                settingsController: settingsController,
                storeLoader: _loadStore,
              )
            : PetNoteRoot(
                appVersionInfo: _appVersionInfo,
                settingsController: settingsController,
                nativePetPhotoPicker: widget.nativePetPhotoPicker,
                storeLoader: _loadStore,
                aiSettingsCoordinator: AiSettingsCoordinator(
                  settingsController: settingsController,
                  secretStore: secretStore,
                  connectionTester:
                      widget.aiConnectionTester ?? AiConnectionTester(),
                ),
                aiInsightsService: widget.aiInsightsService ??
                    NetworkAiInsightsService(
                      clientFactory: AiClientFactory(
                        settingsController: settingsController,
                        secretStore: secretStore,
                      ),
                    ),
              );
        return MaterialApp(
          title: _appTaskTitle,
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
          home: home,
        );
      },
    );
  }

  Future<PetNoteStore> _loadStore() async {
    final preloadedStore = _preloadedStore;
    if (preloadedStore != null) {
      _preloadedStore = null;
      return preloadedStore;
    }
    return (widget.storeLoader ?? PetNoteStore.load)();
  }

  bool _hasExistingLocalData(PetNoteStore store) {
    return store.pets.isNotEmpty ||
        store.todos.isNotEmpty ||
        store.reminders.isNotEmpty ||
        store.records.isNotEmpty;
  }
}
