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

String _recordSubtitle(PetRecord item) {
  final summary = item.summary.trim();
  final photoCount = item.photoPaths.length;
  final photoLabel = photoCount == 0 ? null : '$photoCount 张图片';
  return [
    formatDate(item.recordDate, withTime: false),
    if (summary.isNotEmpty) summary,
    if (photoLabel != null) photoLabel,
  ].join(' · ');
}

enum _VisitSummaryRange { thirtyDays, ninetyDays, custom }

class _AiCareReportOverview extends StatelessWidget {
  const _AiCareReportOverview({
    required this.report,
    required this.pets,
  });

  final AiCareReport report;
  final List<Pet> pets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildCareReportCards(report, pets),
    );
  }
}

List<Widget> _buildCareReportCards(AiCareReport report, List<Pet> pets) {
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
      _AiPetDetailTabs(
        reports: orderedPetReports,
        pets: pets,
      ),
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        '读取数据量：${report.promptPayloadVersionLabel}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8C8C8C),
          height: 1.4,
        ),
      ),
    ),
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
  const _AiPetDetailTabs({
    required this.reports,
    required this.pets,
  });

  final List<AiPetCareReport> reports;
  final List<Pet> pets;

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
                  pet: _findPetForReport(report.petId),
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

  Pet? _findPetForReport(String petId) {
    for (final pet in widget.pets) {
      if (pet.id == petId) {
        return pet;
      }
    }
    return null;
  }
}

class _AiPetDetailTab extends StatelessWidget {
  const _AiPetDetailTab({
    required this.tabKey,
    required this.report,
    required this.pet,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final AiPetCareReport report;
  final Pet? pet;
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
                child: PetPhotoAvatar(
                  photoPath: pet?.photoPath,
                  fallbackText: pet == null
                      ? _aiPetAvatarText(report.petName)
                      : petAvatarFallbackForPet(pet!),
                  radius: 15,
                  backgroundColor: Colors.transparent,
                  foregroundColor: foregroundColor,
                  fallbackTextStyle: theme.textTheme.labelMedium?.copyWith(
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
    required this.canGenerate,
    required this.hasReport,
    required this.onOpenAiSettings,
    required this.onGenerate,
  });

  final bool isLoading;
  final bool canGenerate;
  final bool hasReport;
  final FutureOr<void> Function()? onOpenAiSettings;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _OverviewAiSettingsHeaderButton(
          onPressed: onOpenAiSettings,
        ),
        FilledButton.icon(
          onPressed: isLoading || (!canGenerate && !hasReport)
              ? null
              : onGenerate,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFB8BCC6),
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text(hasReport ? '重新生成' : '生成总览'),
        ),
      ],
    );
  }
}

class _OverviewSetupHeaderActions extends StatelessWidget {
  const _OverviewSetupHeaderActions({
    required this.config,
    required this.referenceDate,
    required this.onOpenAiSettings,
    required this.onSelectRange,
    required this.onSelectCustomRange,
  });

  final OverviewAnalysisConfig config;
  final DateTime referenceDate;
  final FutureOr<void> Function()? onOpenAiSettings;
  final Future<void> Function(OverviewRange range) onSelectRange;
  final Future<void> Function(DateTimeRange range) onSelectCustomRange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _OverviewAiSettingsHeaderButton(
          onPressed: onOpenAiSettings,
        ),
        _OverviewRangeMenuButton(
          config: config,
          referenceDate: referenceDate,
          onSelectRange: onSelectRange,
          onSelectCustomRange: onSelectCustomRange,
        ),
      ],
    );
  }
}

class _OverviewAiSettingsHeaderButton extends StatelessWidget {
  const _OverviewAiSettingsHeaderButton({
    required this.onPressed,
  });

  final FutureOr<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return IconButton.filledTonal(
      key: const ValueKey('overview-header-ai-settings-button'),
      tooltip: 'AI配置',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: accentColor,
        backgroundColor: accentColor.withValues(alpha: 0.1),
        disabledForegroundColor: const Color(0xFF9AA1AD),
        disabledBackgroundColor: const Color(0xFFE7E9EF),
        minimumSize: const Size(44, 44),
      ),
      icon: const Icon(Icons.settings_outlined, size: 20),
    );
  }
}

