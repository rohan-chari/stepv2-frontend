import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../styles.dart';
import 'game_container.dart';
import 'home_chrome.dart';
import 'powerup_icon.dart';

/// CSGO-style reel chrome shared by every mystery-box surface (race boxes,
/// daily reward box): swipe-to-spin scroll, deceleration, pointer markers,
/// and the end-of-spin lift on the result tile. Tiles themselves come from
/// [itemBuilder] so each surface renders its own contents.
class CaseOpeningReel extends StatefulWidget {
  final int itemCount;
  final int resultIndex;
  final Widget Function(BuildContext context, int index, bool isResult)
  itemBuilder;
  final VoidCallback onComplete;
  final double height;
  final double itemWidth;

  /// Async gate between the swipe and the spin. The server roll happens HERE —
  /// not before — so backing out of the screen without swiping never consumes
  /// the box. Return true once the result tile is in place to run the spin;
  /// return false to re-arm the reel (e.g. the roll request failed). While the
  /// future is pending the reel shows PREPARING. Null spins immediately.
  final Future<bool> Function()? onSpinRequested;

  const CaseOpeningReel({
    super.key,
    required this.itemCount,
    required this.resultIndex,
    required this.itemBuilder,
    required this.onComplete,
    this.height = 116,
    this.itemWidth = 86.0,
    this.onSpinRequested,
  });

  @override
  State<CaseOpeningReel> createState() => _CaseOpeningReelState();
}

