import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

class QdNavItem {
  const QdNavItem({required this.icon, required this.label, this.activeIcon});

  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// Bottom navigation: 3–4 items, a 20×3 gold bar under the active one.
class QdBottomNav extends StatelessWidget {
  const QdBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length >= 3 && items.length <= 4,
            'QdBottomNav takes 3 or 4 items');

  final List<QdNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.qdMainNavigation,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: QdSpace.x3),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                QdSpace.x2, 6, QdSpace.x2, QdSpace.x1),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(child: _item(c, i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(QdColors c, int i) {
    final item = items[i];
    final active = i == currentIndex;
    final color = active ? c.textPrimary : c.textSecondary;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      onTap: () => onTap(i),
      child: InkWell(
        onTap: () => onTap(i),
        borderRadius: BorderRadius.circular(QdRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? (item.activeIcon ?? item.icon) : item.icon,
                size: QdSize.iconLg,
                color: color,
              ),
              const SizedBox(height: QdSpace.x1),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QdText.caption.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: QdSpace.x1),
              Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: active ? c.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
