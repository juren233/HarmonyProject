import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncService.instance = null;
  });

  tearDown(() async {
    debugPetPhotoImageBuilder = null;
    debugHasPetPhotoOverride = null;
    await SyncService.instance?.stop();
    SyncService.instance = null;
  });

  testWidgets('未选择服务宠物时展示宠物选择列表', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    String? selectedPetId;
    var openedSettings = false;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (value) => selectedPetId = value,
          onMarkDone: (_) {},
          onOpenSettings: () => openedSettings = true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pet_selector_hero')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pet_selector_list_panel')), findsOneWidget);
    expect(find.text('这台设备照顾谁？'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);

    final pet = store.pets.first;
    await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
    await tester.pump();
    expect(selectedPetId, pet.id);

    await tester.tap(find.byIcon(Icons.settings_rounded).first);
    await tester.pump();
    expect(openedSettings, isTrue);
  });

  testWidgets('横屏下服务宠物选择页使用中枢式分栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    String? selectedPetId;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (value) => selectedPetId = value,
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('pet_selector_side_panel')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pet_selector_list_panel')), findsOneWidget);
    expect(find.text('选择服务宠物'), findsOneWidget);
    expect(find.text('这台设备照顾谁？'), findsOneWidget);

    final pet = store.pets.first;
    await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
    await tester.pump();
    expect(selectedPetId, pet.id);
  });

  testWidgets('服务宠物选择页显示同步后的真实头像', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final photoFile = File(
      '${Directory.systemTemp.path}/petnote-selector-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (photoFile.existsSync()) {
        photoFile.deleteSync();
      }
    });
    debugHasPetPhotoOverride = (path) => path == photoFile.path;
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required BoxFit fit,
      required Widget fallback,
    }) {
      return SizedBox(
        key: ValueKey('selector-real-photo-$photoPath'),
      );
    };
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await store.addPet(
      name: '强',
      type: PetType.dog,
      photoPath: photoFile.path,
      breed: '法斗',
      sex: '弟弟',
      birthday: '2025-01-01',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '同步头像',
    );

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: null,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.byKey(ValueKey('selector-real-photo-${photoFile.path}')),
        findsOneWidget);
  });

  testWidgets('看板展示同步状态并把待办完成动作回调给上层', (tester) async {
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '测试喂饭',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;
    PetAction? action;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (value) => action = value,
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text(pet.name), findsWidgets);
    expect(find.text('已连接'), findsOneWidget);
    final petCard = find.byKey(const ValueKey('pet_dashboard_pet_card'));
    expect(
        find.descendant(of: petCard, matching: find.text('已连接')), findsNothing);
    expect(find.text(firstItem.title), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
    await tester.pump();

    expect(action?.kind, PetActionKind.markDone);
    expect(action?.sourceType, firstItem.sourceType);
  });

  testWidgets('深色模式下宠物端看板使用主题文字和监控面板', (tester) async {
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
        brightness: Brightness.dark,
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, darkPetNoteTokens.pageGradientTop);

    final title = tester.widget<Text>(find.text(pet.name));
    expect(title.style?.color, darkPetNoteTokens.primaryText);
    expect(
      find.byKey(const ValueKey('pet_dashboard_pet_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pet_dashboard_todo_panel')),
      findsOneWidget,
    );
    expect(find.text('下一件事'), findsWidgets);
  });

  testWidgets('横屏下宠物端看板保留头像状态区和待办主区域', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    await store.addTodo(
      petId: pet.id,
      title: '横屏喂食',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      notificationLeadTime: NotificationLeadTime.none,
      note: '',
    );
    final firstItem = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .first;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pet_dashboard_pet_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pet_dashboard_todo_panel')),
      findsOneWidget,
    );
    expect(find.text('已连接'), findsOneWidget);
    final petCard = find.byKey(const ValueKey('pet_dashboard_pet_card'));
    expect(
        find.descendant(of: petCard, matching: find.text('已连接')), findsNothing);
    expect(find.text(firstItem.title), findsOneWidget);
    expect(find.text('下一件事'), findsOneWidget);
  });

  testWidgets('宠物端看板优先显示同步后的真实头像', (tester) async {
    final photoFile = File(
      '${Directory.systemTemp.path}/petnote-dashboard-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (photoFile.existsSync()) {
        photoFile.deleteSync();
      }
    });
    debugHasPetPhotoOverride = (path) => path == photoFile.path;
    debugPetPhotoImageBuilder = ({
      required String photoPath,
      required BoxFit fit,
      required Widget fallback,
    }) {
      return SizedBox(
        key: ValueKey('dashboard-real-photo-$photoPath'),
      );
    };
    final store =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    await store.addPet(
      name: '强',
      type: PetType.dog,
      photoPath: photoFile.path,
      breed: '法斗',
      sex: '弟弟',
      birthday: '2025-01-01',
      weightKg: 8,
      neuterStatus: PetNeuterStatus.unknown,
      feedingPreferences: '少食多餐',
      allergies: '无',
      note: '同步头像',
    );
    final pet = store.pets.single;

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.byKey(ValueKey('dashboard-real-photo-${photoFile.path}')),
        findsOneWidget);
  });

  testWidgets('同步失败时宠物端在设置旁显示胶囊', (tester) async {
    final store = PetNoteStore.seeded();
    final pet = store.pets.first;
    final transport = _FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: store,
      transport: transport,
      crypto: crypto,
    );
    final settings = await AppSettingsController.load();
    final service = SyncService(settings: settings);
    service.petController = controller;
    SyncService.instance = service;
    await settings.setPendingResetSnapshotSyncId('failed-sync');

    await tester.pumpWidget(
      _wrapDashboard(
        PetDeviceDashboard(
          store: store,
          servedPetId: pet.id,
          syncStatusLabel: '已连接',
          pendingItemKeys: const <String>{},
          onSelectServedPet: (_) {},
          onMarkDone: (_) {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pet_dashboard_settings')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sync_failure_chip')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync_failure_chip')));
    await tester.pumpAndSettle();

    expect(find.text('同步失败'), findsWidgets);
    expect(
      find.byKey(const ValueKey('sync_failure_retry_button')),
      findsOneWidget,
    );

    await service.stop();
    SyncService.instance = null;
  });

  testWidgets('合并冲突弹窗返回保留对方', (tester) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            dialogContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showSyncMergeConflictDialog(
      dialogContext,
      const SyncMergeConflict(
        collectionLabel: '待办',
        id: 'todo-1',
        localLabel: '本机待办',
        remoteLabel: '对方待办',
        differences: [
          SyncMergeDifference(
            fieldPath: 'title',
            localValue: '本机待办',
            remoteValue: '对方待办',
          ),
          SyncMergeDifference(
            fieldPath: 'note',
            localValue: '本机备注',
            remoteValue: '对方备注',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待办冲突'), findsOneWidget);
    expect(find.textContaining('本机待办'), findsWidgets);
    expect(find.text('title'), findsOneWidget);
    expect(find.text('note'), findsOneWidget);
    expect(find.textContaining('对方备注'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync_merge_keep_remote')));
    await tester.pumpAndSettle();

    expect(await future, SyncMergeSide.remote);
  });
}

Widget _wrapDashboard(Widget child,
    {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildPetNoteTheme(brightness),
    home: child,
  );
}

class _FakeSyncTransport implements SyncTransport {
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  ValueListenable<SyncConnectionState> get state => _state;
  final ValueNotifier<SyncConnectionState> _state =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connected);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void send(SyncMessage message) {}
}
