import 'package:flutter/material.dart';
import '../core/theme.dart';

class PillFilterItem<T> {
  final String label;
  final T value;
  final IconData? icon;
  final int? count;

  const PillFilterItem({
    required this.label,
    required this.value,
    this.icon,
    this.count,
  });
}

class PillFilterBar<T> extends StatelessWidget {
  final List<PillFilterItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;
  final bool isDarkSelected;

  const PillFilterBar({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    this.isDarkSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.value == selectedValue;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.base),
            child: _PillFilterChip<T>(
              item: item,
              isSelected: isSelected,
              isDarkSelected: isDarkSelected,
              onTap: () => onSelected(item.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PillFilterChip<T> extends StatefulWidget {
  final PillFilterItem<T> item;
  final bool isSelected;
  final bool isDarkSelected;
  final VoidCallback onTap;

  const _PillFilterChip({
    required this.item,
    required this.isSelected,
    required this.isDarkSelected,
    required this.onTap,
  });

  @override
  State<_PillFilterChip<T>> createState() => _PillFilterChipState<T>();
}

class _PillFilterChipState<T> extends State<_PillFilterChip<T>> {
  DateTime? _lastTapTime;

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastTapTime = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedBg =
        widget.isDarkSelected ? AppColors.primary : AppColors.secondary;
    final Color selectedFg =
        widget.isDarkSelected ? AppColors.onPrimary : AppColors.onSecondary;

    final Color bgColor =
        widget.isSelected ? selectedBg : AppColors.surfaceContainerLowest;
    final Color fgColor =
        widget.isSelected ? selectedFg : AppColors.onSurfaceVariant;
    final Border? border = widget.isSelected
        ? null
        : Border.all(color: AppColors.outlineVariant, width: 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: border,
            boxShadow: widget.isSelected ? AppElevation.shadowLevel1List : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.item.icon != null) ...[
                Icon(
                  widget.item.icon,
                  size: AppIconSize.sm,
                  color: fgColor,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                widget.item.label,
                style: AppTypography.labelLg.copyWith(
                  color: fgColor,
                  fontWeight:
                      widget.isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (widget.item.count != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? fgColor.withValues(alpha: 0.2)
                        : AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.radiusSmMd),
                  ),
                  child: Text(
                    '${widget.item.count}',
                    style: AppTypography.labelSm.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
