import 'package:flutter/material.dart';
import 'package:petnote/app/petnote_pages.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class PetDeviceDashboard extends StatelessWidget {
  const PetDeviceDashboard({
    super.key,
    required this.store,
    required this.servedPetId,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onSelectServedPet,
    required this.onMarkDone,
    required this.onOpenSettings,
  });

  final PetNoteStore store;
  final String? servedPetId;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
  final ValueChanged<String> onSelectServedPet;
  final ValueChanged<PetAction> onMarkDone;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final pets = store.pets;
    final selectedPet = _findPet(pets, servedPetId);
    return Scaffold(
      backgroundColor: const Color(0xFF17181C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: selectedPet == null
              ? _PetSelector(
                  pets: pets,
                  onSelectServedPet: onSelectServedPet,
                  onOpenSettings: onOpenSettings,
                )
              : _DashboardContent(
                  store: store,
                  pet: selectedPet,
                  syncStatusLabel: syncStatusLabel,
                  pendingItemKeys: pendingItemKeys,
                  onMarkDone: onMarkDone,
                  onOpenSettings: onOpenSettings,
                ),
        ),
      ),
    );
  }
}

Pet? _findPet(List<Pet> pets, String? petId) {
  for (final pet in pets) {
    if (pet.id == petId) {
      return pet;
    }
  }
  return null;
}

class _PetSelector extends StatelessWidget {
  const _PetSelector({
    required this.pets,
    required this.onSelectServedPet,
    required this.onOpenSettings,
  });

  final List<Pet> pets;
  final ValueChanged<String> onSelectServedPet;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '这台设备为谁服务？',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SyncFailureChip(),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final pet in pets)
          Card(
            key: ValueKey('dashboard_select_pet_${pet.id}'),
            child: ListTile(
              leading: CircleAvatar(child: Text(pet.avatarText)),
              title: Text(pet.name),
              subtitle: Text('${pet.breed} · ${pet.ageLabel}'),
              onTap: () => onSelectServedPet(pet.id),
            ),
          ),
      ],
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.store,
    required this.pet,
    required this.syncStatusLabel,
    required this.pendingItemKeys,
    required this.onMarkDone,
    required this.onOpenSettings,
  });

  final PetNoteStore store;
  final Pet pet;
  final String syncStatusLabel;
  final Set<String> pendingItemKeys;
  final ValueChanged<PetAction> onMarkDone;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final items = store.checklistSections
        .expand((section) => section.items)
        .where((item) => item.petId == pet.id)
        .take(5)
        .toList(growable: false);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Sticker(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text('${pet.breed} · ${pet.ageLabel}'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 216,
              child: _Sticker(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SyncFailureChip(),
                    IconButton(
                      key: const ValueKey('pet_dashboard_settings'),
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Sticker(
          child: Row(
            children: [
              const Icon(Icons.cloud_done_rounded),
              const SizedBox(width: 10),
              Text(syncStatusLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _Sticker(
            child: items.isEmpty
                ? const Center(child: Text('今日没有待办'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final itemKey = '${item.sourceType}:${item.id}';
                      return ListTile(
                        key: ValueKey(
                            'dashboard_item_${item.sourceType}_${item.id}'),
                        title: Text(item.title),
                        subtitle: Text(item.dueLabel),
                        trailing: pendingItemKeys.contains(itemKey)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(Icons.check_circle_rounded),
                                onPressed: () => onMarkDone(
                                  PetAction(
                                    kind: PetActionKind.markDone,
                                    sourceType: item.sourceType,
                                    itemId: item.id,
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _Sticker extends StatelessWidget {
  const _Sticker({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DF),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