class _CaseOpeningReelState extends State<CaseOpeningReel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _waitingForSwipe = false;
  bool _requestingSpin = false;

  // Layout values captured during build so the haptic listener can map the
  // current scroll offset to a tile index without re-measuring.
  double _totalScroll = 0;
  double _totalItemWidth = 0;
  int _lastTickIndex = -1;

  static const _itemSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
    _animation.addListener(_handleReelTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // A firm thump as the result locks under the pointer, mirroring the
        // heavy opening thump on the celebration confetti.
        HapticFeedback.mediumImpact();
        // Small delay before calling onComplete for dramatic effect
        Future.delayed(const Duration(milliseconds: 600), widget.onComplete);
      }
    });
    _waitingForSwipe = true;
  }

  /// Fires a selection tick each time a new tile scrolls under the centre
  /// marker, so the reel feels like a physical ratcheting wheel — dense ticks
  /// while it's flying, thinning out as the easeOutQuart curve decelerates.
  void _handleReelTick() {
    if (_totalItemWidth <= 0) return;
    final scrollOffset = _animation.value * _totalScroll;
    final tileIndex = (scrollOffset / _totalItemWidth).floor();
    if (tileIndex != _lastTickIndex) {
      _lastTickIndex = tileIndex;
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startSpin() async {
    if (!_waitingForSwipe || _requestingSpin) return;
    if (widget.onSpinRequested != null) {
      setState(() => _requestingSpin = true);
      bool ok = false;
      try {
        ok = await widget.onSpinRequested!();
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      setState(() => _requestingSpin = false);
      if (!ok) return; // roll failed — stay armed so the user can retry
    }
    if (!mounted || !_waitingForSwipe) return;
    setState(() => _waitingForSwipe = false);
    _controller.forward();
  }

  Widget _buildItem(int index) {
    final isResult = index == widget.resultIndex;
    final tile = widget.itemBuilder(context, index, isResult);
    if (!isResult) return tile;
    // Lock-in pop: as the reel settles, the winning tile lifts, scales up and
    // catches a gold glow — the "it's THIS one" beat.
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final locked = _animation.value > 0.985;
        final content = locked
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.pillGold.withValues(alpha: 0.85),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              )
            : child!;
        return Transform.translate(
          offset: Offset(0, locked ? -5.0 : 0.0),
          child: Transform.scale(scale: locked ? 1.07 : 1.0, child: content),
        );
      },
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalItemWidth = widget.itemWidth + _itemSpacing;
    final armed = _waitingForSwipe && !_requestingSpin;
    return GestureDetector(
      onTap: armed ? _startSpin : null,
      onHorizontalDragEnd: armed ? (_) => _startSpin() : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final centerX = viewportWidth / 2;

          // The result item's left edge position in the full strip
          final resultItemCenter =
              widget.resultIndex * totalItemWidth + widget.itemWidth / 2;

          // We want to scroll so the result ends up at centerX
          final totalScroll = resultItemCenter - centerX;
          // Hand these to the haptic tick listener (see _handleReelTick).
          _totalScroll = totalScroll;
          _totalItemWidth = totalItemWidth;

          return GameContainer(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            frameColor: AppColors.textDark,
            surfaceColor: AppColors.parchment,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _requestingSpin
                      ? 'PREPARING...'
                      : _waitingForSwipe
                      ? 'SWIPE OR TAP'
                      : 'OPENING...',
                  style: PixelText.title(size: 14, color: AppColors.textMid),
                ),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Gold glow that builds around the viewport as the reel
                    // decelerates toward the result, then holds once it locks.
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        final t = ((_animation.value - 0.55) / 0.45).clamp(
                          0.0,
                          1.0,
                        );
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: t == 0
                                ? const []
                                : [
                                    BoxShadow(
                                      color: AppColors.pillGold.withValues(
                                        alpha: 0.65 * t,
                                      ),
                                      blurRadius: 6 + 14 * t,
                                      spreadRadius: 2 * t,
                                    ),
                                  ],
                          ),
                          child: child,
                        );
                      },
                      child: Container(
                        height: widget.height,
                        width: viewportWidth,
                        // Dark machine window: tiles glow against the deep
                        // felt, framed like a cabinet slot.
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.pillGoldShadow,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: ColoredBox(
                            color: AppColors.felt,
                            child: ClipRect(
                              child: OverflowBox(
                                maxWidth: double.infinity,
                                alignment: Alignment.centerLeft,
                                child: AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, child) {
                                    final scrollOffset =
                                        _animation.value * totalScroll;
                                    return Transform.translate(
                                      offset: Offset(-scrollOffset, 0),
                                      child: child,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (
                                          int i = 0;
                                          i < widget.itemCount;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const SizedBox(width: _itemSpacing),
                                          _buildItem(i),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Edge fades: tiles surface out of the dark on one side
                    // and sink back into it on the other, so the strip reads
                    // as a spinning wheel instead of a sliding row.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Color(0xE61A2B20),
                                      Color(0x001A2B20),
                                    ],
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 46,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerRight,
                                    end: Alignment.centerLeft,
                                    colors: [
                                      Color(0xE61A2B20),
                                      Color(0x001A2B20),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _CenterMarkerPainter()),
                      ),
                    ),
                    Positioned(
                      top: -3,
                      child: CustomPaint(
                        size: const Size(28, 16),
                        painter: _PointerPainter(),
                      ),
                    ),
                    Positioned(
                      bottom: -3,
                      child: Transform.rotate(
                        angle: pi,
                        child: CustomPaint(
                          size: const Size(28, 16),
                          painter: _PointerPainter(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_waitingForSwipe) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.swipe_rounded,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'drag across the reel',
                        style: HomeText.body(
                          size: 13,
                          color: HomeColors.muted,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rarity tile colors shared by all reel surfaces.
Color caseRarityColor(String rarity) {
  switch (rarity.toUpperCase()) {
    case 'RARE':
      return AppColors.coinDark;
    case 'UNCOMMON':
      return const Color(0xFF4A90D9);
    default:
      return AppColors.woodMid;
  }
}

/// The standard reel tile frame (rarity border + checker backdrop) shared by
/// all reel surfaces; [child] is the tile contents.
class CaseReelTile extends StatelessWidget {
  final String rarity;
  final double width;
  final double height;
  final Widget child;

  const CaseReelTile({
    super.key,
    required this.rarity,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = caseRarityColor(rarity);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.parchment,
        border: Border.all(color: borderColor, width: 2.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.18),
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ArcadeCheckerPainter(
                tileColor: Color(0x08FFFFFF),
                stripeColor: Color(0x08000000),
                drawBottomStripe: false,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(6, 7, 6, 6), child: child),
        ],
      ),
    );
  }
}

/// CSGO-style horizontal scrolling strip of powerup icons.
/// Rapidly scrolls left, decelerates, and stops with the result under the pointer.
class CaseOpeningStrip extends StatefulWidget {
  /// May be empty while the server roll hasn't happened yet (deferred-roll
  /// flow): the result slot holds a decoy until [didUpdateWidget] swaps the
  /// real result in. It lands before the spin starts, far off-screen.
  final String resultType;
  final String resultRarity;
  final VoidCallback onComplete;
  final double height;
  final Future<bool> Function()? onSpinRequested;

  const CaseOpeningStrip({
    super.key,
    required this.resultType,
    required this.resultRarity,
    required this.onComplete,
    this.height = 116,
    this.onSpinRequested,
  });

  @override
  State<CaseOpeningStrip> createState() => _CaseOpeningStripState();
}

class _CaseOpeningStripState extends State<CaseOpeningStrip> {
  late List<_StripItem> _items;

  static const _itemWidth = 86.0;
  static const _itemCount = 45;
  // Place result near the end so there's a long scroll
  static const _resultPosition = 38;

  static const _rarityByType = {
    'PROTEIN_SHAKE': 'COMMON',
    'SHORTCUT': 'COMMON',
    'RUNNERS_HIGH': 'UNCOMMON',
    'LEG_CRAMP': 'UNCOMMON',
    'STEALTH_MODE': 'UNCOMMON',
    'WRONG_TURN': 'UNCOMMON',
    'RED_CARD': 'RARE',
    'SECOND_WIND': 'RARE',
    'COMPRESSION_SOCKS': 'RARE',
    'FANNY_PACK': 'RARE',
    'TRAIL_MIX': 'COMMON',
    'DETOUR_SIGN': 'COMMON',
    'LUCKY_HORSESHOE': 'RARE',
    'CAMPFIRE_REST': 'UNCOMMON',
    'TRAIL_MAGNET': 'COMMON',
    'POCKET_WATCH': 'RARE',
    'TRAIL_MINE': 'RARE',
    'PINECONE_TOSS': 'UNCOMMON',
    'SNEAKY_SWAP': 'RARE',
    'MIRROR': 'RARE',
    'CLEANSE': 'RARE',
  };

  // Weighted random: common 50%, uncommon 35%, rare 15%
  static const _commonTypes = [
    'PROTEIN_SHAKE',
    'SHORTCUT',
    'TRAIL_MIX',
    'DETOUR_SIGN',
    'TRAIL_MAGNET',
  ];
  // CAMPFIRE_REST removed from the possible-drops preview (1.1.7): it is no
  // longer generated by the backend, so don't advertise it as obtainable. Its
  // icon/name entries are kept elsewhere so a still-held campfire still renders.
  static const _uncommonTypes = [
    'RUNNERS_HIGH',
    'LEG_CRAMP',
    'STEALTH_MODE',
    'WRONG_TURN',
    'PINECONE_TOSS',
  ];
  static const _rareTypes = [
    'RED_CARD',
    'SECOND_WIND',
    'COMPRESSION_SOCKS',
    'FANNY_PACK',
    'LUCKY_HORSESHOE',
    'POCKET_WATCH',
    'TRAIL_MINE',
    'SNEAKY_SWAP',
    'CLEANSE',
    'MIRROR',
  ];

  @override
  void initState() {
    super.initState();
    _items = _generateStrip();
  }

  @override
  void didUpdateWidget(CaseOpeningStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deferred-roll flow: the result arrives after the swipe. Replant only the
    // result tile so the decoys the user is already looking at don't reshuffle.
    if (widget.resultType != oldWidget.resultType ||
        widget.resultRarity != oldWidget.resultRarity) {
      _items = List.of(_items)..[_resultPosition] = _resultOrDecoy(Random());
    }
  }

  _StripItem _resultOrDecoy(Random rng) {
    if (widget.resultType.isNotEmpty) {
      return _StripItem(widget.resultType, widget.resultRarity);
    }
    final type = _randomType(rng);
    return _StripItem(type, _rarityByType[type] ?? 'COMMON');
  }

  List<_StripItem> _generateStrip() {
    final rng = Random();
    final items = <_StripItem>[];

    for (int i = 0; i < _itemCount; i++) {
      if (i == _resultPosition) {
        items.add(_resultOrDecoy(rng));
      } else {
        final type = _randomType(rng);
        items.add(_StripItem(type, _rarityByType[type] ?? 'COMMON'));
      }
    }
    return items;
  }

  String _randomType(Random rng) {
    final roll = rng.nextDouble();
    if (roll < 0.50) {
      return _commonTypes[rng.nextInt(_commonTypes.length)];
    } else if (roll < 0.85) {
      return _uncommonTypes[rng.nextInt(_uncommonTypes.length)];
    } else {
      return _rareTypes[rng.nextInt(_rareTypes.length)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return CaseOpeningReel(
      itemCount: _itemCount,
      resultIndex: _resultPosition,
      onComplete: widget.onComplete,
      height: widget.height,
      itemWidth: _itemWidth,
      onSpinRequested: widget.onSpinRequested,
      itemBuilder: (context, index, isResult) {
        final item = _items[index];
        return CaseReelTile(
          rarity: item.rarity,
          width: _itemWidth,
          height: widget.height - 16,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(child: PowerupIcon(type: item.type, size: 46)),
              ),
              const SizedBox(height: 3),
              Text(
                _typeName(item.type),
                style: PixelText.body(size: 10, color: AppColors.textDark),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  static const _powerupNames = {
    'LEG_CRAMP': 'Leg Cramp',
    'RED_CARD': 'Red Card',
    'SHORTCUT': 'Shortcut',
    'COMPRESSION_SOCKS': 'Compression\nSocks',
    'PROTEIN_SHAKE': 'Protein Shake',
    'RUNNERS_HIGH': "Runner's High",
    'SECOND_WIND': 'Second Wind',
    'STEALTH_MODE': 'Stealth Mode',
    'WRONG_TURN': 'Wrong Turn',
    'FANNY_PACK': 'Fanny Pack',
    'TRAIL_MIX': 'Trail Mix',
    'DETOUR_SIGN': 'Detour Sign',
    'LUCKY_HORSESHOE': 'Lucky\nHorseshoe',
    'CAMPFIRE_REST': 'Campfire Rest',
    'TRAIL_MAGNET': 'Trail Magnet',
    'POCKET_WATCH': 'Pocket Watch',
    'TRAIL_MINE': 'Trail Mine',
    'PINECONE_TOSS': 'Pinecone Toss',
    'SNEAKY_SWAP': 'Sneaky Swap',
    'MIRROR': 'Mirror',
    'CLEANSE': 'Cleanse',
  };

  static String _typeName(String type) {
    return _powerupNames[type] ?? type;
  }
}

class _StripItem {
  final String type;
  final String rarity;
  const _StripItem(this.type, this.rarity);
}

/// Chunky gold chevron with a dark keyline — the cabinet's win pointer.
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = AppColors.pillGold);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.pillGoldShadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The gold "win line" through the reel window: a soft glow column under a
/// crisp gold hairline, so the landing spot is unmistakable against the felt.
class _CenterMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;

    // Soft glow column behind the line.
    final glow = Paint()
      ..color = AppColors.pillGold.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(Rect.fromLTRB(x - 7, 4, x + 7, size.height - 4), glow);

    final line = Paint()
      ..color = AppColors.pillGold
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
