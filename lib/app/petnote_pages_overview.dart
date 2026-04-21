part of 'petnote_pages.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    required this.bottomCtaController,
    this.aiInsightsService,
    this.onOpenAiSettings,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final OverviewBottomCtaController bottomCtaController;
  final AiInsightsService? aiInsightsService;
  final FutureOr<void> Function()? onOpenAiSettings;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  static final Expando<bool> _providerAvailabilityCache =
      Expando<bool>('overview_provider_availability');
  static const Duration _errorRetryButtonDelay = Duration(milliseconds: 480);

  bool _hasActiveProvider = false;
  int _providerCheckSerial = 0;
  Timer? _errorRetryButtonTimer;
  String? _pendingErrorRetryKey;
  bool _showErrorRetryButton = false;
  int _bottomCtaSyncSerial = 0;

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
  void dispose() {
    _errorRetryButtonTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final pagePadding =
            pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
        if (widget.store.pets.isEmpty) {
          _scheduleBottomCtaSync(null);
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
        final showGenerationError = _shouldShowOverviewGenerationError(
          reportState,
        );
        _syncErrorRetryButtonVisibility(
          showGenerationError: showGenerationError,
          requestKey: reportState.requestKey,
        );
        final selectedPetIds =
            widget.store.overviewAnalysisConfig.selectedPetIds.toSet();
        final hasSelectedPets = selectedPetIds.isNotEmpty;
        final showGeneratingExperience =
            reportState.isLoading && _hasActiveProvider && hasSelectedPets;
        final listBottomPadding = showGenerationSetup || showGenerationError
            ? overviewBottomCtaContentReserve
            : 0.0;
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
        final overviewHeader = PageHeader(
          title: '总览',
          subtitle:
              showGenerationSetup ? '你的AI关怀助理' : _overviewTitle(snapshot.range),
          trailing: showGenerationSetup
              ? _OverviewSetupHeaderActions(
                  config: widget.store.overviewAnalysisConfig,
                  referenceDate: widget.store.referenceNow,
                  onOpenAiSettings: widget.onOpenAiSettings == null
                      ? null
                      : _handleOpenAiSettings,
                  onSelectRange: _selectOverviewRangeFromSetup,
                  onSelectCustomRange: _applyCustomOverviewDateRange,
                )
              : reportState.isLoading
                  ? const _OverviewGeneratingHeaderActions()
                      : showGenerationError
                          ? null
                      : (_hasActiveProvider || reportState.hasReport)
                          ? _OverviewHeaderActions(
                              isLoading: reportState.isLoading,
                              canGenerate: hasSelectedPets,
                              hasReport: reportState.hasReport,
                              onOpenAiSettings: widget.onOpenAiSettings == null
                                  ? null
                                  : _handleOpenAiSettings,
                              onGenerate: reportState.hasReport
                                  ? _returnToOverviewSetup
                                  : () => _generateCareReport(
                                        forceRefresh: false,
                                      ),
                            )
                          : null,
        );
        _scheduleBottomCtaSync(
          _buildBottomCtaState(
            showGenerationSetup: showGenerationSetup,
            showGenerationError: showGenerationError,
            hasSelectedPets: hasSelectedPets,
          ),
        );
        return ListView(
          padding: pagePadding.copyWith(
            bottom: pagePadding.bottom + listBottomPadding,
          ),
          children: [
            overviewHeader,
            _OverviewBodyTransition(child: overviewBody),
          ],
        );
      },
    );
  }

  void _scheduleBottomCtaSync(OverviewBottomCtaState? nextState) {
    _bottomCtaSyncSerial += 1;
    final syncSerial = _bottomCtaSyncSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || syncSerial != _bottomCtaSyncSerial) {
        return;
      }
      widget.bottomCtaController.update(nextState);
    });
  }

  OverviewBottomCtaState? _buildBottomCtaState({
    required bool showGenerationSetup,
    required bool showGenerationError,
    required bool hasSelectedPets,
  }) {
    if (showGenerationError) {
      return OverviewBottomCtaState(
        visible: _showErrorRetryButton,
        enabled: true,
        label: '返回重试',
        icon: Icons.arrow_back_rounded,
        onPressed: _returnToOverviewSetup,
      );
    }
    if (!showGenerationSetup) {
      return null;
    }
    return OverviewBottomCtaState(
      visible: true,
      enabled: _hasActiveProvider && hasSelectedPets,
      label: '生成总览',
      icon: Icons.auto_awesome_rounded,
      onPressed: _hasActiveProvider && hasSelectedPets
          ? () => _generateCareReport(forceRefresh: false)
          : null,
    );
  }

  bool _shouldShowOverviewGenerationSetup(
    OverviewAiReportState reportState,
  ) {
    return !reportState.hasReport &&
        !reportState.isLoading &&
        !(reportState.hasRequested && reportState.errorMessage != null);
  }

  bool _shouldShowOverviewGenerationError(
    OverviewAiReportState reportState,
  ) {
    return !reportState.hasReport &&
        !reportState.isLoading &&
        reportState.hasRequested &&
        reportState.errorMessage != null;
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
          _AiCareReportOverview(
            report: reportState.report!,
            pets: widget.store.pets,
          ),
        ],
      );
    }

    if (reportState.hasRequested && reportState.errorMessage != null) {
      return _OverviewGeneratingExperience(
        key: const ValueKey('overview-generation-error-experience'),
        pets: selectedPets,
        mode: _OverviewGenerationExperienceMode.error,
        errorMessage: reportState.errorMessage,
      );
    }

    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    return _OverviewBodySection(
      key: const ValueKey('overview-body-fallback'),
      children: _buildOverviewFallbackSections(snapshot, theme, tokens),
    );
  }

  Future<void> _returnToOverviewSetup() async {
    await widget.store.clearOverviewAiHistory();
  }

  void _syncErrorRetryButtonVisibility({
    required bool showGenerationError,
    required String? requestKey,
  }) {
    final errorKey = showGenerationError ? requestKey ?? 'error' : null;
    if (errorKey != null) {
      if (_pendingErrorRetryKey == errorKey) {
        return;
      }
      _pendingErrorRetryKey = errorKey;
      _errorRetryButtonTimer?.cancel();
      if (_showErrorRetryButton) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _pendingErrorRetryKey != errorKey) {
            return;
          }
          setState(() {
            _showErrorRetryButton = false;
          });
        });
      }
      _errorRetryButtonTimer = Timer(_errorRetryButtonDelay, () {
        if (!mounted || _pendingErrorRetryKey != errorKey) {
          return;
        }
        setState(() {
          _showErrorRetryButton = true;
        });
      });
      return;
    }

    if (_pendingErrorRetryKey == null && !_showErrorRetryButton) {
      return;
    }
    _pendingErrorRetryKey = null;
    _errorRetryButtonTimer?.cancel();
    if (_showErrorRetryButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pendingErrorRetryKey != null) {
          return;
        }
        setState(() {
          _showErrorRetryButton = false;
        });
      });
    }
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

  Future<void> _selectOverviewRangeFromSetup(OverviewRange range) async {
    final currentConfig = widget.store.overviewAnalysisConfig;
    final selectedPetIds = currentConfig.selectedPetIds;
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

  Future<void> _applyCustomOverviewDateRange(DateTimeRange range) async {
    widget.store.updateOverviewAnalysisConfig(
      range: OverviewRange.custom,
      selectedPetIds: widget.store.overviewAnalysisConfig.selectedPetIds,
      customRangeStart: range.start,
      customRangeEnd: range.end,
    );
  }

  void _toggleOverviewPetFromSetup(String petId, bool selected) {
    final currentConfig = widget.store.overviewAnalysisConfig;
    final selectedPetIds = currentConfig.selectedPetIds.toSet();
    if (selected) {
      selectedPetIds.add(petId);
    } else {
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
    widget.store.updateOverviewAnalysisConfig(
      range: widget.store.overviewAnalysisConfig.range,
      selectedPetIds: const [],
      customRangeStart: widget.store.overviewAnalysisConfig.customRangeStart,
      customRangeEnd: widget.store.overviewAnalysisConfig.customRangeEnd,
    );
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
    if (widget.store.overviewAnalysisConfig.selectedPetIds.isEmpty) {
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
