import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/navigation_palette.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';

class ChecklistPage extends StatelessWidget {
  const ChecklistPage({
    super.key,
    required this.store,
    required this.activeSectionKey,
    required this.highlightedChecklistItemKey,
    required this.onSectionChanged,
    required this.onAddFirstPet,
  });

  final PetNoteStore store;
  final String activeSectionKey;
  final String? highlightedChecklistItemKey;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onAddFirstPet;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    if (store.pets.isEmpty) {
      return ListView(
        padding: pagePadding,
        children: [
          const PageHeader(
            title: '清单',
            subtitle: '先建好第一只爱宠，再开始安排照护节奏',
          ),
          const HeroPanel(
            title: '欢迎来到日常照护清单',
            subtitle: '添加第一只爱宠后，这里会开始承接待办、提醒和记录，让每天的事情更顺手。',
            child: SizedBox.shrink(),
          ),
          EmptyCard(
            title: '先添加第一只爱宠',
            subtitle: '建好第一份档案后，清单、提醒和总览都会围绕它展开。',
            actionLabel: '开始添加宠物',
            onAction: onAddFirstPet,
          ),
        ],
      );
    }

    final sections = store.checklistSections;
    final section = sections.firstWhere(
      (item) => item.key == activeSectionKey,
      orElse: () => sections.first,
    );
    final today = _sectionByKey(sections, 'today');
    final upcoming = _sectionByKey(sections, 'upcoming');
    final overdue = _sectionByKey(sections, 'overdue');
    final postponed = _sectionByKey(sections, 'postponed');
    final skipped = _sectionByKey(sections, 'skipped');

    return ListView(
      padding: pagePadding,
      children: [
        PageHeader(
          title: '清单',
          subtitle: '今天 ${today.items.length} 项待处理',
        ),
        HeroPanel(
          title: '今日照护概况',
          subtitle: '关键节点和日常待办都被整理在这里，先把最重要的事情完成掉。',
          child: MetricOverview(
            metrics: [
              MetricItem(
                label: '今日待办',
                value: '${today.items.length}',
                background: const Color(0xFFEAF0FF),
                foreground: const Color(0xFF335FCA),
              ),
              MetricItem(
                label: '即将到期',
                value: '${upcoming.items.length}',
                background: const Color(0xFFFFF3D8),
                foreground: const Color(0xFF976A00),
              ),
              MetricItem(
                label: '已逾期',
                value: '${overdue.items.length}',
                background: const Color(0xFFFDEBE8),
                foreground: const Color(0xFFC7533E),
              ),
            ],
          ),
        ),
        HyperSegmentedControl(
          items: [
            SegmentItem(key: 'today', label: '今日 ${today.summary}'),
            SegmentItem(key: 'upcoming', label: '即将到期 ${upcoming.summary}'),
            SegmentItem(key: 'overdue', label: '已逾期 ${overdue.summary}'),
            SegmentItem(key: 'postponed', label: '已延后 ${postponed.summary}'),
            SegmentItem(key: 'skipped', label: '已跳过 ${skipped.summary}'),
          ],
          selectedKey: activeSectionKey,
          onChanged: onSectionChanged,
        ),
        const SizedBox(height: 18),
        if (section.items.isEmpty)
          const EmptyCard(
            title: '这一栏已经清空了',
            subtitle: '可以点击底部中间的 + 新增待办、提醒或记录，让照护节奏继续保持顺手。',
          )
        else
          ...section.items.map(
            (item) => ChecklistCard(
              key: ValueKey('checklist_card_${item.sourceType}-${item.id}'),
              item: item,
              highlighted: highlightedChecklistItemKey ==
                  '${item.sourceType}:${item.id}',
              onComplete: () =>
                  store.markChecklistDone(item.sourceType, item.id),
              onPostpone: () =>
                  store.postponeChecklist(item.sourceType, item.id),
              onSkip: () => store.skipChecklist(item.sourceType, item.id),
            ),
          ),
      ],
    );
  }
}