class _OverviewRangeMenuButton extends StatefulWidget {
  const _OverviewRangeMenuButton({
    required this.config,
    required this.referenceDate,
    required this.onSelectRange,
    required this.onSelectCustomRange,
  });

  final OverviewAnalysisConfig config;
  final DateTime referenceDate;
  final Future<void> Function(OverviewRange range) onSelectRange;
  final Future<void> Function(DateTimeRange range) onSelectCustomRange;

  @override
  State<_OverviewRangeMenuButton> createState() =>
      _OverviewRangeMenuButtonState();
}

class _OverviewRangeMenuButtonState extends State<_OverviewRangeMenuButton> {
  bool _pressed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        key: const ValueKey('overview-range-menu-button'),
        onTap: _busy ? null : () => _handleTap(context),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.97 : 1,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            offset: Offset(0, _pressed ? 0.035 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: accentColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        accentColor.withValues(alpha: _pressed ? 0.18 : 0.28),
                    blurRadius: _pressed ? 10 : 18,
                    spreadRadius: _pressed ? -2 : 0,
                    offset: Offset(0, _pressed ? 5 : 10),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    key: const ValueKey(
                      'overview-range-menu-button-pressed-scope',
                    ),
                    opacity: _pressed ? 0.14 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _overviewRangeButtonLabel(widget.config),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) {
      return;
    }
    setState(() {
      _pressed = value;
    });
  }

  Future<void> _handleTap(BuildContext context) async {
    _busy = true;
    triggerSelectionHaptic();
    await Future<void>.delayed(const Duration(milliseconds: 55));
    _setPressed(false);
    await _openRangePicker(context);
    _busy = false;
  }

  Future<void> _openRangePicker(BuildContext context) async {
    await _showRangePickerBottomSheet(context);
  }

  Future<void> _showRangePickerBottomSheet(
    BuildContext context,
  ) {
    final tokens = context.petNoteTokens;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: tokens.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  key: const ValueKey('overview_range_bottom_sheet'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择总览时间范围',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: tokens.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    for (final option in const [
                      OverviewRange.sevenDays,
                      OverviewRange.oneMonth,
                      OverviewRange.threeMonths,
                      OverviewRange.sixMonths,
                      OverviewRange.oneYear,
                      OverviewRange.custom,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OverviewRangeOptionTile(
                          key: ValueKey(
                            'overview-range-option-${option.name}',
                          ),
                          label: _overviewRangeChipLabel(option),
                          selected: option == widget.config.range,
                          onTap: () async {
                            if (option != OverviewRange.custom) {
                              await widget.onSelectRange(option);
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.of(context).pop();
                              return;
                            }
                            final customRange =
                                await _openCustomRangePage(context);
                            if (!context.mounted) {
                              return;
                            }
                            if (customRange != null) {
                              await widget.onSelectCustomRange(customRange);
                            }
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<DateTimeRange?> _openCustomRangePage(BuildContext context) {
    final now = DateUtils.dateOnly(widget.referenceDate);
    final initialRange = widget.config.range == OverviewRange.custom &&
            widget.config.customRangeStart != null &&
            widget.config.customRangeEnd != null
        ? DateTimeRange(
            start: DateUtils.dateOnly(widget.config.customRangeStart!),
            end: DateUtils.dateOnly(widget.config.customRangeEnd!),
          )
        : DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          );
    return Navigator.of(context, rootNavigator: true).push<DateTimeRange?>(
      _OverviewCustomRangePageRoute(
        initialRange: initialRange,
      ),
    );
  }
}

class _OverviewRangeOptionTile extends StatefulWidget {
  const _OverviewRangeOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Future<void> Function() onTap;

  @override
  State<_OverviewRangeOptionTile> createState() =>
      _OverviewRangeOptionTileState();
}

class _OverviewRangeOptionTileState extends State<_OverviewRangeOptionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  );
  late final Animation<double> _depthAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _isAnimatingTap = false;
  bool _pressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 2 * _depthAnimation.value),
          child: Transform.scale(
            scale: 1 - (0.022 * _depthAnimation.value),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTap: _handleTap,
          child: Ink(
            decoration: BoxDecoration(
              color: widget.selected
                  ? tokens.segmentedSelectedBackground.withValues(alpha: 0.16)
                  : tokens.panelStrongBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: widget.selected
                    ? tokens.segmentedSelectedBackground
                    : tokens.panelBorder,
                width: widget.selected ? 1.4 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Icon(
                    widget.selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: widget.selected
                        ? tokens.segmentedSelectedBackground
                        : tokens.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap() async {
    if (_isAnimatingTap) {
      return;
    }
    _isAnimatingTap = true;
    triggerSelectionHaptic();
    _setPressed(true);
    await _controller.forward(from: 0);
    _setPressed(false);
    if (!mounted) {
      return;
    }
    await widget.onTap();
    _isAnimatingTap = false;
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) {
      return;
    }
    setState(() {
      _pressed = value;
    });
  }
}

class _OverviewCustomRangePageRoute extends PageRouteBuilder<DateTimeRange?> {
  _OverviewCustomRangePageRoute({
    required DateTimeRange initialRange,
  }) : super(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) =>
              _OverviewCustomRangePage(initialRange: initialRange),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(fade);
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child),
            );
          },
        );
}

