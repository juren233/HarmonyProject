part of 'petnote_pages.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    this.aiInsightsService,
    this.onOpenAiSettings,
    this.nativeOptionPicker,
    this.iosRangeButtonBuilder,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final AiInsightsService? aiInsightsService;
  final FutureOr<void> Function()? onOpenAiSettings;
  final NativeOptionPicker? nativeOptionPicker;
  final IosOverviewRangeButtonBuilder? iosRangeButtonBuilder;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  static final Expando<bool> _providerAvailabilityCache =
      Expando<bool>('overview_provider_availability');

  bool _hasActiveProvider = false;
  int _providerCheckSerial = 0;

  @override
  void initState() {
    super.initState();
    final cachedAvailability = widget.aiInsightsService == null
        ? null
        : _providerAvailabilityCache[widget.aiInsightsService!];
    if (cachedAvailability != null) {
      _hasActiveProvider = cachedAvailability;
    }
    _refreshProviderAvailability();
  }

  @override
  void didUpdateWidget(covariant OverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.aiInsightsService, widget.aiInsightsService)) {
      _refreshProviderAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final pagePadding =
            pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
        if (widget.store.pets.isEmpty) {
          return ListView(
            padding: pagePadding,
            children: [
              const PageHeader(
                title: '总览',
                subtitle: '先添加宠物，AI 照护总结才会开始积累',
              ),
              PageEmptyStateBlock(
                heroTitle: '等第一份档案建立后再开始总结',
                heroSubtitle: '当前还没有宠物资料、提醒或记录。先完成第一只爱宠建档，后续的照护观察会自动收拢到这里。',
                emptyTitle: '先添加第一只爱宠',
                emptySubtitle: '有了基础档案后，这里才会生成更贴近日常的总结内容。',
                actionLabel: '开始添加宠物',
                onAction: widget.onAddFirstPet,
              ),
            ],
          );
        }

        final snapshot = widget.store.overviewSnapshot;
        final reportState = widget.store.overviewAiReportState;
        final showGenerationSetup =
            _shouldShowOverviewGenerationSetup(reportState);
        final showGeneratingExperience = reportState.isLoading &&
            _hasActiveProvider &&
            widget.store.overviewAnalysisConfig.selectedPetIds.isNotEmpty;
        final viewPadding = MediaQuery.viewPaddingOf(context);
        final dockLayout = dockLayoutForInsets(viewPadding);
        final floatingButtonBottom =
            Theme.of(context).platform == TargetPlatform.iOS
                ? viewPadding.bottom +
                    iosNativeDockHostHeight +
                    overviewFloatingButtonDockClearance
                : viewPadding.bottom +
                    dockLayout.shellHeight +
                    dockLayout.outerMargin.bottom -
                    4;
        final listBottomPadding = showGenerationSetup ? 116.0 : 0.0;
        final selectedPetIds =
            widget.store.overviewAnalysisConfig.selectedPetIds.isEmpty
                ? widget.store.pets.map((pet) => pet.id).toSet()
                : widget.store.overviewAnalysisConfig.selectedPetIds.toSet();
        final selectedPets = widget.store.pets
            .where((pet) => selectedPetIds.contains(pet.id))
            .toList(growable: false);
        final overviewBody = _buildOverviewBody(
          context: context,
          snapshot: snapshot,
          reportState: reportState,
          showGenerationSetup: showGenerationSetup,
          showGeneratingExperience: showGeneratingExperience,
          selectedPets: selectedPets,
        );
        return Stack(
          children: [
            ListView(
              padding: pagePadding.copyWith(
                bottom: pagePadding.bottom + listBottomPadding,
              ),
              children: [
                PageHeader(
                  title: '总览',
                  subtitle: showGenerationSetup
                      ? '你的AI关怀助理'
                      : _overviewTitle(snapshot.range),
                  trailing: showGenerationSetup
                      ? _OverviewRangeActionButton(
                          config: widget.store.overviewAnalysisConfig,
                          nativeOptionPicker: widget.nativeOptionPicker,
                          iosRangeButtonBuilder: widget.iosRangeButtonBuilder,
                          onSelectRange: _selectOverviewRangeFromSetup,
                        )
                      : reportState.isLoading
                          ? _OverviewGeneratingHeaderActions(
                              onOpenConfig: _openOverviewConfig,
                            )
                          : _hasActiveProvider
                              ? _OverviewHeaderActions(
                                  isLoading: reportState.isLoading,
                                  onOpenConfig: _openOverviewConfig,
                                  onGenerate: () => _generateCareReport(
                                    forceRefresh: reportState.hasReport,
                                  ),
                                )
                              : null,
                ),
                _OverviewBodyTransition(child: overviewBody),
              ],
            ),
            if (showGenerationSetup)
              Positioned(
                left: 22,
                right: 22,
                bottom: floatingButtonBottom,
                child: FilledButton.icon(
                  key: const ValueKey('overview-floating-generate-button'),
                  onPressed: _hasActiveProvider
                      ? () => _generateCareReport(forceRefresh: false)
                      : null,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor:
                        tabAccentFor(context, AppTab.overview).label,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFB8BCC6),
                    disabledForegroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('生成总览'),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _shouldShowOverviewGenerationSetup(
    OverviewAiReportState reportState,
  ) {
    return !reportState.hasReport &&
        !reportState.isLoading &&
        !(reportState.hasRequested && reportState.errorMessage != null);
  }

  Widget _buildOverviewBody({
    required BuildContext context,
    required OverviewSnapshot snapshot,
    required OverviewAiReportState reportState,
    required bool showGenerationSetup,
    required bool showGeneratingExperience,
    required List<Pet> selectedPets,
  }) {
    if (showGenerationSetup) {
      return _OverviewBodySection(
        key: const ValueKey('overview-body-setup'),
        children: [
          _OverviewGenerationSetup(
            config: widget.store.overviewAnalysisConfig,
            pets: widget.store.pets,
            hasActiveProvider: _hasActiveProvider,
            onOpenAiSettings:
                widget.onOpenAiSettings == null ? null : _handleOpenAiSettings,
            onTogglePet: _toggleOverviewPetFromSetup,
            onToggleSelectAll: _toggleOverviewSelectAllFromSetup,
          ),
        ],
      );
    }

    if (showGeneratingExperience) {
      return _OverviewBodySection(
        key: const ValueKey('overview-body-generating'),
        children: [
          _OverviewGeneratingExperience(
            key: const ValueKey('overview-generating-experience'),
            pets: selectedPets,
          ),
        ],
      );
    }

    if (reportState.hasReport && reportState.report != null) {
      return _OverviewBodySection(
        key: const ValueKey('overview-body-report'),
        children: [
          _AiCareReportOverview(report: reportState.report!),
        ],
      );
    }

    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    if (reportState.hasRequested && reportState.errorMessage != null) {
      return _OverviewBodySection(
        key: const ValueKey('overview-body-error'),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _overviewStatusText(reportState),
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.secondaryText,
                height: 1.5,
              ),
            ),
          ),
          SectionCard(
            title: 'AI 总览',
            children: [
              Text(
                reportState.errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFC7533E),
                  height: 1.6,
                ),
              ),
              Text(
                '已自动回退到本地规则总结，方便你先继续查看当前周期的照护概况。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.secondaryText,
                  height: 1.6,
                ),
              ),
            ],
          ),
          ..._buildOverviewFallbackSections(snapshot, theme, tokens),
        ],
      );
    }

    return _OverviewBodySection(
      key: const ValueKey('overview-body-fallback'),
      children: _buildOverviewFallbackSections(snapshot, theme, tokens),
    );
  }

  List<Widget> _buildOverviewFallbackSections(
    OverviewSnapshot snapshot,
    ThemeData theme,
    PetNoteThemeTokens tokens,
  ) {
    return [
      ...snapshot.sections.map(
        (section) => SectionCard(
          title: section.title,
          children:
              section.items.map((item) => BulletText(text: item)).toList(),
        ),
      ),
      SectionCard(
        title: '说明',
        children: [
          Text(
            snapshot.disclaimer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.secondaryText,
              height: 1.6,
            ),
          ),
        ],
      ),
    ];
  }

  String _overviewStatusText(OverviewAiReportState reportState) {
    if (reportState.isLoading) {
      return '';
    }
    if (reportState.hasReport) {
      return '当前展示的是已选宠物与当前时间范围下的综合总览，仅供照护参考。';
    }
    if (reportState.hasRequested && reportState.errorMessage != null) {
      return 'AI 总览生成失败，当前展示本地规则总结。';
    }
    if (_hasActiveProvider) {
      return '先用配置按钮确认时间范围和宠物，再生成高密度总览。';
    }
    return '未检测到可用 AI 配置，当前展示本地规则总结。';
  }

  Future<void> _openOverviewConfig() async {
    final currentConfig = widget.store.overviewAnalysisConfig;
    var selectedRange = currentConfig.range;
    var customRangeStart = currentConfig.customRangeStart;
    var customRangeEnd = currentConfig.customRangeEnd;
    final selectedPetIds = currentConfig.selectedPetIds.toSet();
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('总览配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('时间范围'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in const [
                          OverviewRange.sevenDays,
                          OverviewRange.oneMonth,
                          OverviewRange.threeMonths,
                          OverviewRange.sixMonths,
                          OverviewRange.oneYear,
                          OverviewRange.custom,
                        ])
                          ChoiceChip(
                            label: Text(_overviewRangeChipLabel(option)),
                            selected: selectedRange == option,
                            onSelected: (_) async {
                              if (option == OverviewRange.custom) {
                                final now = widget.store.referenceNow;
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(now.year - 2, 1, 1),
                                  lastDate: DateTime(now.year + 1, 12, 31),
                                  initialDateRange: DateTimeRange(
                                    start: customRangeStart ??
                                        now.subtract(const Duration(days: 7)),
                                    end: customRangeEnd ?? now,
                                  ),
                                  locale: const Locale('zh', 'CN'),
                                );
                                if (picked == null) {
                                  return;
                                }
                                setDialogState(() {
                                  selectedRange = option;
                                  customRangeStart = picked.start;
                                  customRangeEnd = picked.end;
                                });
                                return;
                              }
                              setDialogState(() {
                                selectedRange = option;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('分析宠物'),
                    const SizedBox(height: 10),
                    ...widget.store.pets.map(
                      (pet) => CheckboxListTile(
                        value: selectedPetIds.contains(pet.id),
                        title: Text(pet.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value ?? false) {
                              selectedPetIds.add(pet.id);
                            } else if (selectedPetIds.length > 1) {
                              selectedPetIds.remove(pet.id);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('应用配置'),
                ),
              ],
            );
          },
        );
      },
    );
    if (applied != true || !mounted) {
      return;
    }
    widget.store.updateOverviewAnalysisConfig(
      range: selectedRange,
      selectedPetIds: selectedPetIds.toList(growable: false),
      customRangeStart: customRangeStart,
      customRangeEnd: customRangeEnd,
    );
  }

  Future<void> _selectOverviewRangeFromSetup(OverviewRange range) async {
    final currentConfig = widget.store.overviewAnalysisConfig;
    final selectedPetIds = _effectiveOverviewSelectedPetIds(currentConfig);
    if (range == OverviewRange.custom) {
      final picked = await _pickCustomOverviewDateRange(
        currentConfig.customRangeStart,
        currentConfig.customRangeEnd,
      );
      if (picked == null) {
        return;
      }
      widget.store.updateOverviewAnalysisConfig(
        range: OverviewRange.custom,
        selectedPetIds: selectedPetIds,
        customRangeStart: picked.start,
        customRangeEnd: picked.end,
      );
      return;
    }
    widget.store.updateOverviewAnalysisConfig(
      range: range,
      selectedPetIds: selectedPetIds,
      customRangeStart: currentConfig.customRangeStart,
      customRangeEnd: currentConfig.customRangeEnd,
    );
  }

  void _toggleOverviewPetFromSetup(String petId, bool selected) {
    final currentConfig = widget.store.overviewAnalysisConfig;
    final selectedPetIds =
        _effectiveOverviewSelectedPetIds(currentConfig).toSet();
    if (selected) {
      selectedPetIds.add(petId);
    } else if (selectedPetIds.length > 1) {
      selectedPetIds.remove(petId);
    }
    widget.store.updateOverviewAnalysisConfig(
      range: currentConfig.range,
      selectedPetIds: selectedPetIds.toList(growable: false),
      customRangeStart: currentConfig.customRangeStart,
      customRangeEnd: currentConfig.customRangeEnd,
    );
  }

  void _toggleOverviewSelectAllFromSetup(bool selected) {
    if (selected) {
      widget.store.updateOverviewAnalysisConfig(
        range: widget.store.overviewAnalysisConfig.range,
        selectedPetIds:
            widget.store.pets.map((pet) => pet.id).toList(growable: false),
        customRangeStart: widget.store.overviewAnalysisConfig.customRangeStart,
        customRangeEnd: widget.store.overviewAnalysisConfig.customRangeEnd,
      );
      return;
    }
    if (widget.store.pets.isEmpty) {
      return;
    }
    widget.store.updateOverviewAnalysisConfig(
      range: widget.store.overviewAnalysisConfig.range,
      selectedPetIds: [widget.store.pets.first.id],
      customRangeStart: widget.store.overviewAnalysisConfig.customRangeStart,
      customRangeEnd: widget.store.overviewAnalysisConfig.customRangeEnd,
    );
  }

  List<String> _effectiveOverviewSelectedPetIds(
    OverviewAnalysisConfig config,
  ) {
    if (config.selectedPetIds.isEmpty) {
      return widget.store.pets.map((pet) => pet.id).toList(growable: false);
    }
    return config.selectedPetIds;
  }

  Future<DateTimeRange?> _pickCustomOverviewDateRange(
    DateTime? currentStart,
    DateTime? currentEnd,
  ) {
    final now = widget.store.referenceNow;
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: currentStart ?? now.subtract(const Duration(days: 7)),
        end: currentEnd ?? now,
      ),
      locale: const Locale('zh', 'CN'),
    );
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

    final requestSerial = ++_providerCheckSerial;
    bool hasProvider = false;
    try {
      hasProvider = await service.hasActiveProvider();
    } catch (_) {
      hasProvider = false;
    }
    if (!mounted || requestSerial != _providerCheckSerial) {
      return;
    }
    _providerAvailabilityCache[service] = hasProvider;
    setState(() {
      _hasActiveProvider = hasProvider;
    });
  }

  Future<void> _handleOpenAiSettings() async {
    final openAiSettings = widget.onOpenAiSettings;
    if (openAiSettings == null) {
      return;
    }
    await openAiSettings();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await _refreshProviderAvailability();
  }

  Future<void> _generateCareReport({required bool forceRefresh}) async {
    final service = widget.aiInsightsService;
    if (service == null || widget.store.overviewAiReportState.isLoading) {
      return;
    }

    await widget.store.generateOverviewAiReport(
      (context, {forceRefresh = false}) => service.generateCareReport(
        context,
        forceRefresh: forceRefresh,
      ),
      forceRefresh: forceRefresh,
    );
  }
}