ChecklistSection _sectionByKey(
  List<ChecklistSection> sections,
  String key,
) {
  return sections.firstWhere(
    (section) => section.key == key,
    orElse: () => ChecklistSection(
      key: key,
      title: '',
      summary: '0 项',
      items: const [],
    ),
  );
}

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    this.aiInsightsService,
    this.onOpenAiSettings,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final AiInsightsService? aiInsightsService;
  final VoidCallback? onOpenAiSettings;

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
              const HeroPanel(
                title: '等第一份档案建立后再开始总结',
                subtitle: '当前还没有宠物资料、提醒或记录。先完成第一只爱宠建档，后续的照护观察会自动收拢到这里。',
                child: SizedBox.shrink(),
              ),
              EmptyCard(
                title: '先添加第一只爱宠',
                subtitle: '有了基础档案后，这里才会生成更贴近日常的总结内容。',
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
        final dockLayout =
            dockLayoutForInsets(MediaQuery.viewPaddingOf(context));
        final floatingButtonBottom = MediaQuery.viewPaddingOf(context).bottom +
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
                      ? _OverviewRangeMenuButton(
                          config: widget.store.overviewAnalysisConfig,
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
                child: SafeArea(
                  top: false,
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
            onOpenAiSettings: widget.onOpenAiSettings,
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
    if (service != null) {
      _providerAvailabilityCache[service] = hasProvider;
    }
    setState(() {
      _hasActiveProvider = hasProvider;
    });
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
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: selected
                            ? const Color(0x33FFFFFF)
                            : const Color(0xFFE8EEFF),
                        child: Text(
                          item.avatarText,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF335FCA),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
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
          EmptyCard(
            title: '先添加第一只爱宠',
            subtitle: '建好第一份宠物档案后，提醒、记录和照护观察都会围绕它展开。',
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
                  label: '绝育状态', value: petNeuterStatusLabel(pet.neuterStatus)),
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
                      (item) => ListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.scheduledAt)} · ${item.recurrence}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DD),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.notifications_active_rounded,
                              color: Color(0xFFF2A65A)),
                        ),
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
                      (item) => ListRow(
                        title: item.title,
                        subtitle:
                            '${formatDate(item.recordDate, withTime: false)} · ${item.summary}',
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F7EE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.description_rounded,
                              color: Color(0xFF4FB57C)),
                        ),
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
                ListRow(
                  title: '自定义区间',
                  subtitle: _customDateRange == null
                      ? '尚未选择时间范围'
                      : '${formatDate(_customDateRange!.start, withTime: false)} 至 ${formatDate(_customDateRange!.end, withTime: false)}',
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
                const _AiLoadingState(message: '正在整理时间线、检查结果和就诊问题…'),
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
                _InlineBulletGroup(
                  title: '关键时间线',
                  items: _visitSummary!.timeline,
                ),
                _InlineBulletGroup(
                  title: '用药 / 护理 / 处置',
                  items: _visitSummary!.medicationsAndTreatments,
                ),
                _InlineBulletGroup(
                  title: '检查与结果',
                  items: _visitSummary!.testsAndResults,
                ),
                _InlineBulletGroup(
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

class MePage extends StatelessWidget {
  const MePage({
    super.key,
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return ListView(
      padding: pagePadding,
      children: [
        const PageHeader(
          title: '我的',
          subtitle: '设备与应用设置',
        ),
        const HeroPanel(
          title: 'PetNote',
          subtitle: '把提醒、记录和照护总结收在一个更轻盈的系统式界面里，方便每天顺手管理。',
          child: SizedBox.shrink(),
        ),
        SectionCard(
          title: 'Theme & Appearance',
          children: [
            ListRow(
              title: 'Current theme',
              subtitle: switch (themePreference) {
                AppThemePreference.system => 'Follow system',
                AppThemePreference.light => 'Light mode',
                AppThemePreference.dark => 'Dark mode',
              },
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_system'),
              title: 'Follow system',
              subtitle: 'Use the device appearance setting automatically.',
              value: AppThemePreference.system,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_light'),
              title: 'Light mode',
              subtitle: 'Keep the current bright interface style.',
              value: AppThemePreference.light,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
            _ThemePreferenceTile(
              key: const ValueKey('theme_option_dark'),
              title: 'Dark mode',
              subtitle: 'Reduce glare for low-light usage.',
              value: AppThemePreference.dark,
              groupValue: themePreference,
              onChanged: onThemePreferenceChanged,
            ),
          ],
        ),
        SectionCard(
          title: '通知与提醒',
          children: const [
            ListRow(title: '提醒权限', subtitle: '后续可接入系统通知与提醒权限管理'),
            ListRow(title: '提醒方式', subtitle: '当前原型使用本地清单和 AI 总览来承接提醒信息'),
          ],
        ),
        SectionCard(
          title: '数据与存储',
          children: const [
            ListRow(title: '备份与恢复', subtitle: '预留本地备份、迁移与恢复入口'),
            ListRow(title: '导出与分享', subtitle: '后续支持导出宠物交接卡和记录摘要'),
          ],
        ),
        SectionCard(
          title: '隐私与关于',
          children: const [
            ListRow(title: '隐私说明', subtitle: '仅用于记录照护信息和生成日常建议'),
            ListRow(title: '关于应用', subtitle: 'AI 总览仅供照护参考，不替代兽医建议'),
          ],
        ),
      ],
    );
  }
}

class _ThemePreferenceTile extends StatelessWidget {
  const _ThemePreferenceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final AppThemePreference value;
  final AppThemePreference groupValue;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.listRowBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: RadioListTile<AppThemePreference>(
        value: value,
        groupValue: groupValue,
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.secondaryText,
                height: 1.45,
              ),
        ),
        activeColor: Theme.of(context).colorScheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

String formatDate(DateTime value, {bool withTime = true}) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  if (!withTime) {
    return '${value.year}-$month-$day';
  }
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}

String _overviewTitle(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '最近 7 天的分析',
      OverviewRange.oneMonth => '最近 1 个月的分析',
      OverviewRange.threeMonths => '最近 3 个月的分析',
      OverviewRange.sixMonths => '最近 6 个月的分析',
      OverviewRange.oneYear => '最近 1 年的分析',
      OverviewRange.custom => '自定义时间段的分析',
    };

OverviewRange _rangeFromKey(String key) => switch (key) {
      'sevenDays' => OverviewRange.sevenDays,
      'oneMonth' => OverviewRange.oneMonth,
      'threeMonths' => OverviewRange.threeMonths,
      'sixMonths' => OverviewRange.sixMonths,
      'oneYear' => OverviewRange.oneYear,
      'custom' => OverviewRange.custom,
      _ => OverviewRange.sevenDays,
    };

String _overviewRangeChipLabel(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '7天',
      OverviewRange.oneMonth => '1个月',
      OverviewRange.threeMonths => '3个月',
      OverviewRange.sixMonths => '6个月',
      OverviewRange.oneYear => '1年',
      OverviewRange.custom => '自定义',
    };

String _overviewRangeButtonLabel(OverviewAnalysisConfig config) {
  return _overviewRangeChipLabel(config.range);
}

String _reminderKindLabel(ReminderKind kind) => switch (kind) {
      ReminderKind.vaccine => '疫苗',
      ReminderKind.deworming => '驱虫',
      ReminderKind.medication => '用药',
      ReminderKind.review => '复诊',
      ReminderKind.grooming => '洗护',
      ReminderKind.custom => '自定义',
    };

String _recordTypeLabel(PetRecordType type) => switch (type) {
      PetRecordType.medical => '病历',
      PetRecordType.receipt => '票据',
      PetRecordType.image => '图片',
      PetRecordType.testResult => '检查结果',
      PetRecordType.other => '其他',
    };

enum _VisitSummaryRange { thirtyDays, ninetyDays, custom }

class _AiCareReportOverview extends StatelessWidget {
  const _AiCareReportOverview({required this.report});

  final AiCareReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildCareReportCards(report),
    );
  }
}

List<Widget> _buildCareReportCards(AiCareReport report) {
  final orderedPetReports = _orderedPetReports(report);
  return [
    _AiCareReportHero(report: report),
    _AiRecommendationBoard(recommendations: report.recommendationRankings),
    if (orderedPetReports.isNotEmpty)
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 12),
        child: Text(
          '详细分析',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.4,
          ),
        ),
      ),
    if (orderedPetReports.isNotEmpty)
      _AiPetDetailTabs(reports: orderedPetReports),
  ];
}

