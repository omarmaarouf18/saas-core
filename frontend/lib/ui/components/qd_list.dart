import 'package:flutter/material.dart';

import '../tokens.dart';

/// Bordered group of [QdListTile]s with dividers inset to the title column,
/// like the settings and team lists in the mockups.
class QdListGroup extends StatelessWidget {
  const QdListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      rows.add(child);
      if (i < children.length - 1) {
        final inset = child is QdListTile ? child.dividerInset : 0.0;
        rows.add(Padding(
          padding: EdgeInsetsDirectional.only(start: inset),
          child: Container(height: 1, color: c.fillMuted),
        ));
      }
    }
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QdRadius.card),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// One row of a [QdListGroup].
///
/// Leading: an [icon] (20 dp, settings rows) or any [leading] widget such
/// as a [QdAvatarInitial] (whose width must be given as [leadingWidth]).
/// Trailing, in reading order: [value] text, [badge] (e.g. a status chip),
/// a switch when [switchValue] is set, and a [chevron].
class QdListTile extends StatelessWidget {
  const QdListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.leadingWidth = 40,
    this.value,
    this.badge,
    this.switchValue,
    this.onSwitchChanged,
    this.chevron = false,
    this.onTap,
    this.enabled = true,
    this.subtitleColor,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final double leadingWidth;
  final String? value;
  final Widget? badge;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final bool chevron;
  final VoidCallback? onTap;

  /// Disabled rows (e.g. "Wallet · coming soon") use secondary text and
  /// ignore taps.
  final bool enabled;

  /// Override for a warning subtitle ("Documents missing").
  final Color? subtitleColor;

  static const double _gap = QdSpace.x3;

  double get _hPad => icon != null && leading == null ? 14 : QdSpace.x4;

  /// Start inset of the divider below this row: aligned with the title.
  double get dividerInset {
    if (leading != null) return _hPad + leadingWidth + _gap;
    if (icon != null) return _hPad + QdSize.icon + _gap;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final titleColor = enabled ? c.textPrimary : c.textSecondary;
    final hasSwitch = switchValue != null;
    final tall = subtitle != null || leading != null;

    final children = <Widget>[
      if (leading != null) ...[
        ExcludeSemantics(child: leading!),
        const SizedBox(width: _gap),
      ] else if (icon != null) ...[
        Icon(icon, size: QdSize.icon, color: titleColor),
        const SizedBox(width: _gap),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: (subtitle != null
                      ? QdText.rowTitleSm
                      : QdText.body.copyWith(fontSize: 15))
                  .copyWith(color: titleColor),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(
                subtitle!,
                style: QdText.caption
                    .copyWith(color: subtitleColor ?? c.textSecondary),
              ),
            ],
          ],
        ),
      ),
      if (value != null) ...[
        const SizedBox(width: QdSpace.x2),
        Text(value!, style: QdText.secondary.copyWith(color: c.textSecondary)),
      ],
      if (badge != null) ...[
        const SizedBox(width: QdSpace.x2),
        badge!,
      ],
      if (hasSwitch) ...[
        const SizedBox(width: QdSpace.x2),
        Switch(
          value: switchValue!,
          onChanged: enabled ? onSwitchChanged : null,
          activeTrackColor: c.navy,
          activeThumbColor: c.surface,
          inactiveTrackColor: c.fillMuted,
          inactiveThumbColor: c.textSecondary,
          trackOutlineColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.navy : c.borderInput),
        ),
      ],
      if (chevron) ...[
        const SizedBox(width: QdSpace.x1),
        // chevron_right mirrors itself in RTL (matchTextDirection).
        Icon(Icons.chevron_right, size: QdSize.icon, color: c.textSecondary),
      ],
    ];

    VoidCallback? tap = enabled ? onTap : null;
    if (tap == null && hasSwitch && enabled && onSwitchChanged != null) {
      tap = () => onSwitchChanged!(!switchValue!);
    }

    return Semantics(
      container: true,
      button: tap != null && !hasSwitch,
      enabled: enabled,
      child: InkWell(
        onTap: tap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tall ? 64 : QdSize.listRow),
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: _hPad,
              vertical: QdSpace.x2,
            ),
            child: Row(children: children),
          ),
        ),
      ),
    );
  }
}