class _OverviewCustomRangePage extends StatefulWidget {
  const _OverviewCustomRangePage({
    required this.initialRange,
  });

  final DateTimeRange initialRange;

  @override
  State<_OverviewCustomRangePage> createState() =>
      _OverviewCustomRangePageState();
}

enum _OverviewCustomRangeStage { start, end }

class _OverviewCustomRangePageState extends State<_OverviewCustomRangePage> {
  late DateTime _startDate = DateUtils.dateOnly(widget.initialRange.start);
  late DateTime _endDate = DateUtils.dateOnly(widget.initialRange.end);
  _OverviewCustomRangeStage _activeStage = _OverviewCustomRangeStage.start;

  DateTime get _referenceNow => DateUtils.dateOnly(DateTime.now());
  bool get _canApply => !_endDate.isBefore(_startDate);
  DateTime get _displayedMonth =>
      _activeStage == _OverviewCustomRangeStage.start ? _startDate : _endDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final localizations = MaterialLocalizations.of(context);
    final accent = tokens.segmentedSelectedBackground;
    final overlayStyle = petNoteOverlayStyleForTheme(theme).copyWith(
      statusBarColor: tokens.panelBackground,
      systemNavigationBarColor: tokens.panelBackground,
    );
    final topInset = MediaQuery.paddingOf(context).top;
    final calendarTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: accent,
        onPrimary: Colors.white,
        surface: tokens.panelBackground,
        onSurface: tokens.primaryText,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: tokens.panelStrongBackground,
        headerBackgroundColor: Colors.transparent,
        headerForegroundColor: tokens.primaryText,
        surfaceTintColor: Colors.transparent,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return tokens.primaryText;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent;
          }
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return accent;
        }),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayBorder: BorderSide(color: accent, width: 1.2),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        key: const ValueKey('overview-custom-range-scaffold'),
        backgroundColor: tokens.panelBackground,
        body: ColoredBox(
          key: const ValueKey('overview-custom-range-page'),
          color: tokens.panelBackground,
          child: Column(
            children: [
              ColoredBox(
                key: const ValueKey('overview-custom-range-top-surface'),
                color: tokens.panelBackground,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, topInset + 16, 18, 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey(
                            'overview-custom-range-close-button'),
                        onPressed: _close,
                        style: IconButton.styleFrom(
                          backgroundColor: tokens.panelStrongBackground,
                          foregroundColor: tokens.primaryText,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '自定义时间范围',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: tokens.primaryText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '先选开始日期，再补齐结束日期',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        key: const ValueKey(
                            'overview-custom-range-apply-button'),
                        onPressed: _canApply ? _apply : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _OverviewCustomRangeStageCard(
                                key: const ValueKey(
                                  'overview-custom-range-stage-start',
                                ),
                                label: '开始日期',
                                value:
                                    localizations.formatMediumDate(_startDate),
                                selected: _activeStage ==
                                    _OverviewCustomRangeStage.start,
                                onTap: () =>
                                    _setStage(_OverviewCustomRangeStage.start),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _OverviewCustomRangeStageCard(
                                key: const ValueKey(
                                  'overview-custom-range-stage-end',
                                ),
                                label: '结束日期',
                                value: localizations.formatMediumDate(_endDate),
                                selected: _activeStage ==
                                    _OverviewCustomRangeStage.end,
                                onTap: () =>
                                    _setStage(_OverviewCustomRangeStage.end),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _activeStage == _OverviewCustomRangeStage.start
                                ? '当前正在选择开始日期'
                                : '当前正在选择结束日期',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.panelStrongBackground,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: tokens.panelBorder,
                                width: 1,
                              ),
                            ),
                            child: Theme(
                              data: calendarTheme,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                                child: CalendarDatePicker(
                                  key: const ValueKey(
                                    'overview-custom-range-calendar',
                                  ),
                                  initialDate: _displayedMonth,
                                  currentDate: _referenceNow,
                                  firstDate:
                                      DateTime(_referenceNow.year - 2, 1, 1),
                                  lastDate:
                                      DateTime(_referenceNow.year + 1, 12, 31),
                                  onDateChanged: _handleDateSelected,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDateSelected(DateTime value) {
    final normalized = DateUtils.dateOnly(value);
    triggerSelectionHaptic();
    setState(() {
      switch (_activeStage) {
        case _OverviewCustomRangeStage.start:
          _startDate = normalized;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate;
          }
          _activeStage = _OverviewCustomRangeStage.end;
          break;
        case _OverviewCustomRangeStage.end:
          _endDate = normalized;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
          break;
      }
    });
  }

  void _setStage(_OverviewCustomRangeStage stage) {
    triggerSelectionHaptic();
    setState(() {
      _activeStage = stage;
    });
  }

  void _close() {
    triggerSelectionHaptic();
    Navigator.of(context).pop();
  }

  void _apply() {
    if (!_canApply) {
      return;
    }
    triggerLightImpactHaptic();
    Navigator.of(context).pop(
      DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
    );
  }
}

class _OverviewCustomRangeStageCard extends StatelessWidget {
  const _OverviewCustomRangeStageCard({
    super.key,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? tokens.segmentedSelectedBackground.withValues(alpha: 0.14)
                : tokens.panelStrongBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? tokens.segmentedSelectedBackground
                  : tokens.panelBorder,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
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
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
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
        return _OverviewBodyDirectionalTransition(
          animation: animation,
          child: child,
        );
      },
      child: child,
    );
  }
}

class _OverviewBodyDirectionalTransition extends StatelessWidget {
  const _OverviewBodyDirectionalTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value.clamp(0.0, 1.0);
        final isOutgoing = animation.status == AnimationStatus.reverse;
        final normalizedPhase = isOutgoing
            ? ((1 - value) / 0.5).clamp(0.0, 1.0)
            : ((value - 0.5) / 0.5).clamp(0.0, 1.0);
        final phaseProgress = isOutgoing
            ? Curves.easeInCubic.transform(normalizedPhase)
            : Curves.easeOutCubic.transform(normalizedPhase);
        final clampedPhaseProgress = phaseProgress.clamp(0.0, 1.0);
        final opacity =
            isOutgoing ? 1 - clampedPhaseProgress : clampedPhaseProgress;
        final offsetY = isOutgoing
            ? 0.12 * clampedPhaseProgress
            : -0.12 * (1 - clampedPhaseProgress);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(0, offsetY),
            child: child,
          ),
        );
      },
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

enum _OverviewGenerationExperienceMode { generating, error }

class _OverviewGeneratingExperience extends StatefulWidget {
  const _OverviewGeneratingExperience({
    super.key,
    required this.pets,
    this.mode = _OverviewGenerationExperienceMode.generating,
    this.errorMessage,
  });

  final List<Pet> pets;
  final _OverviewGenerationExperienceMode mode;
  final String? errorMessage;

  @override
  State<_OverviewGeneratingExperience> createState() =>
      _OverviewGeneratingExperienceState();
}

class _OverviewGeneratingExperienceState
    extends State<_OverviewGeneratingExperience> with TickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 560);
  static const _holdDuration = Duration(milliseconds: 2100);
  static const _titleGradientDuration = Duration(milliseconds: 1320);
  static const _breathingDuration = Duration(milliseconds: 2400);

  late final AnimationController _controller;
  late final AnimationController _breathingController;
  late final AnimationController _titleGradientController;
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
    _breathingController = AnimationController(
      vsync: this,
      duration: _breathingDuration,
    );
    _titleGradientController = AnimationController(
      vsync: this,
      duration: _titleGradientDuration,
    );
    _syncGeneratingTitleAnimation();
    _syncBreathingAnimation();
    if (widget.mode == _OverviewGenerationExperienceMode.generating) {
      _scheduleRotation();
    }
  }

  @override
  void didUpdateWidget(covariant _OverviewGeneratingExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _syncGeneratingTitleAnimation();
      _syncBreathingAnimation();
    }
    if (widget.mode != _OverviewGenerationExperienceMode.generating) {
      _rotationTimer?.cancel();
      _nextIndex = null;
      _controller.stop();
      _controller.value = 0;
      return;
    }
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

  void _syncGeneratingTitleAnimation() {
    if (widget.mode == _OverviewGenerationExperienceMode.generating) {
      if (!_titleGradientController.isAnimating) {
        _titleGradientController.repeat();
      }
      return;
    }
    _titleGradientController
      ..stop()
      ..value = 0;
  }

  void _syncBreathingAnimation() {
    if (widget.mode == _OverviewGenerationExperienceMode.generating) {
      if (!_breathingController.isAnimating) {
        _breathingController.repeat();
      }
      return;
    }
    _breathingController
      ..stop()
      ..value = 0;
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
    _breathingController.dispose();
    _titleGradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final pets = widget.pets.isEmpty ? const <Pet>[] : widget.pets;
    final isError = widget.mode == _OverviewGenerationExperienceMode.error;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: isError ? 212 : 258,
          child: Center(
            child: _GeneratingPetCarousel(
              key: ValueKey(
                isError
                    ? 'overview-error-pet-carousel'
                    : 'overview-generating-pet-carousel',
              ),
              pets: pets,
              animation: _controller,
              breathingAnimation: _breathingController,
              displayedIndex: _displayedIndex,
              nextIndex: _nextIndex,
              mode: widget.mode,
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
        SizedBox(height: isError ? 24 : 34),
        isError
            ? Text(
                '喵喵喵？！好像出错了...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: tokens.primaryText,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
              )
            : _GeneratingGradientTitle(
                animation: _titleGradientController,
              ),
        if (isError && (widget.errorMessage?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              widget.errorMessage!.trim(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryText,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(4, isError ? 0 : 22, 4, isError ? 0 : 28),
      child: isError
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: content,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 54),
                content,
              ],
            ),
    );
  }
}