List<AiPetCareReport> _orderedPetReports(AiCareReport report) {
  if (report.perPetReports.length <= 1) {
    return report.perPetReports;
  }

  final orderedIds = <String>[];
  for (final item in report.recommendationRankings) {
    for (final petId in item.petIds) {
      if (!orderedIds.contains(petId)) {
        orderedIds.add(petId);
      }
    }
  }

  final orderedReports = <AiPetCareReport>[];
  for (final petId in orderedIds) {
    final match = report.perPetReports.where((item) => item.petId == petId);
    if (match.isNotEmpty) {
      orderedReports.add(match.first);
    }
  }

  for (final petReport in report.perPetReports) {
    if (!orderedReports.contains(petReport)) {
      orderedReports.add(petReport);
    }
  }
  return orderedReports;
}

class _AiPetDetailTabs extends StatefulWidget {
  const _AiPetDetailTabs({required this.reports});

  final List<AiPetCareReport> reports;

  @override
  State<_AiPetDetailTabs> createState() => _AiPetDetailTabsState();
}

class _AiPetDetailTabsState extends State<_AiPetDetailTabs> {
  String? _selectedPetId;

  @override
  void initState() {
    super.initState();
    _selectedPetId = widget.reports.isEmpty ? null : widget.reports.first.petId;
  }

