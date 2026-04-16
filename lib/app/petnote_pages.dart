import 'package:flutter/material.dart';
import 'package:petnote/ai/ai_insights_models.dart';
import 'package:petnote/ai/ai_insights_service.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/common_widgets.dart';
import 'package:petnote/app/layout_metrics.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
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
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final AiInsightsService? aiInsightsService;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _hasActiveProvider = false;
  int _providerCheckSerial = 0;

  @override
  void initState() {
    super.initState();
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
        return ListView(
          padding: pagePadding,
          children: [
            const PageHeader(
              title: '总览',
              subtitle: 'AI 照护总结',
            ),
            HeroPanel(
              title: _overviewTitle(snapshot.range),
              subtitle: '根据最近的待办、提醒和资料记录，用更接近系统报告页的方式整理你的照护观察。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HyperSegmentedControl(
                    items: const [
                      SegmentItem(key: 'sevenDays', label: '7天'),
                      SegmentItem(key: 'oneMonth', label: '1个月'),
                      SegmentItem(key: 'threeMonths', label: '3个月'),
                      SegmentItem(key: 'sixMonths', label: '6个月'),
                      SegmentItem(key: 'oneYear', label: '1年'),
                    ],
                    selectedKey: snapshot.range.name,
                    onChanged: (value) =>
                        widget.store.setOverviewRange(_rangeFromKey(value)),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_hasActiveProvider)
                        OutlinedButton(
                          onPressed: reportState.isLoading
                              ? null
                              : () => _generateCareReport(
                                    forceRefresh: reportState.hasReport,
                                  ),
                          child: Text(
                            reportState.hasReport ? '重新生成 AI 总览' : '生成 AI 总览',
                          ),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('overview_ai_history_button'),
                        onPressed: () => _openOverviewAiHistory(),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: Text(
                          widget.store.overviewAiHistory.isEmpty
                              ? '历史记录'
                              : '历史记录 (${widget.store.overviewAiHistory.length})',
                        ),
                      ),
                      Text(
                        _overviewStatusText(reportState),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.petNoteTokens.secondaryText,
                              height: 1.5,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (reportState.isLoading && !reportState.hasReport)
              SectionCard(
                title: 'AI 总览',
                children: [
                  _AiLoadingState(
                    message: _overviewLoadingText(),
                  ),
                ],
              ),
            if (reportState.report != null)
              ..._buildCareReportCards(reportState.report!),
            if (reportState.hasRequested && reportState.errorMessage != null)
              SectionCard(
                title: 'AI 总览',
                children: [
                  Text(
                    reportState.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFC7533E),
                          height: 1.6,
                        ),
                  ),
                  Text(
                    '已自动回退到本地规则总结，方便你先继续查看当前周期的照护概况。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.petNoteTokens.secondaryText,
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            if (!reportState.hasReport)
              ...snapshot.sections.map(
                (section) => SectionCard(
                  title: section.title,
                  children: section.items
                      .map((item) => BulletText(text: item))
                      .toList(),
                ),
              ),
            SectionCard(
              title: '说明',
              children: [
                Text(
                  snapshot.disclaimer,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.petNoteTokens.secondaryText,
                        height: 1.6,
                      ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _overviewStatusText(OverviewAiReportState reportState) {
    if (reportState.isLoading) {
      return 'AI 正在生成新的专业分析报告…';
    }
    if (reportState.hasReport) {
      final report = reportState.report!;
      if (_isLocalFastOverviewReport(report)) {
        return '当前正在展示本地规则短版总结与综合评分，仅供照护参考，不替代兽医建议。';
      }
      if (_isAiFastOverviewReport(report)) {
        return '当前正在展示 AI 短版总结与综合评分，仅供照护参考，不替代兽医建议。';
      }
      return '当前正在展示专业分析报告与综合评分，仅供照护参考，不替代兽医建议。';
    }
    if (reportState.hasRequested && reportState.errorMessage != null) {
      if (_looksLikeOverviewGenerationStabilityIssue(
        reportState.errorMessage!,
      )) {
        return 'AI 基础连接可用，但当前时间范围的长报告生成不稳定，已回退到本地规则总结。';
      }
      return 'AI 总览生成失败，当前展示本地规则总结。';
    }
    if (_hasActiveProvider) {
      return '已检测到 AI 配置；点击按钮后才会生成专业分析报告。';
    }
    return '未检测到可用 AI 配置，当前展示本地规则总结。';
  }

  bool _isLocalFastOverviewReport(AiCareReport report) {
    return report.dataQualityNotes.any(
      (item) => item.contains('本地极速规则生成'),
    );
  }

  bool _isAiFastOverviewReport(AiCareReport report) {
    return report.dataQualityNotes.any(
      (item) => item.contains('AI 短版总结'),
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

  Future<void> _openOverviewAiHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OverviewAiHistoryPage(store: widget.store),
      ),
    );
  }

  String _overviewLoadingText() {
    return switch (widget.store.overviewRange) {
      OverviewRange.threeMonths ||
      OverviewRange.sixMonths ||
      OverviewRange.oneYear =>
        '当前时间范围较长，正在基于精简事实摘要生成结构化照护总结…',
      _ => '正在根据当前时间范围生成结构化照护总结…',
    };
  }

  bool _looksLikeOverviewGenerationStabilityIssue(String message) {
    return message.contains('基础连接可用') ||
        message.contains('精简事实摘要') ||
        message.contains('超时或过载');
  }
}

class OverviewAiHistoryPage extends StatelessWidget {
  const OverviewAiHistoryPage({
    super.key,
    required this.store,
  });

  final PetNoteStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final history = store.overviewAiHistory;
        return Scaffold(
          appBar: AppBar(
            title: const Text('AI 总览历史'),
            actions: [
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClearHistory(context),
                  child: const Text('清空'),
                ),
            ],
          ),
          body: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '还没有 AI 总览历史。生成成功后的报告会自动保存在这里。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF6C7280),
                            height: 1.6,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  itemCount: history.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return SectionCard(
                      title: entry.title,
                      trailing: Text(
                        formatDate(entry.generatedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6C7280),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      children: [
                        Text(
                          entry.report.executiveSummary,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.6,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    OverviewAiHistoryDetailPage(entry: entry),
                              ),
                            ),
                            child: const Text('查看详情'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 AI 总览历史'),
        content: const Text('清空后将删除本地保存的所有 AI 总览历史记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await store.clearOverviewAiHistory();
  }
}

class OverviewAiHistoryDetailPage extends StatelessWidget {
  const OverviewAiHistoryDetailPage({
    super.key,
    required this.entry,
  });

  final AiCareReportHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 总览详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          SectionCard(
            title: entry.title,
            children: [
              Text(
                '${entry.rangeLabel} · ${formatDate(entry.generatedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6C7280),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          ..._buildCareReportCards(entry.report),
        ],
      ),
    );
  }
}

class PetsPage extends StatelessWidget {
  const PetsPage({
    super.key,
    required this.store,
    required this.onAddFirstPet,
    required this.onEditPet,
  });

  final PetNoteStore store;
  final VoidCallback onAddFirstPet;
  final ValueChanged<Pet> onEditPet;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final pet = store.selectedPet;
        final remindersForSelectedPet = store.remindersForSelectedPet;
        final recordsForSelectedPet = store.recordsForSelectedPet;
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
                itemCount: store.pets.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = store.pets[index];
                  final selected = pet?.id == item.id;
                  return GestureDetector(
                    onTap: () => store.selectPet(item.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFF2A65A)
                            : const Color(0xF4FFFFFF),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            key: ValueKey('pet_selector_photo_${item.id}'),
                            width: 40,
                            height: 40,
                            child: PetPhotoAvatar(
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
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
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
                                item.ageLabel,
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
                onAction: onAddFirstPet,
              )
            else ...[
              HeroPanel(
                header: hasPetPhoto(pet.photoPath)
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          key: ValueKey('selected_pet_hero_photo'),
                          width: 96,
                          height: 96,
                          child: PetPhotoSquare(
                            photoPath: pet.photoPath,
                            size: 96,
                          ),
                        ),
                      )
                    : null,
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
                            semanticLabel: '查看${pet.name}的近期提醒',
                            onTap: () => _openReminderDetailPage(context, pet),
                          ),
                          MetricItem(
                            label: '资料记录',
                            value: '${recordsForSelectedPet.length}',
                            background: const Color(0xFFF5F0FF),
                            foreground: const Color(0xFF6B51C9),
                            semanticLabel: '查看${pet.name}的资料记录',
                            onTap: () => _openRecordDetailPage(context, pet),
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
                  onPressed: () => onEditPet(pet),
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
      },
    );
  }

  Future<void> _openReminderDetailPage(BuildContext context, Pet pet) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PetReminderDetailPage(
          store: store,
          petId: pet.id,
          petName: pet.name,
        ),
      ),
    );
  }

  Future<void> _openRecordDetailPage(BuildContext context, Pet pet) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PetRecordDetailPage(
          store: store,
          petId: pet.id,
          petName: pet.name,
        ),
      ),
    );
  }
}

