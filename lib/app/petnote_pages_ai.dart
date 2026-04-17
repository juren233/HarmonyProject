part of 'petnote_pages.dart';

String _overviewTitle(OverviewRange range) => switch (range) {
      OverviewRange.sevenDays => '最近 7 天的分析',
      OverviewRange.oneMonth => '最近 1 个月的分析',
      OverviewRange.threeMonths => '最近 3 个月的分析',
      OverviewRange.sixMonths => '最近 6 个月的分析',
      OverviewRange.oneYear => '最近 1 年的分析',
      OverviewRange.custom => '自定义时间段的分析',
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
  final FutureOr<void> Function()? onOpenAiSettings;
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
          TitledBulletGroup(
            title: '为什么是这个分数？',
            items: report.whyThisScore,
            topPadding: 16,
            titleStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
          TitledBulletGroup(
            title: '现在应该处理什么？',
            items: report.topPriority,
            topPadding: 16,
            titleStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
          TitledBulletGroup(
            title: '你漏了什么重要信息？',
            items: report.missedItems,
            topPadding: 16,
            titleStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
          TitledBulletGroup(
            title: '最近有哪些变化？',
            items: report.recentChanges,
            topPadding: 16,
            titleStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
          TitledBulletGroup(
            title: '后续怎么跟进？',
            items: report.followUpPlan,
            topPadding: 16,
            titleStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  letterSpacing: -0.2,
                ),
          ),
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
