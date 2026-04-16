import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/ai/ai_secret_store.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/data_storage_page.dart';
import 'package:petnote/data/data_package_file_access.dart';
import 'package:petnote/data/data_storage_coordinator.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('data storage page can export ai summary json', (tester) async {
    final settingsController = await AppSettingsController.load();
    final coordinator = DataStorageCoordinator(
      store: PetNoteStore.seeded(),
      settingsController: settingsController,
      secretStore: InMemoryAiSecretStore(),
    );
    final fileAccess = _FakeDataPackageFileAccess(
      saveBackupHandler: ({required suggestedFileName, required rawJson}) async {
        return const SavedDataPackageFile(
          displayName: 'petnote_ai_summary.json',
          locationLabel: 'Files',
          byteLength: 512,
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: DataStoragePage(
          coordinator: coordinator,
          fileAccess: fileAccess,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('data_storage_export_ai_button')));
    await tester.pumpAndSettle();

    expect(fileAccess.savedBackups, hasLength(1));
    expect(fileAccess.savedBackups.single.displayName, 'petnote_ai_summary.json');
    expect(fileAccess.savedBackups.single.rawJson, contains('"packageType": "ai_summary"'));
    expect(fileAccess.savedBackups.single.rawJson, isNot(contains('sensitiveSettings')));
  });
}

class _SavedBackupRequest {
  const _SavedBackupRequest({
    required this.displayName,
    required this.rawJson,
  });

  final String displayName;
  final String rawJson;
}

class _FakeDataPackageFileAccess implements DataPackageFileAccess {
  _FakeDataPackageFileAccess({
    this.saveBackupHandler,
  });

  final Future<SavedDataPackageFile?> Function({
    required String suggestedFileName,
    required String rawJson,
  })? saveBackupHandler;

  final List<_SavedBackupRequest> savedBackups = <_SavedBackupRequest>[];

  @override
  Future<PickedDataPackageFile?> pickBackupFile() async => null;

  @override
  Future<SavedDataPackageFile?> saveBackupFile({
    required String suggestedFileName,
    required String rawJson,
  }) async {
    savedBackups.add(
      _SavedBackupRequest(
        displayName: suggestedFileName,
        rawJson: rawJson,
      ),
    );
    return saveBackupHandler?.call(
          suggestedFileName: suggestedFileName,
          rawJson: rawJson,
        ) ??
        SavedDataPackageFile(
          displayName: suggestedFileName,
          locationLabel: 'Files',
          byteLength: rawJson.length,
        );
  }
}
