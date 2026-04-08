import 'package:flutter/material.dart';
import 'app_avatar.dart';

/// A colored circle with 2-letter initials for player identification.
class PlayerAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final bool isUser;
  final bool isStealthed;

  const PlayerAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 36,
    this.isUser = false,
    this.isStealthed = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppAvatar(
      name: name,
      imageUrl: imageUrl,
      size: size,
      isUser: isUser,
      isStealthed: isStealthed,
    );
  }
}
