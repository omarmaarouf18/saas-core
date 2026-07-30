import 'package:flutter/material.dart';
import '../core/theme.dart';

class EntityAvatar extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final VoidCallback? onTap;
  final IconData defaultIcon;

  const EntityAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = 20.0,
    this.backgroundColor,
    this.foregroundColor,
    this.onTap,
    this.defaultIcon = Icons.person,
  });

  String get _initials {
    if (name == null || name!.trim().isEmpty) return '';
    final parts = name!.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts[0]
          .substring(0, parts[0].length > 2 ? 2 : parts[0].length)
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary;
    final fg = foregroundColor ?? AppColors.onPrimary;
    final initialsStr = _initials;

    Widget avatarContent;
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: NetworkImage(imageUrl!),
        onForegroundImageError: (_, __) {},
        child: initialsStr.isNotEmpty
            ? Text(
                initialsStr,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.8,
                ),
              )
            : Icon(
                defaultIcon,
                size: radius * 1.1,
                color: fg,
              ),
      );
    } else if (initialsStr.isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          initialsStr,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.8,
          ),
        ),
      );
    } else {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Icon(
          defaultIcon,
          size: radius * 1.1,
          color: fg,
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }
}
