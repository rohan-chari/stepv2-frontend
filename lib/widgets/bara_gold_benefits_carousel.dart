import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import 'bara_gold_benefits.dart';

/// One benefit row, with manual paging and a 2.5-second reading interval.
class BaraGoldBenefitsCarousel extends StatefulWidget {
  const BaraGoldBenefitsCarousel({super.key});

  /// Use this same height for the adjacent upgrade button. Normal text fits
  /// in 56dp; measure wrapping rather than clipping larger accessibility text.
  static double rowHeight(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style, double available) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: math.max(1.0, available));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Border 2 + horizontal padding 20 + icon/gap 42. Dots sit below.
    final textWidth = width - 64;
    var height = 56.0;
    for (final benefit in BaraGoldBenefit.values) {
      final content =
          measure(benefit.title, goldBenefitTitleStyle(context), textWidth) +
          2 +
          measure(benefit.teaser, goldBenefitDetailStyle(context), textWidth);
      height = math.max(height, content + 22);
    }
    // Match the CTA's own border, padding, arrow and optional sparkles too.
    final innerWidth = width - 27;
    final sparkles = innerWidth >= 280 && scaler.scale(1) <= 1.35;
    final ctaTextHeight = measure(
      'Upgrade to Bara Gold',
      PixelText.title(size: 15, color: AppColors.of(context).textDark),
      innerWidth - 30 - (sparkles ? 52 : 0),
    );
    return math.max(height, ctaTextHeight + 23).ceilToDouble();
  }

  @override
  State<BaraGoldBenefitsCarousel> createState() =>
      _BaraGoldBenefitsCarouselState();
}

class _BaraGoldBenefitsCarouselState extends State<BaraGoldBenefitsCarousel>
    with WidgetsBindingObserver {
  static const _interval = Duration(milliseconds: 2500);
  static const _transition = Duration(milliseconds: 350);
  static const _count = 4;
  // Duplicate end pages provide a seamless wrap in both swipe directions.
  final _pages = PageController(initialPage: 1, keepPage: false);
  Timer? _timer;
  int _page = 1;
  bool _enabled = false;
  bool _resumed = true;
  bool _touching = false;
  bool _scrolling = false;
  bool _hovered = false;
  bool _focused = false;
  Size _screenSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _screenSize = media.size;
    _enabled =
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _restartTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        !_enabled ||
        !_resumed ||
        _touching ||
        _scrolling ||
        _hovered ||
        _focused) {
      return;
    }
    _timer = Timer(_interval, () {
      if (!mounted || !_pages.hasClients) return;
      final box = context.findRenderObject();
      if (box is! RenderBox ||
          !box.hasSize ||
          !(box.localToGlobal(Offset.zero) & box.size).overlaps(
            Offset.zero & _screenSize,
          )) {
        _restartTimer();
        return;
      }
      unawaited(
        _pages.nextPage(duration: _transition, curve: Curves.easeInOutCubic),
      );
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _timer?.cancel();
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      // Jump only after layout, and only if the user is still on the sentinel.
      // The destination has identical content, so no reverse scroll is visible.
      if (_page == 0 || _page == _count + 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pages.hasClients || _scrolling) return;
          final page = _pages.page?.round();
          if (page == 0) _pages.jumpToPage(_count);
          if (page == _count + 1) _pages.jumpToPage(1);
        });
      }
      _restartTimer();
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final active = (_page - 1) % _count;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _restartTimer();
      },
      onExit: (_) {
        _hovered = false;
        _restartTimer();
      },
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) {
          _focused = value;
          _restartTimer();
        },
        child: Listener(
          onPointerDown: (_) {
            _touching = true;
            _restartTimer();
          },
          onPointerUp: (_) {
            _touching = false;
            _restartTimer();
          },
          onPointerCancel: (_) {
            _touching = false;
            _restartTimer();
          },
          child: Container(
            key: const Key('bara-gold-benefits'),
            decoration: BoxDecoration(
              color: colors.parchment,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.parchmentBorder.withValues(alpha: 0.65),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: PageView.builder(
                    key: const Key('bara-gold-benefits-pager'),
                    controller: _pages,
                    itemCount: _count + 2,
                    allowImplicitScrolling: true,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, page) {
                      final index = (page - 1) % _count;
                      final benefit = BaraGoldBenefit.values[index];
                      return Semantics(
                        label:
                            '${benefit.title}. ${benefit.detail} Benefit ${index + 1} of $_count.',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 5, 10, 15),
                          child: Row(
                            children: [
                              BaraGoldBenefitIcon(benefit: benefit),
                              const SizedBox(width: 10),
                              Expanded(
                                child: BaraGoldBenefitText(
                                  benefit: benefit,
                                  short: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _count; i++)
                            Container(
                              key: ValueKey('gold-benefit-dot-$i'),
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == active
                                    ? colors.textAccent
                                    : colors.parchmentBorder,
                              ),
                            ),
                        ],
                      ),
                    ),
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
