part of 'petnote_pages.dart';

class PetsPage extends StatefulWidget {
  const PetsPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    required this.onEditPet,
    this.aiInsightsService,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final ValueChanged<Pet> onEditPet;
  final AiInsightsService? aiInsightsService;

  @override
  State<PetsPage> createState() => _PetsPageState();
}

class _PetsPageState extends State<PetsPage> {
  @override
  Widget build(BuildContext context) {
    final pet = widget.store.selectedPet;
    final remindersForSelectedPet = widget.store.remindersForSelectedPet;
    final recordsForSelectedPet = widget.store.recordsForSelectedPet;
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        PageHeader(
          title: '爱宠',
          subtitle: pet == null ? '管理你的宠物档案' : '${pet.name} 的照护档案',
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.store.pets.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = widget.store.pets[index];
              final selected = pet?.id == item.id;
              return GestureDetector(
                onTap: () => widget.store.selectPet(item.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFF2A65A)
                        : const Color(0xF4FFFFFF),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      PetPhotoAvatar(
                        photoPath: item.photoPath,
                        fallbackText: item.avatarText,
                        radius: 20,
                        backgroundColor: selected
                            ? const Color(0x33FFFFFF)
                            : const Color(0xFFE8EEFF),
                        foregroundColor:
                            selected ? Colors.white : const Color(0xFF335FCA),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFF17181C),
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.ageLabel,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: selected
                                          ? Colors.white70
                                          : const Color(0xFF6C7280),
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (pet == null)
          PageEmptyStateBlock(
            emptyTitle: '先添加第一只爱宠',
            emptySubtitle: '建好第一份宠物档案后，提醒、记录和照护观察都会围绕它展开。',
            actionLabel: '开始添加宠物',
            onAction: widget.onAddFirstPet,
          )
        else ...[
          HeroPanel(
            title: pet.name,
            subtitle:
                '${petTypeLabel(pet.type)} · ${pet.breed} · ${pet.ageLabel} · 当前体重 ${pet.weightKg} kg',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                return Column(
                  children: [
                    if (hasPetPhoto(pet.photoPath)) ...[
                      SizedBox(
                        width: availableWidth,
                        child: Center(
                          child: PetPhotoSquare(
                            photoPath: pet.photoPath,
                            size: availableWidth - 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: MetricOverview(
                            metrics: [
                              MetricItem(
                                label: '近期提醒',
                                value: '${remindersForSelectedPet.length}',
                                background: const Color(0xFFEAF0FF),
                                foreground: const Color(0xFF335FCA),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => PetDetailsPage(
                                        pet: pet,
                                        reminders: remindersForSelectedPet,
                                        records: recordsForSelectedPet,
                                        detailType: PetDetailType.reminders,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              MetricItem(
                                label: '资料记录',
                                value: '${recordsForSelectedPet.length}',
                                background: const Color(0xFFF5F0FF),
                                foreground: const Color(0xFF6B51C9),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => PetDetailsPage(
                                        pet: pet,
                                        reminders: remindersForSelectedPet,
                                        records: recordsForSelectedPet,
                                        detailType: PetDetailType.records,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          SectionCard(
            title: '基础信息',
            trailing: TextButton(
              key: const ValueKey('edit_pet_button'),
              onPressed: () => widget.onEditPet(pet),
              child: const Text('编辑信息'),
            ),
            children: [
              InfoRow(label: '类型', value: petTypeLabel(pet.type)),
              InfoRow(label: '性别', value: pet.sex),
              InfoRow(label: '生日', value: pet.birthday),
              InfoRow(
                label: '绝育状态',
                value: petNeuterStatusLabel(pet.neuterStatus),
              ),
              InfoRow(label: '喂养偏好', value: pet.feedingPreferences),
              InfoRow(label: '过敏/禁忌', value: pet.allergies),
              InfoRow(label: '备注', value: pet.note),
            ],
          ),
        ],
      ],
    );
  }
}
