import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/pet_device_dashboard.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