  @override
  void didUpdateWidget(covariant _AiPetDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableIds = widget.reports.map((report) => report.petId).toSet();
    if (_selectedPetId == null || !availableIds.contains(_selectedPetId)) {
      _selectedPetId =
          widget.reports.isEmpty ? null : widget.reports.first.petId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final selectedReport = widget.reports.firstWhere(
      (report) => report.petId == _selectedPetId,
      orElse: () => widget.reports.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Row(
            children: [
              for (final report in widget.reports) ...[
                _AiPetDetailTab(
                  tabKey: ValueKey('ai-pet-tab-${report.petId}'),
                  report: report,
                  selected: report.petId == selectedReport.petId,
                  onTap: () => setState(() => _selectedPetId = report.petId),
                ),
                if (report != widget.reports.last) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: _AiPetDetailPanel(
              key: ValueKey('ai-pet-detail-panel-${selectedReport.petId}'),
              report: selectedReport,
            ),
          ),
        ),
      ],
    );
  }
}

class _AiPetDetailTab extends StatelessWidget {
  const _AiPetDetailTab({
    required this.tabKey,
    required this.report,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final AiPetCareReport report;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final theme = Theme.of(context);
    final backgroundColor =
        selected ? tokens.primaryText : tokens.secondarySurface;
    final foregroundColor =
        selected ? tokens.secondarySurface : tokens.primaryText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tabKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? backgroundColor : tokens.panelBorder,
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: selected
                    ? tokens.secondarySurface.withValues(alpha: 0.18)
                    : tokens.primaryText.withValues(alpha: 0.08),
                child: Text(
                  _aiPetAvatarText(report.petName),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                report.petName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewHeaderActions extends StatelessWidget {
  const _OverviewHeaderActions({
    required this.isLoading,
    required this.onOpenConfig,
    required this.onGenerate,
  });

  final bool isLoading;
  final VoidCallback onOpenConfig;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: '配置',
          onPressed: isLoading ? null : onOpenConfig,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(28, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: accentColor,
            disabledForegroundColor:
                tokens.secondaryText.withValues(alpha: 0.45),
          ),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
        FilledButton.icon(
          onPressed: isLoading ? null : onGenerate,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('生成总览'),
        ),
      ],
    );
  }
}

class _OverviewRangeMenuButton extends StatelessWidget {
  const _OverviewRangeMenuButton({
    required this.config,
    required this.onSelectRange,
  });

