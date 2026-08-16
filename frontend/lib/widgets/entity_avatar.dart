import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

class EntityAvatar extends StatefulWidget {
  final String? name;
  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final VoidCallback? onTap;
  final IconData defaultIcon;
  final DateTime Function()? nowProvider;

  const EntityAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.radius = 20.0,
    this.backgroundColor,
    this.foregroundColor,
    this.onTap,
    this.defaultIcon = Icons.person,
    this.nowProvider,
  });

  @override
  State<EntityAvatar> createState() => _EntityAvatarState();
}

class _EntityAvatarState extends State<EntityAvatar> {
  DateTime? _lastTapTime;

  String get _initials {
    if (widget.name == null || widget.name!.trim().isEmpty) return '';
    final parts = widget.name!.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts[0]
          .substring(0, parts[0].length > 2 ? 2 : parts[0].length)
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    final now =
        widget.nowProvider != null ? widget.nowProvider!() : DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastTapTime = now;
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppColors.primary;
    final fg = widget.foregroundColor ?? AppColors.onPrimary;
    final initialsStr = _initials;

    Widget avatarContent;
    if (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        backgroundImage: NetworkImage(widget.imageUrl!),
        onForegroundImageError: (_, __) {},
        child: initialsStr.isNotEmpty
            ? Text(
                initialsStr,
                style: GoogleFonts.poppins(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.radius * 0.8,
                ),
              )
            : Icon(
                widget.defaultIcon,
                size: widget.radius * 1.1,
                color: fg,
              ),
      );
    } else if (initialsStr.isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: Text(
          initialsStr,
          style: GoogleFonts.poppins(
            color: fg,
            fontWeight: FontWeight.bold,
            fontSize: widget.radius * 0.8,
          ),
        ),
      );
    } else {
      avatarContent = CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: Icon(
          widget.defaultIcon,
          size: widget.radius * 1.1,
          color: fg,
        ),
      );
    }

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: _handleTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }
}
