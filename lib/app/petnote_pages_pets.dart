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
  _VisitSummaryRange _selectedVisitRange = _VisitSummaryRange.thirtyDays;
  DateTimeRange? _customDateRange;
  AiVisitSummary? _visitSummary;
  String? _visitErrorMessage;
  bool _visitLoading = false;
  bool _hasActiveProvider = false;

  @override
  void initState() {
    super.initState();
    _refreshProviderAvailability();
  }

  @override
  void didUpdateWidget(covariant PetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.aiInsightsService, widget.aiInsightsService)) {
      _refreshProviderAvailability();
    }
  }

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
                        foregroundColor: selected
                            ? Colors.white
                            : const Color(0xFF335FCA),
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
            child: Row(
              children: [
                if (hasPetPhoto(pet.photoPath)) ...[
                  PetPhotoSquare(photoPath: pet.photoPath, size: 96),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: MetricOverview(
                    metrics: [
                      MetricItem(
                        label: '近期提醒',
                        value: '${remindersForSelectedPet.length}',
                        background: const Color(0xFFEAF0FF),
                        foreground: const Color(0xFF335FCA),
                      ),
                      MetricItem(
                        label: '资料记录',
                        value: '${recordsForSelectedPet.length}',
                        background: const Color(0xFFF5F0FF),
                        foreground: const Color(0xFF6B51C9),
                      ),
                    ],
                  ),
                ),
              ],
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
          SectionCard(
            title: '近期提醒',
            children: remindersForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无提醒',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : remindersForSelectedPet
                    .map(
                      (item) => StatusListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.scheduledAt)} · ${item.recurrence}',
                        leadingIcon: Icons.notifications_active_rounded,
                        leadingBackgroundColor: const Color(0xFFFFF1DD),
                        leadingIconColor: const Color(0xFFF2A65A),
                        trailing: HyperBadge(
                          text: _reminderKindLabel(item.kind),
                          foreground: const Color(0xFFC57A14),
                          background: const Color(0xFFFFF1DD),
                        ),
                      ),
                    )
                    .toList(),
          ),
          SectionCard(
            title: '资料记录',
            children: recordsForSelectedPet.isEmpty
                ? [
                    Text(
                      '暂无资料记录',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6C7280)),
                    ),
                  ]
                : recordsForSelectedPet
                    .map(
                      (item) => StatusListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.recordDate, withTime: false)} · ${item.summary}',
                        leadingIcon: Icons.description_rounded,
                        leadingBackgroundColor: const Color(0xFFE8F7EE),
                        leadingIconColor: const Color(0xFF4FB57C),
                        trailing: HyperBadge(
                          text: _recordTypeLabel(item.type),
                          foreground: const Color(0xFF2F8F5B),
                          background: const Color(0xFFE8F7EE),
                        ),
                      ),
                    )
                    .toList(),
          ),
          SectionCard(
            title: 'AI 看诊摘要',
            children: [
              HyperSegmentedControl(
                items: const [
                  SegmentItem(key: 'thirtyDays', label: '近30天'),
                  SegmentItem(key: 'ninetyDays', label: '近90天'),
                  SegmentItem(key: 'custom', label: '自定义'),
                ],
                selectedKey: _selectedVisitRange.name,
                onChanged: _onVisitRangeChanged,
              ),
              if (_selectedVisitRange == _VisitSummaryRange.custom)
                StatusListRow(
                  title: '自定义区间',
                  subtitle: _customDateRange == null
                      ? '尚未选择时间范围'
                      : '${formatDate(_customDateRange!.start, withTime: false)} 至 ${formatDate(_customDateRange!.end, withTime: false)}',
                  leadingIcon: Icons.date_range_rounded,
                  leadingBackgroundColor: const Color(0xFFEAF0FF),
                  leadingIconColor: const Color(0xFF335FCA),
                  trailing: TextButton(
                    onPressed: _pickCustomDateRange,
                    child: const Text('选择区间'),
                  ),
                )
              else
                Text(
                  _selectedVisitRange == _VisitSummaryRange.thirtyDays
                      ? '按最近 30 天的提醒、待办和资料记录生成摘要。'
                      : '按最近 90 天的提醒、待办和资料记录生成摘要。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.petNoteTokens.secondaryText,
                        height: 1.55,
                      ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _canGenerateVisitSummary(pet)
                        ? _generateVisitSummary
                        : null,
                    child: Text(
                      _visitSummary == null ? '生成看诊摘要' : '重新生成看诊摘要',
                    ),
                  ),
                  Text(
                    _visitStatusText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.petNoteTokens.secondaryText,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
              if (_visitLoading)
                const InlineLoadingMessage(message: '正在整理时间线、检查结果和就诊问题…'),
              if (_visitErrorMessage != null)
                Text(
                  _visitErrorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFC7533E),
                        height: 1.6,
                      ),
                ),
              if (_visitSummary != null) ...[
                Text(
                  _visitSummary!.visitReason,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.petNoteTokens.primaryText,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                TitledBulletGroup(
                  title: '关键时间线',
                  items: _visitSummary!.timeline,
                ),
                TitledBulletGroup(
                  title: '用药 / 护理 / 处置',
                  items: _visitSummary!.medicationsAndTreatments,
                ),
                TitledBulletGroup(
                  title: '检查与结果',
                  items: _visitSummary!.testsAndResults,
                ),
                TitledBulletGroup(
                  title: '建议问医生',
                  items: _visitSummary!.questionsToAskVet,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  bool _canGenerateVisitSummary(Pet? pet) {
    if (pet == null || _visitLoading || !_hasActiveProvider) {
      return false;
    }
    if (_selectedVisitRange == _VisitSummaryRange.custom) {
      return _customDateRange != null;
    }
    return true;
  }

  String _visitStatusText() {
    if (_visitLoading) {
      return 'AI 正在整理当前宠物的就诊摘要…';
    }
    if (_visitSummary != null) {
      return '摘要仅供就诊准备和记录整理参考，不替代专业诊疗建议。';
    }
    if (_hasActiveProvider) {
      return '支持近 30 天、近 90 天和自定义区间。';
    }
    return '配置 AI 后可生成可读的时间线和就诊问题清单。';
  }

  Future<void> _refreshProviderAvailability() async {
    final service = widget.aiInsightsService;
    if (service == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasActiveProvider = false;
      });
      return;
    }
    bool hasProvider = false;
    try {
      hasProvider = await service.hasActiveProvider();
    } catch (_) {
      hasProvider = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasActiveProvider = hasProvider;
    });
  }

  Future<void> _onVisitRangeChanged(String key) async {
    final nextRange = switch (key) {
      'ninetyDays' => _VisitSummaryRange.ninetyDays,
      'custom' => _VisitSummaryRange.custom,
      _ => _VisitSummaryRange.thirtyDays,
    };
    if (nextRange == _VisitSummaryRange.custom) {
      await _pickCustomDateRange();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedVisitRange = nextRange;
      _visitSummary = null;
      _visitErrorMessage = null;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customDateRange,
      locale: const Locale('zh', 'CN'),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      _selectedVisitRange = _VisitSummaryRange.custom;
      _customDateRange = picked;
      _visitSummary = null;
      _visitErrorMessage = null;
    });
  }

  Future<void> _generateVisitSummary() async {
    final service = widget.aiInsightsService;
    final pet = widget.store.selectedPet;
    if (service == null || pet == null) {
      return;
    }

    final context = _buildVisitContext(
      widget.store,
      pet,
      _selectedVisitRange,
      customDateRange: _customDateRange,
    );
    setState(() {
      _visitLoading = true;
      _visitErrorMessage = null;
    });

    try {
      final summary = await service.generateVisitSummary(
        context,
        forceRefresh: _visitSummary != null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _visitSummary = summary;
        _visitLoading = false;
      });
    } on AiGenerationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visitSummary = null;
        _visitErrorMessage = error.message;
        _visitLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visitSummary = null;
        _visitErrorMessage = 'AI 看诊摘要暂时无法生成，请稍后重试。';
        _visitLoading = false;
      });
    }
  }
}