  final OverviewAnalysisConfig config;
  final ValueChanged<OverviewRange> onSelectRange;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    final menuBackground = tokens.panelBackground.withAlpha(255);
    return PopupMenuButton<OverviewRange>(
      key: const ValueKey('overview-range-menu-button'),
      onSelected: onSelectRange,
      offset: const Offset(0, 10),
      color: menuBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      itemBuilder: (context) => [
        for (final option in const [
          OverviewRange.sevenDays,
          OverviewRange.oneMonth,
          OverviewRange.threeMonths,
          OverviewRange.sixMonths,
          OverviewRange.oneYear,
          OverviewRange.custom,
        ])
          PopupMenuItem(
            value: option,
            child: Text(_overviewRangeChipLabel(option)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accentColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _overviewRangeButtonLabel(config),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBodyTransition extends StatelessWidget {
  const _OverviewBodyTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 720),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final fadeOutAnimation = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.42, curve: Curves.easeInCubic),
          reverseCurve: const Interval(0.58, 1.0, curve: Curves.easeOutCubic),
        );
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.24, 1.0, curve: Curves.easeOutCubic),
          reverseCurve: const Interval(0.0, 0.76, curve: Curves.easeInCubic),
        );
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(fadeAnimation);
        return FadeTransition(
          opacity: fadeOutAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: slideAnimation, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _OverviewBodySection extends StatelessWidget {
  const _OverviewBodySection({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _OverviewGeneratingExperience extends StatefulWidget {
  const _OverviewGeneratingExperience({
    super.key,
    required this.pets,
  });

  final List<Pet> pets;

  @override
  State<_OverviewGeneratingExperience> createState() =>
      _OverviewGeneratingExperienceState();
}

class _OverviewGeneratingExperienceState
    extends State<_OverviewGeneratingExperience>
    with SingleTickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 620);
  static const _holdDuration = Duration(milliseconds: 2100);

  late final AnimationController _controller;
  Timer? _rotationTimer;
  int _displayedIndex = 0;
  int? _nextIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    );
    _scheduleRotation();
  }

  @override
  void didUpdateWidget(covariant _OverviewGeneratingExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pets.isEmpty) {
      _rotationTimer?.cancel();
      _nextIndex = null;
      _displayedIndex = 0;
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (_displayedIndex >= widget.pets.length) {
      _displayedIndex = 0;
    }
    if (widget.pets.length <= 1) {
      _rotationTimer?.cancel();
      _nextIndex = null;
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (oldWidget.pets.length != widget.pets.length) {
      _scheduleRotation();
    }
  }

  void _scheduleRotation() {
    _rotationTimer?.cancel();
    if (widget.pets.length <= 1) {
      return;
    }
    _rotationTimer = Timer(_holdDuration, _startRotation);
  }

  void _startRotation() {
    if (!mounted || widget.pets.length <= 1) {
      return;
    }
    setState(() {
      _nextIndex = (_displayedIndex + 1) % widget.pets.length;
    });
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final pets = widget.pets.isEmpty ? const <Pet>[] : widget.pets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 54),
          SizedBox(
            height: 258,
            child: Center(
              child: _GeneratingPetCarousel(
                key: const ValueKey('overview-generating-pet-carousel'),
                pets: pets,
                animation: _controller,
                displayedIndex: _displayedIndex,
                nextIndex: _nextIndex,
                onSwitchDisplayed: () {
                  if (!mounted || _nextIndex == null) {
                    return;
                  }
                  setState(() {
                    _displayedIndex = _nextIndex!;
                    _nextIndex = null;
                  });
                  _scheduleRotation();
                },
              ),
            ),
          ),
          const SizedBox(height: 34),
          Text(
            'AI总览生成中',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _OverviewGeneratingHeaderActions extends StatelessWidget {
  const _OverviewGeneratingHeaderActions({
    required this.onOpenConfig,
  });

  final VoidCallback onOpenConfig;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: '配置',
          onPressed: onOpenConfig,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(28, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: accentColor,
            disabledForegroundColor:
                tokens.secondaryText.withValues(alpha: 0.45),
          ),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
        FilledButton.icon(
          key: const ValueKey('overview-generating-analyzing-button'),
          onPressed: null,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: accentColor,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('正在分析'),
        ),
      ],
    );
  }
}

class _GeneratingPetCarousel extends StatefulWidget {
  const _GeneratingPetCarousel({
    super.key,
    required this.pets,
    required this.animation,
    required this.displayedIndex,
    required this.nextIndex,
    required this.onSwitchDisplayed,
  });

