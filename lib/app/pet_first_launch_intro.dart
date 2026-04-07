import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:petnote/app/app_theme.dart';

class PetFirstLaunchIntro extends StatefulWidget {
  const PetFirstLaunchIntro({
    super.key,
    required this.onStartOnboarding,
    required this.onExploreFirst,
    this.fillParent = true,
    this.onboardingExitProgress = 0,
  });

  final Future<void> Function() onStartOnboarding;
  final Future<void> Function() onExploreFirst;
  final bool fillParent;
  final double onboardingExitProgress;

  @override
  State<PetFirstLaunchIntro> createState() => _PetFirstLaunchIntroState();
}

class _PetFirstLaunchIntroState extends State<PetFirstLaunchIntro>
    with TickerProviderStateMixin {
  static const _launchPawStartColor = Color(0xFFB8BEC8);
  static const _launchPawStartSize = 208.0;
  static const _launchPawEndSize = 112.0;
  static const _sharedIndicatorColor = Color(0xFFF2A65A);
  static const _pageHorizontalPadding = 20.0;
  static const _pageContentRevealDuration = Duration(milliseconds: 680);
  static const _privacyLockAnimationDuration = Duration(milliseconds: 1220);
  static const _firstPageIndicatorDelay = Duration(milliseconds: 500);
  static const _firstPageIndicatorRevealDuration = Duration(milliseconds: 240);
  static const _firstPageButtonDelayAfterIndicator =
      Duration(milliseconds: 360);
  static const _firstPageButtonRevealDuration = Duration(milliseconds: 320);
  static const _firstPageFooterTimelineDuration = Duration(milliseconds: 1500);
  static const _finalPageIndicatorDelay = Duration(milliseconds: 700);
  static const _finalPageIndicatorRevealDuration = Duration(milliseconds: 180);
  static const _finalPagePrimaryButtonDelayAfterIndicator =
      Duration(milliseconds: 360);
  static const _finalPagePrimaryButtonRevealDuration =
      Duration(milliseconds: 320);
  static const _finalPageSecondaryButtonDelayAfterPrimary =
      Duration(milliseconds: 180);
  static const _finalPageSecondaryButtonRevealDuration =
      Duration(milliseconds: 280);
  static const _finalPageFooterTimelineDuration = Duration(milliseconds: 2100);

  late final PageController _pageController;
  late final AnimationController _launchController;
  late final AnimationController _firstPageFooterController;
  late final AnimationController _finalPageFooterController;

  int _pageIndex = 0;
  bool _showLaunchPaw = true;
  bool _isPrimaryNavigating = false;
  bool _isSecondaryNavigating = false;
  final Set<int> _revealedPages = <int>{};

  static const _pages = [
    _IntroPageData(
      title: '欢迎来到宠记',
      subtitle: '把毛孩子的日常照顾、重要提醒和成长记录，放进一个更省心的小空间里。',
      icon: Icons.pets_rounded,
      accentColor: Color(0xFFF2A65A),
      heroAccentColor: Color(0xFFF2A65A),
      values: [
        _IntroValueData(title: '提醒更清楚'),
        _IntroValueData(title: '记录更集中'),
        _IntroValueData(title: '关怀更省心'),
      ],
    ),
    _IntroPageData(
      title: '照顾它的每一天，都能更从容一点',
      subtitle: '从待办提醒到资料记录，宠记会把重要的照护信息收在顺手的位置。',
      icon: Icons.auto_awesome_rounded,
      accentColor: Color(0xFFD9822B),
      heroAccentColor: Color(0xFF8D63D2),
      listStyle: _IntroListStyle.cards,
      values: [
        _IntroValueData(
          title: '日常提醒更清楚',
          subtitle: '喂养、驱虫、洗护、复查都能安排得更稳当。',
          icon: Icons.checklist_rounded,
          iconColor: Color(0xFFF2C94C),
        ),
        _IntroValueData(
          title: '宠物信息更集中',
          subtitle: '基础资料、喂养偏好和过敏禁忌等一站式管理。',
          icon: Icons.description_rounded,
          iconColor: Color(0xFF335FCA),
        ),
        _IntroValueData(
          title: '爱宠照顾更省心',
          subtitle: '通过总览模块，辅助你更好地照护毛孩子。',
          icon: Icons.favorite_rounded,
          iconColor: Color(0xFFE88FB0),
        ),
      ],
    ),
    _IntroPageData(
      title: '先认识一下你的毛孩子吧',
      subtitle: '添加爱宠信息才能够更好地照顾你的毛孩子~',
      icon: Icons.pets_rounded,
      accentColor: Color(0xFF90CE9B),
      heroAccentColor: Color(0xFF90CE9B),
      values: [
        _IntroValueData(
          title: '你的隐私安全我们始终第一',
          leadingStyle: _IntroValueLeadingStyle.animatedPrivacyLock,
        ),
        _IntroValueData(
          title: '所有数据均安全保存在本地',
          leadingStyle: _IntroValueLeadingStyle.animatedPrivacyLock,
        ),
        _IntroValueData(
          title: '除了AI谁都看不到你的数据',
          leadingStyle: _IntroValueLeadingStyle.animatedPrivacyLock,
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _launchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) {
          return;
        }
        setState(() {
          _showLaunchPaw = false;
          _revealedPages.add(0);
        });
        _startFirstPageFooterReveal();
      });
    _firstPageFooterController = AnimationController(
      vsync: this,
      duration: _firstPageFooterTimelineDuration,
    );
    _finalPageFooterController = AnimationController(
      vsync: this,
      duration: _finalPageFooterTimelineDuration,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _launchController.forward();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _launchController.dispose();
    _firstPageFooterController.dispose();
    _finalPageFooterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.petNoteTokens;
    final isDark = theme.brightness == Brightness.dark;
    final page = _pages[_pageIndex];
    final isFinalPage = _pageIndex == _pages.length - 1;
    final insets = MediaQuery.viewPaddingOf(context);
    final onboardingExitProgress =
        widget.onboardingExitProgress.clamp(0.0, 1.0);
    final onboardingHeroScale = _onboardingHeroScale(onboardingExitProgress);
    final onboardingContentFade =
        _onboardingContentFadeProgress(onboardingExitProgress);
    final onboardingOverlayFade =
        _onboardingOverlayFadeProgress(onboardingExitProgress);
    final onboardingOverlayScale =
        _onboardingOverlayScale(onboardingExitProgress);

    final content = Transform.scale(
      key: const ValueKey('intro_onboarding_exit_scale'),
      scale: onboardingOverlayScale,
      child: Opacity(
        key: const ValueKey('intro_onboarding_exit_opacity'),
        opacity: 1 - onboardingOverlayFade,
        child: Material(
          key: const ValueKey('first_launch_intro_overlay'),
          color: theme.scaffoldBackgroundColor.withValues(
            alpha: isDark ? 0.92 : 0.80,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tokens.pageGradientTop, tokens.pageGradientBottom],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: insets.top + 20),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Column(
                            children: [
                              const SizedBox(height: 12),
                              SizedBox(
                                height: _launchPawEndSize,
                                child: _showLaunchPaw
                                    ? const SizedBox.shrink()
                                    : Center(
                                        child: Transform.scale(
                                          key: const ValueKey(
                                            'intro_onboarding_exit_hero_scale',
                                          ),
                                          scale: onboardingHeroScale,
                                          child: _buildFixedHero(page),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 22),
                              Expanded(
                                child: Opacity(
                                  key: const ValueKey(
                                    'intro_onboarding_exit_content_opacity',
                                  ),
                                  opacity: 1 - onboardingContentFade,
                                  child: PageView(
                                    key: const ValueKey(
                                      'first_launch_intro_page_view',
                                    ),
                                    controller: _pageController,
                                    physics: _showLaunchPaw
                                        ? const NeverScrollableScrollPhysics()
                                        : null,
                                    onPageChanged: _handlePageChanged,
                                    children:
                                        List.generate(_pages.length, (index) {
                                      final item = _pages[index];
                                      return _IntroPage(
                                        key: ValueKey('intro_page_$index'),
                                        index: index,
                                        data: item,
                                        isRevealed:
                                            _revealedPages.contains(index),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showLaunchPaw)
                            _LaunchPawOverlay(
                              progress: _launchController,
                              endColor: _pages.first.accentColor,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (!_showLaunchPaw)
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(20, 18, 20, insets.bottom + 20),
                    child: Opacity(
                      key: const ValueKey(
                        'intro_onboarding_exit_footer_opacity',
                      ),
                      opacity: 1 - onboardingContentFade,
                      child: _buildFooterChrome(page, isFinalPage),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.fillParent) {
      return content;
    }

    return Positioned.fill(
      child: content,
    );
  }

  void _goNext() {
    if (_pageIndex >= _pages.length - 1) {
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePageChanged(int index) {
    setState(() {
      _pageIndex = index;
      if (!_showLaunchPaw || index != 0) {
        _revealedPages.add(index);
      }
    });
    if (!_showLaunchPaw && index == 0) {
      _startFirstPageFooterReveal();
    }
    if (index == _pages.length - 1) {
      _startFinalPageFooterReveal();
    }
  }

  Widget _buildFooterChrome(_IntroPageData page, bool isFinalPage) {
    if (_pageIndex != 0) {
      return _buildStaticFooterChrome(page, isFinalPage);
    }
    return AnimatedBuilder(
      animation: _firstPageFooterController,
      builder: (context, _) {
        final indicatorProgress = _footerStageProgress(
          startDelay: _firstPageIndicatorDelay,
          revealDuration: _firstPageIndicatorRevealDuration,
        );
        final buttonProgress = _footerStageProgress(
          startDelay: Duration(
            milliseconds: _firstPageIndicatorDelay.inMilliseconds +
                _firstPageButtonDelayAfterIndicator.inMilliseconds,
          ),
          revealDuration: _firstPageButtonRevealDuration,
        );
        return Column(
          children: [
            _FooterReveal(
              key: const ValueKey('first_page_indicator_reveal'),
              progress: indicatorProgress,
              child: _buildIndicator(_sharedIndicatorColor),
            ),
            const SizedBox(height: 18),
            _FooterReveal(
              key: const ValueKey('first_page_continue_reveal'),
              progress: buttonProgress,
              child: _buildPrimaryButton(isFinalPage),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStaticFooterChrome(_IntroPageData page, bool isFinalPage) {
    if (isFinalPage) {
      return AnimatedBuilder(
        animation: _finalPageFooterController,
        builder: (context, _) {
          final indicatorProgress = _footerStageProgressForController(
            _finalPageFooterController,
            startDelay: _finalPageIndicatorDelay,
            revealDuration: _finalPageIndicatorRevealDuration,
          );
          final primaryProgress = _footerStageProgressForController(
            _finalPageFooterController,
            startDelay: Duration(
              milliseconds: _finalPageIndicatorDelay.inMilliseconds +
                  _finalPagePrimaryButtonDelayAfterIndicator.inMilliseconds,
            ),
            revealDuration: _finalPagePrimaryButtonRevealDuration,
          );
          final secondaryProgress = _footerStageProgressForController(
            _finalPageFooterController,
            startDelay: Duration(
              milliseconds: _finalPageIndicatorDelay.inMilliseconds +
                  _finalPagePrimaryButtonDelayAfterIndicator.inMilliseconds +
                  _finalPageSecondaryButtonDelayAfterPrimary.inMilliseconds,
            ),
            revealDuration: _finalPageSecondaryButtonRevealDuration,
          );
          return Column(
            children: [
              _FooterReveal(
                key: const ValueKey('final_page_indicator_reveal'),
                progress: indicatorProgress,
                child: _buildIndicator(_sharedIndicatorColor),
              ),
              const SizedBox(height: 18),
              _FooterReveal(
                key: const ValueKey('final_page_primary_reveal'),
                progress: primaryProgress,
                child: _buildPrimaryButton(true),
              ),
              const SizedBox(height: 10),
              _FooterReveal(
                key: const ValueKey('final_page_secondary_reveal'),
                progress: secondaryProgress,
                child: _buildSecondaryButton(),
              ),
            ],
          );
        },
      );
    }
    return Column(
      children: [
        _buildIndicator(_sharedIndicatorColor),
        const SizedBox(height: 18),
        _buildPrimaryButton(isFinalPage),
      ],
    );
  }

  Widget _buildIndicator(Color accentColor) {
    return SizedBox(
      key: const ValueKey('first_launch_intro_indicator'),
      child: _IntroIndicator(
        pageCount: _pages.length,
        pageIndex: _pageIndex,
        accentColor: accentColor,
      ),
    );
  }

  Widget _buildFixedHero(_IntroPageData page) {
    return _AnimatedIntroHero(
      page: page,
      pageIndex: _pageIndex,
    );
  }

  Widget _buildPrimaryButton(bool isFinalPage) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: ValueKey(
          isFinalPage
              ? 'first_launch_intro_primary_button'
              : 'first_launch_intro_continue_button',
        ),
        onPressed: isFinalPage
            ? (_isPrimaryNavigating ? null : _handleStartOnboarding)
            : _goNext,
        child: Text(isFinalPage ? '那我们开始吧' : '继续'),
      ),
    );
  }

  Widget _buildSecondaryButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        key: const ValueKey('first_launch_intro_secondary_button'),
        onPressed: _isSecondaryNavigating ? null : _handleExploreFirst,
        child: const Text('先看看宠记'),
      ),
    );
  }

  Future<void> _handleStartOnboarding() async {
    if (_isPrimaryNavigating) {
      return;
    }
    setState(() => _isPrimaryNavigating = true);
    try {
      await widget.onStartOnboarding();
    } finally {
      if (mounted) {
        setState(() => _isPrimaryNavigating = false);
      }
    }
  }

  Future<void> _handleExploreFirst() async {
    if (_isSecondaryNavigating) {
      return;
    }
    setState(() => _isSecondaryNavigating = true);
    try {
      await widget.onExploreFirst();
    } finally {
      if (mounted) {
        setState(() => _isSecondaryNavigating = false);
      }
    }
  }

  void _startFirstPageFooterReveal() {
    if (_firstPageFooterController.isAnimating ||
        _firstPageFooterController.isCompleted) {
      return;
    }
    _firstPageFooterController.forward();
  }

  void _startFinalPageFooterReveal() {
    if (_finalPageFooterController.isAnimating ||
        _finalPageFooterController.isCompleted) {
      return;
    }
    _finalPageFooterController.forward();
  }

  double _footerStageProgress({
    required Duration startDelay,
    required Duration revealDuration,
  }) {
    return _footerStageProgressForController(
      _firstPageFooterController,
      startDelay: startDelay,
      revealDuration: revealDuration,
    );
  }

  double _footerStageProgressForController(
    AnimationController controller, {
    required Duration startDelay,
    required Duration revealDuration,
  }) {
    final elapsedMs = controller.duration!.inMilliseconds * controller.value;
    final progress = ((elapsedMs - startDelay.inMilliseconds) /
            revealDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    return progress.toDouble();
  }

  double _onboardingHeroScale(double progress) {
    if (progress <= 0) {
      return 1.0;
    }
    if (progress < 0.24) {
      return lerpDouble(
        1.0,
        1.2,
        Curves.easeOutCubic.transform(progress / 0.24),
      )!;
    }
    if (progress < 0.34) {
      return lerpDouble(
        1.2,
        0.38,
        Curves.easeInQuart.transform((progress - 0.24) / 0.10),
      )!;
    }
    return lerpDouble(
      0.38,
      0.06,
      Curves.easeOutQuart.transform(((progress - 0.34) / 0.42).clamp(0.0, 1.0)),
    )!;
  }

  double _onboardingContentFadeProgress(double progress) {
    if (progress <= 0.40) {
      return 0.0;
    }
    return Curves.easeInOutCubic
        .transform(((progress - 0.40) / 0.26).clamp(0.0, 1.0));
  }

  double _onboardingOverlayFadeProgress(double progress) {
    if (progress <= 0.40) {
      return 0.0;
    }
    return Curves.easeInOutCubic
        .transform(((progress - 0.40) / 0.46).clamp(0.0, 1.0));
  }

  double _onboardingOverlayScale(double progress) {
    if (progress <= 0.40) {
      return 1.0;
    }
    return lerpDouble(
      1.0,
      0.94,
      Curves.easeInOutCubic
          .transform(((progress - 0.40) / 0.46).clamp(0.0, 1.0)),
    )!;
  }
}

class _FooterReveal extends StatelessWidget {
  const _FooterReveal({
    super.key,
    required this.child,
    this.progress,
  });

  final Widget child;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    if (progress != null) {
      return _buildFrame(progress!.clamp(0.0, 1.0));
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return _buildFrame(value, child: child);
      },
      child: child,
    );
  }

  Widget _buildFrame(double value, {Widget? child}) {
    final currentChild = child ?? this.child;
    return IgnorePointer(
      key: key,
      ignoring: value <= 0.0,
      child: Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: currentChild,
        ),
      ),
    );
  }
}

class _LaunchPawOverlay extends StatelessWidget {
  const _LaunchPawOverlay({
    required this.progress,
    required this.endColor,
    required this.width,
    required this.height,
  });

  final Animation<double> progress;
  final Color endColor;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(progress.value);
        final centerX = width / 2;
        final startCenterY = height * 0.5;
        final endCenterY = 68;
        final currentSize = lerpDouble(
            _PetFirstLaunchIntroState._launchPawStartSize,
            _PetFirstLaunchIntroState._launchPawEndSize,
            t)!;
        final currentY = lerpDouble(startCenterY, endCenterY, t)!;
        final iconSize = lerpDouble(78, 50, t)!;
        final iconColor = Color.lerp(
          _PetFirstLaunchIntroState._launchPawStartColor,
          endColor,
          t,
        )!;
        final shellColor = Color.lerp(
          const Color(0x14B8BEC8),
          endColor.withValues(alpha: 0.18),
          t,
        )!;

        return Positioned(
          left: centerX - currentSize / 2,
          top: currentY - currentSize / 2,
          child: IgnorePointer(
            child: Container(
              width: currentSize,
              height: currentSize,
              decoration: BoxDecoration(
                color: shellColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.pets_rounded,
                  key: const ValueKey('intro_launch_paw_icon'),
                  size: iconSize,
                  color: iconColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IntroPage extends StatefulWidget {
  const _IntroPage({
    super.key,
    required this.index,
    required this.data,
    required this.isRevealed,
  });

  final int index;
  final _IntroPageData data;
  final bool isRevealed;

  @override
  State<_IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<_IntroPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final AnimationController _contentController;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _contentController = AnimationController(
      vsync: this,
      duration: _PetFirstLaunchIntroState._pageContentRevealDuration,
    );
    _tryReveal();
  }

  @override
  void didUpdateWidget(covariant _IntroPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tryReveal();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = context.petNoteTokens;
    if (!widget.isRevealed) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      key: ValueKey('intro_page_${widget.index}_content'),
      padding: const EdgeInsets.symmetric(
        horizontal: _PetFirstLaunchIntroState._pageHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReveal(
            interval: const Interval(0.12, 0.52, curve: Curves.easeOutCubic),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.data.title,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.data.subtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.secondaryText,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (widget.data.listStyle == _IntroListStyle.cards)
            ..._buildCardItems()
          else
            ..._buildCheckItems(),
        ],
      ),
    );
  }

  List<Widget> _buildCheckItems() {
    return List.generate(widget.data.values.length, (index) {
      final start = 0.34 + index * 0.12;
      final end = (start + 0.24).clamp(0.0, 1.0);
      final curved = CurvedAnimation(
        parent: _contentController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: _IntroValueRow(
            data: widget.data.values[index],
            lockKey: widget.data.values[index].leadingStyle ==
                    _IntroValueLeadingStyle.animatedPrivacyLock
                ? ValueKey('privacy_lock_$index')
                : null,
            lockAnimationDelay: widget.data.values[index].leadingStyle ==
                    _IntroValueLeadingStyle.animatedPrivacyLock
                ? Duration(
                    milliseconds: (_PetFirstLaunchIntroState
                                ._pageContentRevealDuration.inMilliseconds *
                            start)
                        .round(),
                  )
                : null,
          ),
        ),
      );
    });
  }

  List<Widget> _buildCardItems() {
    return List.generate(widget.data.values.length, (index) {
      final start = 0.34 + index * 0.14;
      final end = (start + 0.28).clamp(0.0, 1.0);
      return _buildReveal(
        interval: Interval(start, end, curve: Curves.easeOutCubic),
        child: _IntroFeatureCard(data: widget.data.values[index]),
      );
    });
  }

  Widget _buildReveal({
    required Interval interval,
    required Widget child,
  }) {
    final curved = CurvedAnimation(
      parent: _contentController,
      curve: interval,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  void _tryReveal() {
    if (!widget.isRevealed || _hasAnimated) {
      return;
    }
    _hasAnimated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _contentController.forward();
    });
  }
}

class _IntroHeroIcon extends StatelessWidget {
  const _IntroHeroIcon({
    required this.heroKey,
    required this.icon,
    required this.accentColor,
  });

  final Key heroKey;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: heroKey,
      width: _PetFirstLaunchIntroState._launchPawEndSize,
      height: _PetFirstLaunchIntroState._launchPawEndSize,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          icon,
          size: 50,
          color: accentColor,
        ),
      ),
    );
  }
}

class _AnimatedIntroHero extends StatefulWidget {
  const _AnimatedIntroHero({
    required this.page,
    required this.pageIndex,
  });

  final _IntroPageData page;
  final int pageIndex;

  @override
  State<_AnimatedIntroHero> createState() => _AnimatedIntroHeroState();
}

class _AnimatedIntroHeroState extends State<_AnimatedIntroHero>
    with SingleTickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 400);

  late final AnimationController _controller;
  late _IntroPageData _displayedPage;
  late int _displayedPageIndex;
  _IntroPageData? _nextPage;
  int? _nextPageIndex;

  @override
  void initState() {
    super.initState();
    _displayedPage = widget.page;
    _displayedPageIndex = widget.pageIndex;
    _controller = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedIntroHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageIndex == _displayedPageIndex) {
      _cancelPendingTransition();
      return;
    }
    if (widget.pageIndex == _nextPageIndex) {
      return;
    }
    _nextPage = widget.page;
    _nextPageIndex = widget.pageIndex;
    _controller.forward(from: 0);
  }

  void _cancelPendingTransition() {
    _nextPage = null;
    _nextPageIndex = null;
    if (_controller.isAnimating || _controller.value != 0) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('intro_fixed_hero_host'),
      width: _PetFirstLaunchIntroState._launchPawEndSize,
      height: _PetFirstLaunchIntroState._launchPawEndSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value.clamp(0.0, 1.0);
          if (_nextPage != null && progress >= 0.42) {
            _displayedPage = _nextPage!;
            _displayedPageIndex = _nextPageIndex!;
            _nextPage = null;
            _nextPageIndex = null;
          }
          return Transform.scale(
            scale: _scaleFor(progress),
            child: Opacity(
              opacity: _opacityFor(progress),
              child: _IntroHeroIcon(
                heroKey:
                    ValueKey('intro_page_${_displayedPageIndex}_hero_icon'),
                icon: _displayedPage.icon,
                accentColor: _displayedPage.heroAccentColor,
              ),
            ),
          );
        },
      ),
    );
  }

  double _scaleFor(double value) {
    final elapsedMs = _transitionDuration.inMilliseconds * value;
    if (elapsedMs < 96) {
      return lerpDouble(
        1.0,
        1.12,
        _segmentValue(elapsedMs, 0, 96, Curves.linear),
      )!;
    }
    if (elapsedMs < 176) {
      return lerpDouble(
        1.12,
        0.72,
        _segmentValue(elapsedMs, 96, 176, Curves.easeInQuart),
      )!;
    }
    return lerpDouble(
      0.72,
      1.0,
      _segmentValue(elapsedMs, 176, 400, Curves.easeOutQuart),
    )!;
  }

  double _opacityFor(double value) {
    final elapsedMs = _transitionDuration.inMilliseconds * value;
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
      _segmentValue(elapsedMs, 96, 400, Curves.easeOutCubic),
    )!;
  }

  double _segmentValue(num value, num start, num end, Curve curve) {
    final segment =
        (((value - start) / (end - start)).toDouble()).clamp(0.0, 1.0);
    return curve.transform(segment);
  }
}

class _IntroValueRow extends StatelessWidget {
  const _IntroValueRow({
    required this.data,
    this.lockKey,
    this.lockAnimationDelay,
  });

  final _IntroValueData data;
  final Key? lockKey;
  final Duration? lockAnimationDelay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: lockAnimationDelay == null
                ? const Icon(
                    Icons.done_rounded,
                    size: 20,
                    color: Color(0xFF6AB57A),
                  )
                : _AnimatedPrivacyLockIcon(
                    startDelay: lockAnimationDelay!,
                    iconKey: lockKey!,
                    scaleKey: lockKey is ValueKey<String>
                        ? ValueKey(
                            '${(lockKey as ValueKey<String>).value}_scale',
                          )
                        : null,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (data.subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    data.subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.secondaryText,
                          height: 1.45,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPrivacyLockIcon extends StatefulWidget {
  const _AnimatedPrivacyLockIcon({
    required this.startDelay,
    required this.iconKey,
    this.scaleKey,
  });

  final Duration startDelay;
  final Key iconKey;
  final Key? scaleKey;

  @override
  State<_AnimatedPrivacyLockIcon> createState() =>
      _AnimatedPrivacyLockIconState();
}

class _AnimatedPrivacyLockIconState extends State<_AnimatedPrivacyLockIcon>
    with SingleTickerProviderStateMixin {
  static const _lockColor = Color(0xFF5FAF73);
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _PetFirstLaunchIntroState._privacyLockAnimationDuration,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.startDelay > Duration.zero) {
        await Future<void>.delayed(widget.startDelay);
      }
      if (!mounted) {
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value.clamp(0.0, 1.0);
        final elapsedMs = (_PetFirstLaunchIntroState
                    ._privacyLockAnimationDuration.inMilliseconds *
                value)
            .round();
        final scale = _scaleFor(value);
        final icon = elapsedMs == 0 || scale > 1.0
            ? CupertinoIcons.lock_open_fill
            : CupertinoIcons.lock_fill;
        return Transform.scale(
          key: widget.scaleKey,
          scale: scale,
          child: Icon(
            icon,
            key: widget.iconKey,
            size: 20,
            color: _lockColor,
          ),
        );
      },
    );
  }

  double _scaleFor(double value) {
    final elapsedMs =
        _PetFirstLaunchIntroState._privacyLockAnimationDuration.inMilliseconds *
            value;
    if (elapsedMs < 300) {
      return lerpDouble(
        1.0,
        1.38,
        _segmentValue(elapsedMs, 0, 300, Curves.linear),
      )!;
    }
    if (elapsedMs < 460) {
      return lerpDouble(
        1.38,
        1.5,
        _segmentValue(elapsedMs, 300, 460, Curves.linear),
      )!;
    }
    if (elapsedMs < 900) {
      return lerpDouble(
        1.5,
        0.6,
        _segmentValue(elapsedMs, 460, 900, Curves.easeInQuart),
      )!;
    }
    return lerpDouble(
      0.6,
      1.0,
      _segmentValue(elapsedMs, 900, 1120, Curves.easeOutQuart),
    )!;
  }

  double _segmentValue(num value, num start, num end, Curve curve) {
    final segment =
        (((value - start) / (end - start)).toDouble()).clamp(0.0, 1.0);
    return curve.transform(segment);
  }
}

class _IntroFeatureCard extends StatelessWidget {
  const _IntroFeatureCard({required this.data});

  final _IntroValueData data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panelStrongBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.panelBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.secondarySurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              data.icon ?? Icons.auto_awesome_rounded,
              color: data.iconColor ?? const Color(0xFFD9822B),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (data.subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    data.subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.secondaryText,
                          height: 1.45,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroIndicator extends StatelessWidget {
  const _IntroIndicator({
    required this.pageCount,
    required this.pageIndex,
    required this.accentColor,
  });

  final int pageCount;
  final int pageIndex;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (index) {
        final selected = index == pageIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? accentColor : accentColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _IntroPageData {
  const _IntroPageData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.heroAccentColor,
    this.values = const [],
    this.listStyle = _IntroListStyle.checks,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color heroAccentColor;
  final List<_IntroValueData> values;
  final _IntroListStyle listStyle;
}

class _IntroValueData {
  const _IntroValueData({
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leadingStyle = _IntroValueLeadingStyle.check,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final _IntroValueLeadingStyle leadingStyle;
}

enum _IntroListStyle { checks, cards }

enum _IntroValueLeadingStyle { check, animatedPrivacyLock }
