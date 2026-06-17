import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncService.instance = null;
  });

  tearDown(() async {
    await SyncService.instance?.stop();
    SyncService.instance = null;
  });

  testWidgets('未选择服务宠物时展示宠物选择列表', (tester) async {
    final store = PetNoteStore.seeded();
    String? selectedPetId;
    var openedSettings = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PetDeviceDashboard(
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

    final pet = store.pets.first;
    await tester.tap(find.byKey(ValueKey('dashboard_select_pet_${pet.id}')));
    await tester.pump();
    expect(selectedPetId, pet.id);

    await tester.tap(find.byIcon(Icons.settings_rounded).first);
    await tester.pump();
    expect(openedSettings, isTrue);
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
    PetAction? action;

    await tester.pumpWidget(
      MaterialApp(
        home: PetDeviceDashboard(
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
    expect(find.text('测试喂饭'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
    await tester.pump();

    expect(action?.kind, PetActionKind.markDone);
    expect(action?.sourceType, 'todo');
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
    final service = SyncService(settings: await AppSettingsController.load());
    service.petController = controller;
    SyncService.instance = service;
    controller.failedSyncCount.value = 2;

    await tester.pumpWidget(
      MaterialApp(
        home: PetDeviceDashboard(
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
        find.byKey(const ValueKey('pet_dashboard_settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_failure_chip')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync_failure_chip')));
    await tester.pumpAndSettle();

    expect(find.text('同步失败'), findsWidgets);
    expect(find.byKey(const ValueKey('sync_failure_retry_button')),
        findsOneWidget);

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
