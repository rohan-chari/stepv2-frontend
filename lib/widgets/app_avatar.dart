import 'package:flutter/material.dart';

import '../styles.dart';

const _avatarPalette = [
  Color(0xFFE57373),
  Color(0xFF64B5F6),
  Color(0xFFFFB74D),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
  Color(0xFFFF8A65),
  Color(0xFF7986CB),
  Color(0xFFA1887F),
  Color(0xFF4DD0E1),
  Color(0xFFAED581),
];

String avatarInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '??';

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
}

Color avatarColorForName(
  String name, {
  bool isUser = false,
  bool isStealthed = false,
}) {
  if (isStealthed) {
    return const Color(0xFF9E9E9E);
  }
  if (isUser) {
    return AppColors.pillGreen;
  }
  return _avatarPalette[name.hashCode.abs() % _avatarPalette.length];
}

class AppAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final bool isUser;
  final bool isStealthed;
  final Color? borderColor;
  final double borderWidth;
  final double? fontSize;

  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 36,
    this.isUser = false,
    this.isStealthed = false,
    this.borderColor,
    this.borderWidth = 2,
    this.fontSize,
  });

  Color get _fallbackColor => avatarColorForName(
    name,
    isUser: isUser,
    isStealthed: isStealthed,
  );

  bool get _hasImage =>
      !isStealthed && imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _fallbackColor,
        border: Border.all(color: effectiveBorderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: _fallbackColor.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _hasImage
          ? Image.network(
              imageUrl!.trim(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallback(),
            )
          : _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        isStealthed ? '??' : avatarInitials(name),
        style: PixelText.title(
          size: fontSize ?? size * 0.32,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ProfileAvatarButton extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final VoidCallback? onPressed;
  final double size;

  const ProfileAvatarButton({
    super.key,
    required this.name,
    this.imageUrl,
    this.onPressed,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AppAvatar(
        name: name,
        imageUrl: imageUrl,
        size: size,
        isUser: true,
        borderColor: AppColors.parchment,
        borderWidth: 2.25,
      ),
    );
  }
}
