part of 'petnote_pages.dart';

class PetsPage extends StatefulWidget {
  const PetsPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    required this.onEditPet,
    this.aiInsightsService,
    this.remoteVideoPermissionCoordinator,
    this.interactionHapticsDriver,
    this.nowProvider,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final ValueChanged<Pet> onEditPet;
  final AiInsightsService? aiInsightsService;
  final RtcMediaPermissionCoordinator? remoteVideoPermissionCoordinator;
  final InteractionHapticsDriver? interactionHapticsDriver;
  final DateTime Function()? nowProvider;

  @override
  State<PetsPage> createState() => _PetsPageState();
}

class _PetsPageState extends State<PetsPage> {
  late final NativePetPhotoPicker _nativePetPhotoPicker =
      MethodChannelNativePetPhotoPicker();
  late final InteractionHapticsDriver _interactionHapticsDriver =
      widget.interactionHapticsDriver ?? MethodChannelInteractionHaptics();
  Timer? _clockTimer;
  late DateTime _now;

  DateTime get _currentNow => (widget.nowProvider ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _currentNow;
    _scheduleClockRefresh();
  }

  @override
  void didUpdateWidget(covariant PetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nowProvider, widget.nowProvider)) {
      _now = _currentNow;
      _scheduleClockRefresh();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _scheduleClockRefresh() {
    _clockTimer?.cancel();
    final nextMinute = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute + 1,
    );
    final delay = nextMinute.difference(_now);
    _clockTimer = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      _handleClockRefresh,
    );
  }

  void _handleClockRefresh() {
    if (!mounted) {
      return;
    }
    setState(() {
      _now = _currentNow;
    });
    _scheduleClockRefresh();
  }

  Future<void> _confirmDeletePet(Pet pet) async {
    final photoPath = pet.photoPath;
    final petsBeforeDelete = List<Pet>.from(widget.store.pets);
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (context) {
        final tokens = context.petNoteTokens;
        final dialogSurfaceColor =
            tokens.panelStrongBackground.withValues(alpha: 1);
        return Dialog(
          backgroundColor: dialogSurfaceColor,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Material(
            key: const ValueKey('delete-pet-dialog-surface'),
            color: dialogSurfaceColor,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '删除「${pet.name}」？',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: tokens.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '删除后，这只爱宠的档案、待办、提醒和记录都会一起移除，无法恢复。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.secondaryText,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('delete-pet-dialog-info-panel'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: dialogSurfaceColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF2D3B4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_rounded,
                          color: Color(0xFFD9822B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '如果只是想暂时不看这只宠物，可以先保留资料。',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF9A5B13),
                                      height: 1.4,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF2A65A),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('确认删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    await widget.store.deletePet(pet.id);
    if (photoPath != null &&
        !_isPhotoPathReferencedByOtherPets(
          photoPath,
          petsBeforeDelete,
          pet.id,
        )) {
      unawaited(_nativePetPhotoPicker.deletePetPhoto(photoPath));
    }
  }

  bool _isPhotoPathReferencedByOtherPets(
    String path,
    List<Pet> pets,
    String deletedPetId,
  ) {
    return pets
        .any((item) => item.id != deletedPetId && item.photoPath == path);
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.store.selectedPet;
    final recordsForSelectedPet = widget.store.recordsForSelectedPet;
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        PageHeader(
          title: '爱宠',
          subtitle: _petsPageSubtitle(widget.store.pets.length),
          trailing: pet == null
              ? null
              : RemoteVideoPillButton(
                  pet: pet,
                  permissionCoordinator:
                      widget.remoteVideoPermissionCoordinator,
                ),
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
              return _PetSelectorCard(
                pet: item,
                selected: selected,
                now: _now,
                onTap: () => widget.store.selectPet(item.id),
                onLongPressCompleted: () => _confirmDeletePet(item),
                interactionHapticsDriver: _interactionHapticsDriver,
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
            subtitle: petProfileSummary(pet, _now, includeWeight: true),
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
                                label: '资料记录',
                                value: '${recordsForSelectedPet.length}',
                                background: const Color(0xFFF5F0FF),
                                foreground: const Color(0xFF6B51C9),
                                trailing: const _RecordsFolderMetricIcon(),
                                valueTextStyle: const TextStyle(
                                  fontSize: 60,
                                  height: 0.88,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -2.2,
                                ),
                                valueLabelSpacing: 2,
                                contentAlignment: MetricContentAlignment.center,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) => PetDetailsPage(
                                        store: widget.store,
                                        pet: pet,
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

class _PetSelectorCard extends StatefulWidget {
  const _PetSelectorCard({
    required this.pet,
    required this.selected,
    required this.now,
    required this.onTap,
    required this.onLongPressCompleted,
    required this.interactionHapticsDriver,
  });

  final Pet pet;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;
  final Future<void> Function() onLongPressCompleted;
  final InteractionHapticsDriver interactionHapticsDriver;

  @override
  State<_PetSelectorCard> createState() => _PetSelectorCardState();
}

class _PetSelectorCardState extends State<_PetSelectorCard> {
  static const _holdDuration = Duration(milliseconds: 560);
  static const _holdCancelMoveDistance = 12.0;

  Timer? _holdTimer;
  Offset? _holdStartPosition;
  bool _holdCompleted = false;
  bool _suppressNextTap = false;
  double _holdProgressTarget = 0;

  @override
  void dispose() {
    _holdTimer?.cancel();
    unawaited(widget.interactionHapticsDriver.stopDeleteHoldRamp());
    super.dispose();
  }

  void _startHoldProgress() {
    _holdTimer?.cancel();
    setState(() {
      _holdCompleted = false;
      _holdProgressTarget = 1;
    });
    unawaited(widget.interactionHapticsDriver.playDeleteHoldRamp(
      durationMs: _holdDuration.inMilliseconds,
    ));
    _holdTimer = Timer(_holdDuration, _completeHold);
  }

  void _cancelHoldProgress() {
    if (_holdCompleted || _holdStartPosition == null) {
      return;
    }
    _holdTimer?.cancel();
    unawaited(widget.interactionHapticsDriver.stopDeleteHoldRamp());
    _holdStartPosition = null;
    setState(() {
      _holdProgressTarget = 0;
    });
  }

  void _completeHold() {
    if (!mounted || _holdCompleted) {
      return;
    }
    setState(() {
      _holdCompleted = true;
      _suppressNextTap = true;
      _holdProgressTarget = 1;
    });
    unawaited(_playCompletionHaptics());
    _holdStartPosition = null;
    widget.onLongPressCompleted().whenComplete(() {
      if (mounted) {
        setState(() {
          _holdCompleted = false;
          _holdProgressTarget = 0;
        });
      }
    });
  }

  Future<void> _playCompletionHaptics() async {
    await widget.interactionHapticsDriver.stopDeleteHoldRamp();
    await widget.interactionHapticsDriver.playDeleteConfirmImpact();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final pet = widget.pet;
    final borderRadius = BorderRadius.circular(26);
    final fillColor = selected
        ? Colors.white.withValues(alpha: 0.34)
        : const Color(0xFFF2A65A).withValues(alpha: 0.32);

    return Semantics(
      button: true,
      label: '宠物 ${pet.name}，长按删除',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _holdStartPosition = event.position;
          _startHoldProgress();
        },
        onPointerMove: (event) {
          final startPosition = _holdStartPosition;
          if (startPosition == null || _holdCompleted) {
            return;
          }
          if ((event.position - startPosition).distance >
              _holdCancelMoveDistance) {
            _cancelHoldProgress();
          }
        },
        onPointerUp: (_) => _cancelHoldProgress(),
        onPointerCancel: (_) => _cancelHoldProgress(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_suppressNextTap) {
              _suppressNextTap = false;
              return;
            }
            widget.onTap();
          },
          child: AnimatedContainer(
            key: ValueKey('pet-selector-card-${pet.id}'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color:
                  selected ? const Color(0xFFF2A65A) : const Color(0xF4FFFFFF),
              borderRadius: borderRadius,
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        end: _holdProgressTarget,
                      ),
                      duration: _holdDuration,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return FractionallySizedBox(
                          key: ValueKey('pet-selector-hold-progress-${pet.id}'),
                          alignment: Alignment.centerLeft,
                          widthFactor: value,
                          child: child,
                        );
                      },
                      child: ColoredBox(color: fillColor),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        PetPhotoAvatar(
                          photoPath: pet.photoPath,
                          fallbackText: pet.avatarText,
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
                              pet.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF17181C),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _petSelectorSubtitle(pet, widget.now),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _petSelectorSubtitle(Pet pet, DateTime now) {
  final age = petAgeLabel(pet, now);
  if (age.isNotEmpty) {
    return age;
  }
  return pet.breed;
}

String _petsPageSubtitle(int petCount) {
  if (petCount == 0) {
    return '添加宠物就有照护档案啦';
  }
  return petCount == 1 ? '它的照护档案' : '它们的照护档案';
}

class _RecordsFolderMetricIcon extends StatelessWidget {
  const _RecordsFolderMetricIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('records-folder-metric-icon'),
      width: 138,
      height: 104,
      child: Image.asset(
        'assets/images/records-folder.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
