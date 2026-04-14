import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:petnote/ai/ai_client_factory.dart';
import 'package:petnote/ai/ai_connection_tester.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/ai/ai_settings_coordinator.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_root.dart';
import 'package:petnote/logging/app_crash_diagnostics.dart';
import 'package:petnote/logging/app_log_controller.dart';
import 'package:petnote/state/app_settings_controller.dart';

const String _appTaskTitle = '宠记';

class PetNoteApp extends StatefulWidget {
  const PetNoteApp({
    super.key,
    this.settingsController,
    this.aiSecretStore,
    this.aiConnectionTester,
    this.aiInsightsService,
    this.appLogController,
  });

  final AppSettingsController? settingsController;
  final AiSecretStore? aiSecretStore;
  final AiConnectionTester? aiConnectionTester;
  final AiInsightsService? aiInsightsService;
  final AppLogController? appLogController;

  @override
  State<PetNoteApp> createState() => _PetNoteAppState();
}

class _PetNoteAppState extends State<PetNoteApp> {
  AppSettingsController? _settingsController;
  AppLogController? _appLogController;

  @override
  void initState() {
    super.initState();
    if (widget.settingsController != null) {
      _settingsController = widget.settingsController;
      _appLogController = widget.appLogController ?? AppLogController.memory();
      _activateCrashDiagnostics(_appLogController!);
    } else {
      _loadControllers();
    }
  }

  Future<void> _loadControllers() async {
    final controller = await AppSettingsController.load();
    final appLogController =
        widget.appLogController ?? await AppLogController.load();
    if (!mounted) {
      return;
    }
    _activateCrashDiagnostics(appLogController);
    setState(() {
      _settingsController = controller;
      _appLogController = appLogController;
    });
  }

  @override
  void dispose() {
    final appLogController = _appLogController;
    if (appLogController != null) {
      AppCrashDiagnosticsBinding.instance.detachController(appLogController);
    }
    super.dispose();
  }

  void _activateCrashDiagnostics(AppLogController controller) {
    AppCrashDiagnosticsBinding.instance.attachController(controller);
    controller.beginCrashMonitoringSession();
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = _settingsController;
    final appLogController = _appLogController;
    if (settingsController == null || appLogController == null) {
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
          appLogController: appLogController,
          aiSettingsCoordinator: _settingsController == null
              ? null
              : AiSettingsCoordinator(
                  settingsController: _settingsController!,
                  secretStore: widget.aiSecretStore ??
                      MethodChannelAiSecretStore(
                        appLogController: appLogController,
                      ),
                  connectionTester: widget.aiConnectionTester ??
                      AiConnectionTester(
                        appLogController: appLogController,
                      ),
                ),
          aiInsightsService: widget.aiInsightsService,
        ),
      );
    }

    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final secretStore = widget.aiSecretStore ??
            MethodChannelAiSecretStore(
              appLogController: appLogController,
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
          home: PetNoteRoot(
            appLogController: appLogController,
            settingsController: settingsController,
            aiSettingsCoordinator: AiSettingsCoordinator(
              settingsController: settingsController,
              secretStore: secretStore,
              connectionTester: widget.aiConnectionTester ??
                  AiConnectionTester(
                    appLogController: appLogController,
                  ),
            ),
            aiInsightsService: widget.aiInsightsService ??
                NetworkAiInsightsService(
                  clientFactory: AiClientFactory(
                    settingsController: settingsController,
                    secretStore: secretStore,
                  ),
                  appLogController: appLogController,
                ),
          ),
        );
      },
    );
  }
}