class _GeneratingGradientTitle extends StatelessWidget {
  const _GeneratingGradientTitle({
    required this.animation,
  });

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final text = Text(
      key: const ValueKey('overview-generating-title-label'),
      'AI总览生成中',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: tokens.primaryText,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: text,
      builder: (context, child) {
        return ShaderMask(
          key: const ValueKey('overview-generating-title-shimmer'),
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => _buildGeneratingTitleSweepGradient(
            animation.value,
            baseColor: tokens.primaryText,
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

LinearGradient _buildGeneratingTitleSweepGradient(
  double progress, {
  required Color baseColor,
  double opacity = 1,
}) {
  const begin = Alignment(-1.74, 0);
  const end = Alignment(1.74, 0);
  return LinearGradient(
    colors: [
      const Color(0xFF8A8A8A).withValues(alpha: opacity),
      const Color(0xFF8A8A8A).withValues(alpha: opacity),
      const Color(0xFFB8B8B8).withValues(alpha: opacity),
      const Color(0xFFDADADA).withValues(alpha: opacity),
      const Color(0xFFF0F0F0).withValues(alpha: opacity),
      const Color(0xFFFFFFFF).withValues(alpha: opacity),
      const Color(0xFFFFFFFF).withValues(alpha: opacity),
      const Color(0xFFF0F0F0).withValues(alpha: opacity),
      const Color(0xFFDADADA).withValues(alpha: opacity),
      const Color(0xFFB8B8B8).withValues(alpha: opacity),
      const Color(0xFF8A8A8A).withValues(alpha: opacity),
      const Color(0xFF8A8A8A).withValues(alpha: opacity),
    ],
    stops: const [
      0.0,
      0.415,
      0.435,
      0.455,
      0.475,
      0.475,
      0.525,
      0.525,
      0.545,
      0.565,
      0.585,
      1.0,
    ],
    begin: begin,
    end: end,
    tileMode: TileMode.repeated,
    transform: _SlidingGradientTransform(
      progress,
      begin: begin,
      end: end,
    ),
  );
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(
    this.progress, {
    required this.begin,
    required this.end,
  });

  final double progress;
  final Alignment begin;
  final Alignment end;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final travelX = ((end.x - begin.x) * bounds.width / 2) * progress;
    final travelY = ((end.y - begin.y) * bounds.height / 2) * progress;
    return Matrix4.translationValues(travelX, travelY, 0);
  }
}

class _OverviewGeneratingHeaderActions extends StatelessWidget {
  const _OverviewGeneratingHeaderActions();

  @override
  Widget build(BuildContext context) {
    final accentColor = tabAccentFor(context, AppTab.overview).label;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
    required this.breathingAnimation,
    required this.displayedIndex,
    required this.nextIndex,
    required this.mode,
    required this.onSwitchDisplayed,
  });

  final List<Pet> pets;
  final Animation<double> animation;
  final Animation<double> breathingAnimation;
  final int displayedIndex;
  final int? nextIndex;
  final _OverviewGenerationExperienceMode mode;
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
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        widget.breathingAnimation,
      ]),
      builder: (context, _) {
        final progress = widget.animation.value.clamp(0.0, 1.0);
        final hasActiveTransition =
            (safeNextIndex != null || _appliedNextIndex != null) &&
                progress > 0;
        final breathingScale =
            widget.mode == _OverviewGenerationExperienceMode.error
                ? 1.0
                : _breathingScaleFor(widget.breathingAnimation.value);
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
        if (safeNextIndex == null &&
            _appliedNextIndex != null &&
            progress >= 0.999) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _appliedNextIndex = null;
              });
            }
          });
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
                  breathingScale: breathingScale,
                  progress: hasActiveTransition ? progress : 0,
                  mode: widget.mode,
                ),
            ],
          ),
        );
      },
    );
  }

  double _breathingScaleFor(double value) {
    if (value < 0.375) {
      return lerpDouble(
        1.0,
        1.14,
        Curves.easeInOutSine.transform(value / 0.375),
      )!;
    }
    if (value < 0.6666666667) {
      return lerpDouble(
        1.14,
        0.86,
        Curves.easeInOutSine.transform((value - 0.375) / 0.2916666667),
      )!;
    }
    return lerpDouble(
      0.86,
      1.0,
      Curves.easeInOutSine.transform((value - 0.6666666667) / 0.3333333333),
    )!;
  }
}

