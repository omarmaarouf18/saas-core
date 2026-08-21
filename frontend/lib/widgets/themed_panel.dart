import 'package:flutter/material.dart';

/// ThemedPanel is the single sanctioned primitive for bespoke decorated
/// containers inside screens: tinted chips, circular icon badges, callout
/// boxes, hero gradient banners, progress segments, and similar surfaces.
///
/// Screens must not construct [BoxDecoration] directly — route card-like
/// surfaces through [ThemedCard] and every other decorated container through
/// this widget, so decoration policy stays owned centrally by the design
/// system layer.
class ThemedPanel extends StatelessWidget {
  final Widget? child;

  /// Fill color. Ignored when [gradient] is provided (matching BoxDecoration).
  final Color? color;

  /// Optional gradient fill (e.g. hero banners).
  final Gradient? gradient;

  /// Corner radius. Must be null when [shape] is [BoxShape.circle].
  final BorderRadiusGeometry? borderRadius;

  /// Shape of the panel. Defaults to [BoxShape.rectangle].
  final BoxShape shape;

  /// Optional outline border.
  final Border? border;

  /// Optional drop shadow (use [AppElevation] token lists).
  final List<BoxShadow>? boxShadow;

  /// Inner padding around [child].
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Fixed width.
  final double? width;

  /// Fixed height.
  final double? height;

  /// Alignment of [child] within the panel.
  final AlignmentGeometry? alignment;

  /// Size constraints (e.g. minimum badge sizes).
  final BoxConstraints? constraints;

  /// Clip behavior for overflowing children. Defaults to [Clip.none].
  final Clip clipBehavior;

  /// Optional tap handler wrapping the panel in an [InkWell].
  final VoidCallback? onTap;

  const ThemedPanel({
    super.key,
    this.child,
    this.color,
    this.gradient,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.border,
    this.boxShadow,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.constraints,
    this.clipBehavior = Clip.none,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Decoration decoration;
    if (shape == BoxShape.circle) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        gradient: gradient,
        border: border,
        boxShadow: boxShadow,
      );
    } else {
      decoration = BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: borderRadius,
        border: border,
        boxShadow: boxShadow,
      );
    }

    Widget content = Container(
      width: width,
      height: height,
      constraints: constraints,
      alignment: alignment,
      margin: margin,
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: decoration,
      child: child,
    );

    if (onTap != null) {
      final BorderRadius? inkRadius =
          borderRadius is BorderRadius ? borderRadius as BorderRadius : null;
      content = InkWell(
        onTap: onTap,
        borderRadius: shape == BoxShape.circle ? null : inkRadius,
        child: content,
      );
    }

    return content;
  }
}

/// Animated variant of [ThemedPanel] providing implicit decoration
/// transitions (color, border, radius) equivalent to Flutter's
/// AnimatedContainer, while keeping decoration construction inside the
/// shared widgets layer.
class AnimatedThemedPanel extends ImplicitlyAnimatedWidget {
  final Widget? child;
  final Color? color;
  final Gradient? gradient;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final BoxConstraints? constraints;
  final Clip clipBehavior;
  final VoidCallback? onTap;

  const AnimatedThemedPanel({
    super.key,
    this.child,
    this.color,
    this.gradient,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.border,
    this.boxShadow,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.constraints,
    this.clipBehavior = Clip.none,
    this.onTap,
    required super.duration,
    super.curve = Curves.easeInOut,
  });

  @override
  AnimatedWidgetBaseState<AnimatedThemedPanel> createState() =>
      _AnimatedThemedPanelState();
}

class _AnimatedThemedPanelState
    extends AnimatedWidgetBaseState<AnimatedThemedPanel> {
  DecorationTween? _decoration;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    final Decoration target = _resolveDecoration(
      widget.color,
      widget.gradient,
      widget.borderRadius,
      widget.shape,
      widget.border,
      widget.boxShadow,
    );
    _decoration = visitor(
          _decoration,
          target,
          (value) => DecorationTween(begin: value as Decoration),
        )
        as DecorationTween?;
  }

  static Decoration _resolveDecoration(
    Color? color,
    Gradient? gradient,
    BorderRadiusGeometry? borderRadius,
    BoxShape shape,
    Border? border,
    List<BoxShadow>? boxShadow,
  ) {
    if (shape == BoxShape.circle) {
      return BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        gradient: gradient,
        border: border,
        boxShadow: boxShadow,
      );
    }
    return BoxDecoration(
      color: color,
      gradient: gradient,
      borderRadius: borderRadius,
      border: border,
      boxShadow: boxShadow,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      width: widget.width,
      height: widget.height,
      constraints: widget.constraints,
      alignment: widget.alignment,
      margin: widget.margin,
      padding: widget.padding,
      clipBehavior: widget.clipBehavior,
      decoration: _decoration!.evaluate(animation),
      child: widget.child,
    );

    if (widget.onTap != null) {
      content = InkWell(
        onTap: widget.onTap,
        child: content,
      );
    }

    return content;
  }
}
