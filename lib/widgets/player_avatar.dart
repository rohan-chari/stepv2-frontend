import 'package:flutter/material.dart';
import '../styles.dart';

const _friendColors = [
  Color(0xFFE57373), // red
  Color(0xFF64B5F6), // blue
  Color(0xFFFFB74D), // orange
  Color(0xFFBA68C8), // purple
  Color(0xFF4DB6AC), // teal
  Color(0xFFFF8A65), // deep orange
  Color(0xFF7986CB), // indigo
  Color(0xFFA1887F), // brown
  Color(0xFF4DD0E1), // cyan
  Color(0xFFAED581), // lime
];

/// A colored circle with 2-letter initials for player identification.
class PlayerAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isUser;
  final bool isStealthed;

  const PlayerAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.isUser = false,
    this.isStealthed = false,
  });

  Color get color => isStealthed
      ? const Color(0xFF9E9E9E)
      : isUser
          ? AppColors.pillGreen
          : _friendColors[name.hashCode.abs() % _friendColors.length];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          _initials,
          style: PixelText.title(
            size: size * 0.32,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