class _GeneratingPetAvatar extends StatelessWidget {
  const _GeneratingPetAvatar({
    super.key,
    required this.pet,
    required this.breathingScale,
    required this.progress,
    required this.mode,
  });

  final Pet pet;
  final double breathingScale;
  final double progress;
  final _OverviewGenerationExperienceMode mode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final accent = tabAccentFor(context, AppTab.overview);
    final isError = mode == _OverviewGenerationExperienceMode.error;
    final avatarFillColor =
        isError ? const Color(0xFFDCEEFF) : accent.fill.withValues(alpha: 0.18);
    final avatarBorderColor =
        isError ? const Color(0xFF6FAFEF) : accent.fill.withValues(alpha: 0.9);
    final avatarShadowColor = isError
        ? const Color(0xFF3B82C4).withValues(alpha: 0.18)
        : accent.label.withValues(alpha: 0.14);
    return Opacity(
      opacity: _opacityFor(progress),
      child: Transform.scale(
        key: ValueKey('overview-generating-pet-avatar-scale-${pet.id}'),
        scale: _scaleFor(progress),
        child: Transform.scale(
          key: ValueKey('overview-generating-pet-breath-group-${pet.id}'),
          scale: isError ? 1.0 : breathingScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isError ? 132 : 124,
                height: isError ? 132 : 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarFillColor,
                  border: Border.all(
                    color: avatarBorderColor,
                    width: isError ? 1.8 : 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: avatarShadowColor,
                      blurRadius: isError ? 30 : 24,
                      offset: Offset(0, isError ? 12 : 10),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: isError
                          ? const Icon(
                              Icons.sentiment_dissatisfied_rounded,
                              size: 72,
                              color: Color(0xFF2F7CC1),
                            )
                          : PetPhotoAvatar(
                              photoPath: pet.photoPath,
                              fallbackText: petAvatarFallbackForPet(pet),
                              radius: isError ? 66 : 62,
                              backgroundColor: Colors.transparent,
                              foregroundColor: tokens.primaryText,
                              fallbackTextStyle: Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(
                                    color: tokens.primaryText,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                            ),
                    ),
                  ],
                ),
              ),
              if (!isError) ...[
                const SizedBox(height: 14),
                Text(
                  pet.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double _scaleFor(double value) {
    final elapsedMs =
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds *
            value;
    if (elapsedMs < 120) {
      return lerpDouble(
        1.0,
        1.18,
        _segmentValue(elapsedMs, 0, 120, Curves.easeOutCubic),
      )!;
    }
    if (elapsedMs < 360) {
      return lerpDouble(
        1.18,
        0.64,
        _segmentValue(elapsedMs, 120, 360, Curves.easeInOutCubic),
      )!;
    }
    return lerpDouble(
      0.64,
      1.0,
      _segmentValue(
        elapsedMs,
        360,
        560,
        Curves.easeOutBack,
      ),
    )!;
  }

  double _opacityFor(double value) {
    final elapsedMs =
        _OverviewGeneratingExperienceState._transitionDuration.inMilliseconds *
            value;
    if (elapsedMs < 120) {
      return lerpDouble(
        1.0,
        0.98,
        _segmentValue(elapsedMs, 0, 120, Curves.easeOutCubic),
      )!;
    }
    return lerpDouble(
      0.98,
      1.0,
      _segmentValue(
        elapsedMs,
        120,
        560,
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
    final selectedPetIds = config.selectedPetIds.toSet();
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
    final selectedCheckColor = Color.lerp(accent.label, Colors.white, 0.5)!;
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
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: PetPhotoAvatar(
                      photoPath: pet.photoPath,
                      fallbackText: petAvatarFallbackForPet(pet),
                      radius: 42,
                      backgroundColor: Colors.transparent,
                      foregroundColor:
                          selected ? accent.label : tokens.primaryText,
                      fallbackTextStyle: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            color: selected ? accent.label : tokens.primaryText,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ),
                  if (selected)
                    ColoredBox(
                      key: ValueKey('overview-pet-selected-overlay-${pet.id}'),
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.36),
                    ),
                  if (selected)
                    Center(
                      child: Icon(
                        key: ValueKey('overview-pet-selected-check-${pet.id}'),
                        Icons.check_rounded,
                        color: selectedCheckColor,
                        size: 34,
                      ),
                    ),
                ],
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
            title: '现在应该怎么做？',
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
            title: '后续要怎么跟进？',
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
