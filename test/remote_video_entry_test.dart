import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('无宠物时爱宠页不显示远程视频入口', (tester) async {
    final store = await PetNoteStore.load(
      storage: PetNoteLocalStorage.memory(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('remote_video_pill')), findsNothing);
  });

  testWidgets('爱宠页远程视频入口弹出两个选项并进入占位页', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetNoteTheme(Brightness.light),
        home: Scaffold(
          body: PetsPage(
            store: store,
            onAddFirstPet: () {},
            onEditPet: (_) {},
          ),
        ),
      ),
    );

    final pill = find.byKey(const ValueKey('remote_video_pill'));
    expect(pill, findsOneWidget);

    await tester.tap(pill);
    await tester.pumpAndSettle();

    expect(find.text('视频通话'), findsOneWidget);
    expect(find.text('先看看它'), findsOneWidget);

    await tester.tap(find.text('先看看它'));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteVideoPlaceholderPage), findsOneWidget);
    expect(find.text('先看看它'), findsOneWidget);
    expect(find.text('未配对宠物端'), findsOneWidget);
    // 连接对象固定为爱宠页当前展示的宠物。
    expect(find.text('连接对象：${store.selectedPet!.name}'), findsOneWidget);
    expect(find.text('实时画面功能即将上线'), findsOneWidget);
  });

  testWidgets('远程视频只连当前宠物对应的宠物端设备', (tester) async {
    final store = PetNoteStore.seeded();
    addTearDown(store.dispose);
    final pet = store.pets.first;

    Future<void> pumpPlaceholder(List<SyncedDeviceInfo> devices) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPetNoteTheme(Brightness.light),
          home: RemoteVideoPlaceholderPage(
            mode: RemoteVideoMode.watch,
            pet: pet,
            devicesOverride: devices,
          ),
        ),
      );
    }

    // 指派给当前宠物的设备：可连。
    await pumpPlaceholder([
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        servedPetId: pet.id,
        online: true,
      ),
    ]);
    expect(find.text('客厅平板 在线'), findsOneWidget);

    // 指派给其他宠物的设备：不可连。
    await pumpPlaceholder(const [
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        servedPetId: 'other-pet',
        online: true,
      ),
    ]);
    expect(find.text('未配对宠物端'), findsOneWidget);

    // 未指派宠物的设备：视为可服务当前宠物。
    await pumpPlaceholder(const [
      SyncedDeviceInfo(
        deviceId: 'pet-device',
        name: '客厅平板',
        role: 'pet',
        online: false,
      ),
    ]);
    expect(find.text('客厅平板 离线'), findsOneWidget);
  });
}