class _PetReminderDetailPage extends StatelessWidget {
  const _PetReminderDetailPage({
    required this.store,
    required this.petId,
    required this.petName,
  });

  final PetNoteStore store;
  final String petId;
  final String petName;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return Scaffold(
      body: HyperPageBackground(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final reminders = store.reminders
                .where((item) => item.petId == petId)
                .toList(growable: false);
            return ListView(
              padding: pagePadding,
              children: [
                PageHeader(
                  title: '$petName 的近期提醒',
                  subtitle: '查看当前宠物的提醒安排与执行状态',
                  trailing: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                SectionCard(
                  title: '近期提醒',
                  children: reminders.isEmpty
                      ? [
                          Text(
                            '暂无提醒',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF6C7280)),
                          ),
                        ]
                      : reminders
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
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  color: Color(0xFFF2A65A),
                                ),
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PetRecordDetailPage extends StatelessWidget {
  const _PetRecordDetailPage({
    required this.store,
    required this.petId,
    required this.petName,
  });

  final PetNoteStore store;
  final String petId;
  final String petName;

  @override
  Widget build(BuildContext context) {
    final pagePadding =
        pageContentPaddingForInsets(MediaQuery.viewPaddingOf(context));
    return Scaffold(
      body: HyperPageBackground(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final records = store.records
                .where((item) => item.petId == petId)
                .toList(growable: false);
            return ListView(
              padding: pagePadding,
              children: [
                PageHeader(
                  title: '$petName 的资料记录',
                  subtitle: '查看当前宠物的病历、检查和留档记录',
                  trailing: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                SectionCard(
                  title: '资料记录',
                  children: records.isEmpty
                      ? [
                          Text(
                            '暂无资料记录',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF6C7280)),
                          ),
                        ]
                      : records
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
                                child: const Icon(
                                  Icons.description_rounded,
                                  color: Color(0xFF4FB57C),
                                ),
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
              ],
            );
          },
        ),
      ),
    );
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
            RadioGroup<AppThemePreference>(
              groupValue: themePreference,
              onChanged: (next) {
                if (next != null) {
                  onThemePreferenceChanged(next);
                }
              },
              child: Column(
                children: [
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_system'),
                    title: 'Follow system',
                    subtitle: 'Use the device appearance setting automatically.',
                    value: AppThemePreference.system,
                    selected: themePreference == AppThemePreference.system,
                  ),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_light'),
                    title: 'Light mode',
                    subtitle: 'Keep the current bright interface style.',
                    value: AppThemePreference.light,
                    selected: themePreference == AppThemePreference.light,
                  ),
                  _ThemePreferenceTile(
                    key: const ValueKey('theme_option_dark'),
                    title: 'Dark mode',
                    subtitle: 'Reduce glare for low-light usage.',
                    value: AppThemePreference.dark,
                    selected: themePreference == AppThemePreference.dark,
                  ),
                ],
              ),
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
    required this.selected,
  });