  final List<Pet> pets;
  final Animation<double> animation;
  final int displayedIndex;
  final int? nextIndex;
  final VoidCallback onSwitchDisplayed;

  @override
  State<_GeneratingPetCarousel> createState() => _GeneratingPetCarouselState();
}

class _GeneratingPetCarouselState extends State<_GeneratingPetCarousel> {
  int? _appliedNextIndex;

  @override
  Widget build(BuildContext context) {
    final safeDisplayedIndex = widget.pets.isEmpty
        ? 0
        : widget.displayedIndex.clamp(0, widget.pets.length - 1).toInt();
    final safeNextIndex = widget.nextIndex == null || widget.pets.isEmpty
        ? null
        : widget.nextIndex!.clamp(0, widget.pets.length - 1).toInt();
    final displayedPet =
        widget.pets.isEmpty ? null : widget.pets[safeDisplayedIndex];
    final nextPet = safeNextIndex == null ? null : widget.pets[safeNextIndex];
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final progress = widget.animation.value.clamp(0.0, 1.0);
        if (safeNextIndex != null &&
            _appliedNextIndex != safeNextIndex &&
            progress >= 0.42) {
          _appliedNextIndex = safeNextIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onSwitchDisplayed();
            }
          });
        }
        if (safeNextIndex == null && _appliedNextIndex != null) {
          _appliedNextIndex = null;
        }
        return SizedBox(
          width: 216,
          height: 216,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (displayedPet != null)
                _GeneratingPetAvatar(
                  key: ValueKey(
                    'overview-generating-pet-avatar-${displayedPet.id}',
                  ),
                  pet: displayedPet,
                  progress: nextPet == null ? 0 : progress,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GeneratingPetAvatar extends StatelessWidget {
  const _GeneratingPetAvatar({
    super.key,
    required this.pet,
    required this.progress,
  });

  final Pet pet;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accent = tabAccentFor(context, AppTab.overview);
    return Transform.scale(
      scale: _scaleFor(progress),
      child: Opacity(
        opacity: _opacityFor(progress),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.fill.withValues(alpha: 0.18),
                border: Border.all(
                  color: accent.fill.withValues(alpha: 0.9),
                  width: 1.3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.label.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  pet.avatarText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              pet.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  double _scaleFor(double value) {
    final elapsedMs =
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds *
            value;
    if (elapsedMs < 96) {
      return lerpDouble(
        1.0,
        1.08,
        _segmentValue(elapsedMs, 0, 96, Curves.linear),
      )!;
    }
    if (elapsedMs < 176) {
      return lerpDouble(
        1.08,
        0.8,
        _segmentValue(elapsedMs, 96, 176, Curves.easeInQuart),
      )!;
    }
    return lerpDouble(
      0.8,
      1.0,
      _segmentValue(
        elapsedMs,
        176,
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds,
        Curves.easeOutQuart,
      ),
    )!;
  }

  double _opacityFor(double value) {
    final elapsedMs =
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds *
            value;
    if (elapsedMs < 96) {
      return lerpDouble(
        1.0,
        0.96,
        _segmentValue(elapsedMs, 0, 96, Curves.easeOutCubic),
      )!;
    }
    return lerpDouble(
      0.96,
      1.0,
      _segmentValue(
        elapsedMs,
        96,
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds,
        Curves.easeOutCubic,
      ),
    )!;
  }

  double _segmentValue(num value, num start, num end, Curve curve) {
    final segment =
        (((value - start) / (end - start)).toDouble()).clamp(0.0, 1.0);
    return curve.transform(segment);
  }
}

class _OverviewGenerationSetup extends StatelessWidget {
  const _OverviewGenerationSetup({
    required this.config,
    required this.pets,
    required this.hasActiveProvider,
    required this.onOpenAiSettings,
    required this.onTogglePet,
    required this.onToggleSelectAll,
  });

  final OverviewAnalysisConfig config;
  final List<Pet> pets;
  final bool hasActiveProvider;
  final VoidCallback? onOpenAiSettings;
  final void Function(String petId, bool selected) onTogglePet;
  final ValueChanged<bool> onToggleSelectAll;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accent = tabAccentFor(context, AppTab.overview);
    final promptText = hasActiveProvider
        ? '右上角选好时间范围后，在此处选择你的爱宠即可生成总览'
        : '当前尚未配置AI服务，点我前往设置页进行配置➔';
    final selectedPetIds = config.selectedPetIds.isEmpty
        ? pets.map((pet) => pet.id).toSet()
        : config.selectedPetIds.toSet();
    final allSelected = pets.isNotEmpty && selectedPetIds.length == pets.length;
    final promptStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: hasActiveProvider ? tokens.primaryText : accent.label,
          fontWeight: FontWeight.w600,
          height: 1.45,
          letterSpacing: -0.2,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: const ValueKey('overview-generation-prompt-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  key: hasActiveProvider
                      ? null
                      : const ValueKey('overview-open-ai-settings-link'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: hasActiveProvider ? null : onOpenAiSettings,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      promptText,
                      style: promptStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onToggleSelectAll(!allSelected),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('overview-select-all-checkbox'),
                        value: allSelected,
                        onChanged: (value) => onToggleSelectAll(value ?? false),
                        checkColor: accent.label,
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return accent.label.withValues(alpha: 0.14);
                          }
                          return Colors.transparent;
                        }),
                        side: BorderSide(
                          color: allSelected
                              ? accent.label
                              : tokens.secondaryText.withValues(alpha: 0.5),
                          width: 1.4,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        '全选',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: tokens.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          GridView.builder(
            key: const ValueKey('overview-pet-selection-grid'),
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final pet = pets[index];
              final selected = selectedPetIds.contains(pet.id);
              return _OverviewPetSelectionTile(
                key: ValueKey('overview-pet-option-${pet.id}'),
                pet: pet,
                selected: selected,
                accent: accent,
                onTap: () => onTogglePet(pet.id, !selected),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewPetSelectionTile extends StatelessWidget {
  const _OverviewPetSelectionTile({
    super.key,
    required this.pet,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Pet pet;
  final bool selected;
  final NavigationAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? accent.fill.withValues(alpha: 0.18)
                  : tokens.secondarySurface,
              border: Border.all(
                color: selected
                    ? accent.fill.withValues(alpha: 0.88)
                    : tokens.panelBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                pet.avatarText,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: selected ? accent.label : tokens.primaryText,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pet.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? accent.label : tokens.primaryText,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _AiCareReportHero extends StatelessWidget {
  const _AiCareReportHero({required this.report});

  final AiCareReport report;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 132,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${report.overallScore}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: 145,
                            fontWeight: FontWeight.w400,
                            height: 0.92,
                            letterSpacing: -2,
                            color: tokens.primaryText,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 3.5),
                          child: Text(
                            '分',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 50,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -2,
                              color: tokens.primaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 5),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      report.statusLabel,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: tokens.primaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            report.oneLineSummary,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              height: 1.42,
              letterSpacing: -0.1,
              color: tokens.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiRecommendationBoard extends StatelessWidget {
  const _AiRecommendationBoard({required this.recommendations});

  final List<AiRecommendationRanking> recommendations;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final theme = Theme.of(context);
    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 建议',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: tokens.primaryText,
            ),
          ),
          const SizedBox(height: 14),
          ...recommendations.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == recommendations.length - 1 ? 0 : 18,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${item.rank}.',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: tokens.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            letterSpacing: -0.2,
                            color: tokens.primaryText,
                          ),
                        ),
                        if (item.suggestedAction.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.suggestedAction,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.secondaryText,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AiPetDetailPanel extends StatelessWidget {
  const _AiPetDetailPanel({
    super.key,
    required this.report,
  });

  final AiPetCareReport report;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final theme = Theme.of(context);
    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.petName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: tokens.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      report.statusLabel,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tokens.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${report.score} 分',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: tokens.primaryText,
                ),
              ),
            ],
          ),
          if (report.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              report.summary,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: tokens.primaryText,
              ),
            ),
          ],
          _AiDetailGroup(
            title: '为什么是这个分数？',
            items: report.whyThisScore,
          ),
          _AiDetailGroup(
            title: '现在应该处理什么？',
            items: report.topPriority,
          ),
          _AiDetailGroup(
            title: '你漏了什么重要信息？',
            items: report.missedItems,
          ),
          _AiDetailGroup(
            title: '最近有哪些变化？',
            items: report.recentChanges,
          ),
          _AiDetailGroup(
            title: '后续怎么跟进？',
            items: report.followUpPlan,
          ),
        ],
      ),
    );
  }
}

class _AiDetailGroup extends StatelessWidget {
  const _AiDetailGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => BulletText(text: item)),
        ],
      ),
    );
  }
}

