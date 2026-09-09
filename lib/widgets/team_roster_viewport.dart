import 'package:flutter/material.dart';

/// Keeps the first five full-sized rows visible; each team scrolls separately.
/// Measures actual rows so larger accessibility text never shrinks targets.
class TeamRosterViewport extends StatefulWidget {
  const TeamRosterViewport({super.key, required this.rows, this.gap = 4});
  final List<Widget> rows;
  final double gap;

  @override
  State<TeamRosterViewport> createState() => _TeamRosterViewportState();
}

class _TeamRosterViewportState extends State<TeamRosterViewport> {
  final _controller = ScrollController();
  final _rowKeys = List.generate(5, (_) => GlobalKey());
  double _height = 416;
  bool _measurementScheduled = false;

  void _measure() {
    if (_measurementScheduled || widget.rows.length <= 5) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted || widget.rows.length <= 5) return;
      final sizes = _rowKeys.map((key) => key.currentContext?.size).toList();
      if (sizes.any((size) => size == null)) return;
      final height = sizes.fold<double>(
        widget.gap * 4,
        (sum, size) => sum + (size?.height ?? 0),
      );
      if ((_height - height).abs() > 0.5) setState(() => _height = height);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.rows.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          KeyedSubtree(key: i < 5 ? _rowKeys[i] : null, child: widget.rows[i]),
        ],
      ],
    );
    if (widget.rows.length <= 5) return column;
    return SizedBox(
      height: _height,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _controller,
          primary: false,
          child: column,
        ),
      ),
    );
  }
}