  final String title;
  final String subtitle;
  final AppThemePreference value;
  final bool selected;

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
        selected: selected,
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
      OverviewRange.sevenDays => '最近 7 天的总结',
      OverviewRange.oneMonth => '最近 1 个月的总结',
      OverviewRange.threeMonths => '最近 3 个月的总结',
      OverviewRange.sixMonths => '最近 6 个月的总结',
      OverviewRange.oneYear => '最近 1 年的总结',
    };

OverviewRange _rangeFromKey(String key) => switch (key) {
      'sevenDays' => OverviewRange.sevenDays,
      'oneMonth' => OverviewRange.oneMonth,
      'threeMonths' => OverviewRange.threeMonths,
      'sixMonths' => OverviewRange.sixMonths,
      'oneYear' => OverviewRange.oneYear,
      _ => OverviewRange.sevenDays,
    };

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

List<Widget> _buildCareReportCards(AiCareReport report) {
  return [
    SectionCard(
      title: '综合评分',
      children: [
        Text(
          '${report.overallScore} 分 · ${report.overallScoreLabel}',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          report.executiveSummary,
          style: const TextStyle(height: 1.6, fontWeight: FontWeight.w600),
        ),
      ],
    ),
    SectionCard(
      title: '执行总评',
      children: report.overallAssessment
          .map((item) => BulletText(text: item))
          .toList(),
    ),
    SectionCard(
      title: '评分拆解',
      children: [
        ...report.scoreBreakdown.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.label} · ${item.score}/25',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.reason,
                  style: const TextStyle(height: 1.6),
                ),
              ],
            ),
          ),
        ),
        ...report.scoreReasons.take(1).map((item) => BulletText(text: item)),
      ],
    ),
    SectionCard(
      title: '关键发现',
      children:
          report.keyFindings.map((item) => BulletText(text: item)).toList(),
    ),
    SectionCard(
      title: '趋势变化',
      children:
          report.trendAnalysis.map((item) => BulletText(text: item)).toList(),
    ),
    SectionCard(
      title: '风险评估',
      children: report.riskAssessment.isEmpty
          ? const [BulletText(text: '当前没有需要额外放大的风险项，继续观察即可。')]
          : report.riskAssessment
              .map((item) => BulletText(text: item))
              .toList(),
    ),
    SectionCard(
      title: '优先行动',
      children:
          report.priorityActions.map((item) => BulletText(text: item)).toList(),
    ),
    SectionCard(
      title: '数据完整性说明',
      children: report.dataQualityNotes
          .map((item) => BulletText(text: item))
          .toList(),
    ),
    ...report.perPetReports.map(
      (petReport) => SectionCard(
        title: '${petReport.petName} 专项报告',
        children: [
          Text(
            '${petReport.score} 分 · ${petReport.scoreLabel}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            petReport.summary,
            style: const TextStyle(
              height: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '照护重点',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          Text(
            petReport.careFocus,
            style: const TextStyle(height: 1.6),
          ),
          const SizedBox(height: 12),
          const Text(
            '关键事件',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          ...petReport.keyEvents.map((item) => BulletText(text: item)),
          const SizedBox(height: 8),
          const Text(
            '趋势分析',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          ...petReport.trendAnalysis.map((item) => BulletText(text: item)),
          const SizedBox(height: 8),
          const Text(
            '风险评估',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          ...(petReport.riskAssessment.isEmpty
              ? const [BulletText(text: '当前暂无需要额外放大的专项风险。')]
              : petReport.riskAssessment.map((item) => BulletText(text: item))),
          const SizedBox(height: 8),
          const Text(
            '建议行动',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          ...petReport.recommendedActions.map((item) => BulletText(text: item)),
          const SizedBox(height: 8),
          const Text(
            '后续观察重点',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          Text(
            petReport.followUpFocus,
            style: const TextStyle(height: 1.6),
          ),
        ],
      ),
    ),
  ];
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