String _aiPetAvatarText(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  if (trimmed.runes.length >= 2) {
    return String.fromCharCodes(trimmed.runes.take(2)).toUpperCase();
  }
  return trimmed.substring(0, 1).toUpperCase();
}

AiGenerationContext _buildVisitContext(
  PetNoteStore store,
  Pet pet,
  _VisitSummaryRange range, {
  DateTimeRange? customDateRange,
}) {
  final now = store.referenceNow;
  final start = switch (range) {
    _VisitSummaryRange.thirtyDays => now.subtract(const Duration(days: 30)),
    _VisitSummaryRange.ninetyDays => now.subtract(const Duration(days: 90)),
    _VisitSummaryRange.custom =>
      customDateRange?.start ?? now.subtract(const Duration(days: 30)),
  };
  final end = switch (range) {
    _VisitSummaryRange.custom => customDateRange?.end ?? now,
    _ => now,
  };

  final todos = store.todos
      .where(
        (todo) =>
            todo.petId == pet.id &&
            !todo.dueAt.isBefore(start) &&
            !todo.dueAt.isAfter(end),
      )
      .toList(growable: false);
  final reminders = store.reminders
      .where(
        (reminder) =>
            reminder.petId == pet.id &&
            !reminder.scheduledAt.isBefore(start) &&
            !reminder.scheduledAt.isAfter(end),
      )
      .toList(growable: false);
  final records = store.records
      .where(
        (record) =>
            record.petId == pet.id &&
            !record.recordDate.isBefore(start) &&
            !record.recordDate.isAfter(end),
      )
      .toList(growable: false);

  return AiGenerationContext(
    title: '${pet.name} 的看诊摘要',
    rangeLabel: range == _VisitSummaryRange.custom
        ? '自定义区间'
        : (range == _VisitSummaryRange.thirtyDays ? '最近 30 天' : '最近 90 天'),
    rangeStart: start,
    rangeEnd: end,
    languageTag: 'zh-CN',
    pets: [pet],
    todos: todos,
    reminders: reminders,
    records: records,
  );
}

class _AiLoadingState extends StatelessWidget {
  const _AiLoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
      ],
    );
  }
}

class _InlineBulletGroup extends StatelessWidget {
  const _InlineBulletGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => BulletText(text: item)),
      ],
    );
  }
}
