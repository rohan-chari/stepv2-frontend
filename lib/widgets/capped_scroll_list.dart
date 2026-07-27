import 'package:flutter/material.dart';

/// A column of [children] that grows naturally until it hits [maxHeight], then
/// stops growing and scrolls internally instead.
///
/// Used by the race detail standings so a 30-runner race doesn't push the
/// powerups and chat sections kilometres down the page. Below the cap it is
/// indistinguishable from a plain [Column] — no scrollbar, no clipped edge, no
/// wasted whitespace — because the inner list shrink-wraps.
///
/// When content *is* overflowing, a soft fade appears on whichever edge still
/// has rows hidden behind it. The fade is painted in [fadeColor] (pass the
/// surface the list sits on) so it reads as the content dissolving into the
/// card rather than as a grey overlay. Both edges are re-evaluated on every
/// scroll, so the bottom fade disappears once you reach the last row — a
/// permanently-on fade would imply there is always more to see.
class CappedScrollList extends StatefulWidget {
  const CappedScrollList({
    super.key,
    required this.children,
    required this.maxHeight,
    required this.fadeColor,
    this.fadeExtent = 26,
  });

  final List<Widget> children;

  /// The tallest this list may become. Content beyond it scrolls.
  final double maxHeight;

  /// The colour the hidden rows fade into — normally the card's fill.
  final Color fadeColor;

  final double fadeExtent;

  @override
  State<CappedScrollList> createState() => _CappedScrollListState();
}

class _CappedScrollListState extends State<CappedScrollList> {
  final ScrollController _controller = ScrollController();

  bool _canScrollUp = false;
  bool _canScrollDown = false;

  @override
  void initState() {
    super.initState();
    // The first frame has no scroll metrics yet, so the initial fade state has
    // to wait for layout. Without this the bottom fade is missing until the
    // user's first drag.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void didUpdateWidget(covariant CappedScrollList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Live races repoll and re-render with more/fewer runners; recompute so the
    // fades match the new content length.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    // A 1px tolerance keeps sub-pixel layout rounding from leaving a hairline
    // fade stuck on at either end.
    final up = position.pixels > position.minScrollExtent + 1;
    final down = position.pixels < position.maxScrollExtent - 1;
    if (up != _canScrollUp || down != _canScrollDown) {
      setState(() {
        _canScrollUp = up;
        _canScrollDown = down;
      });
    }
  }

  Widget _edgeFade({required bool top, required bool visible}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            height: widget.fadeExtent,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  widget.fadeColor,
                  widget.fadeColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _syncEdges();
          return false;
        },
        child: Stack(
          children: [
            ListView(
              controller: _controller,
              // shrinkWrap keeps the list its natural height when the content
              // is shorter than the cap, so short races render exactly as they
              // did before this widget existed.
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              // Clamping (not bouncing) so the inner list doesn't rubber-band
              // against the page's own scroll view underneath it.
              physics: const ClampingScrollPhysics(),
              children: widget.children,
            ),
            _edgeFade(top: true, visible: _canScrollUp),
            _edgeFade(top: false, visible: _canScrollDown),
          ],
        ),
      ),
    );
  }
}
