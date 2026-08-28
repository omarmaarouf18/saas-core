import 'package:flutter/material.dart';
import '../core/theme.dart';

enum AppShellChromeStyle {
  transparent,
  brandNavy,
  surfaceElevated,
}

/// AppShell is the unified composition root for screens across the application.
/// It standardizes:
/// - AppBar presentation (height, typography, leading back button, actions, optional subtitle, TabBar)
/// - SafeArea integration
/// - Standard horizontal/vertical padding from [AppSpacing]
/// - BottomNavigationBar, Drawer, and FloatingActionButton placement
/// - Embedded tab mode ([isEmbeddedInTab]) to prevent nested app bar / scaffold conflicts
class AppShell extends StatelessWidget {
  /// Screen title displayed in the AppBar.
  final String? title;

  /// Optional subtitle displayed underneath the title in the AppBar.
  final String? subtitle;

  /// Optional custom title widget overriding [title] and [subtitle].
  final Widget? titleWidget;

  /// Custom leading widget for the AppBar. Defaults to a back button if [showBackButton] is true or navigatable.
  final Widget? leading;

  /// Whether to display a back button in the AppBar when [leading] is null.
  final bool? showBackButton;

  /// Custom callback when the back button is pressed. Defaults to [Navigator.maybePop].
  final VoidCallback? onBackPressed;

  /// Action widgets displayed on the trailing end of the AppBar.
  final List<Widget>? actions;

  /// Primary body content of the screen.
  final Widget body;

  /// Optional custom AppBar widget overriding default AppBar construction.
  final PreferredSizeWidget? customAppBar;

  /// Optional bottom widget for the AppBar (e.g., [TabBar]).
  final PreferredSizeWidget? bottom;

  /// Navigation bar displayed at the bottom of the screen.
  final Widget? bottomNavigationBar;

  /// Floating action button.
  final Widget? floatingActionButton;

  /// Position of the floating action button.
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// Drawer widget accessible via swipe or menu button.
  final Widget? drawer;

  /// End drawer widget.
  final Widget? endDrawer;

  /// Whether this screen is embedded within a parent navigation tab (IndexedStack/TabBar).
  /// When true, top AppBar and bottom navigation are omitted to prevent duplicate navigation chrome.
  final bool isEmbeddedInTab;

  /// Whether to wrap the body in a [SafeArea]. Defaults to true.
  final bool useSafeArea;

  /// SafeArea configuration.
  final bool safeAreaTop;
  final bool safeAreaBottom;
  final bool safeAreaLeft;
  final bool safeAreaRight;

  /// Optional padding applied around the body. If null, body receives no additional outer padding.
  final EdgeInsetsGeometry? padding;

  /// Background color of the Scaffold canvas. Defaults to theme's scaffold background.
  final Color? backgroundColor;

  /// Background color of the AppBar. Defaults to [AppColors.primary].
  final Color? appBarBackgroundColor;

  /// Foreground / icon / text color of the AppBar. Defaults to [AppColors.onPrimary].
  final Color? appBarForegroundColor;

  /// Elevation of the AppBar. Defaults to 0 (flat per Stitch design system).
  final double appBarElevation;

  /// Whether the body should resize when the software keyboard appears.
  final bool? resizeToAvoidBottomInset;

  /// Whether title should be centered in the AppBar. Defaults to false.
  final bool centerTitle;

  /// Explicit styling for the AppBar chrome.
  /// When null, chrome style is auto-inferred based on navigation hierarchy:
  /// - [showBackButton] == false (top-level tab root): [AppShellChromeStyle.transparent]
  /// - [showBackButton] == true (pushed/detail screen): [AppShellChromeStyle.surfaceElevated]
  final AppShellChromeStyle? chromeStyle;

  const AppShell({
    super.key,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.leading,
    this.showBackButton,
    this.onBackPressed,
    this.actions,
    required this.body,
    this.customAppBar,
    this.bottom,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.endDrawer,
    this.isEmbeddedInTab = false,
    this.useSafeArea = true,
    this.safeAreaTop = true,
    this.safeAreaBottom = true,
    this.safeAreaLeft = true,
    this.safeAreaRight = true,
    this.padding,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.appBarElevation = 0,
    this.resizeToAvoidBottomInset,
    this.centerTitle = false,
    this.chromeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBg = backgroundColor ?? theme.scaffoldBackgroundColor;

    Widget content = body;

    if (padding != null) {
      content = Padding(
        padding: padding!,
        child: content,
      );
    }

    if (useSafeArea) {
      content = SafeArea(
        top: safeAreaTop,
        bottom: safeAreaBottom,
        left: safeAreaLeft,
        right: safeAreaRight,
        child: content,
      );
    }

    if (isEmbeddedInTab) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        body: content,
      );
    }

    final PreferredSizeWidget? resolvedAppBar =
        customAppBar ?? _buildDefaultAppBar(context, theme);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: resolvedAppBar,
      body: content,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      drawer: drawer,
      endDrawer: endDrawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }

  PreferredSizeWidget? _buildDefaultAppBar(
      BuildContext context, ThemeData theme) {
    final hasTitle = titleWidget != null || title != null || subtitle != null;
    final hasActions = actions != null && actions!.isNotEmpty;
    final hasBottom = bottom != null;
    final canPop = Navigator.canPop(context);
    final shouldShowBack = showBackButton ?? canPop;

    if (!hasTitle &&
        !hasActions &&
        !hasBottom &&
        leading == null &&
        !shouldShowBack) {
      return null;
    }

    final AppShellChromeStyle effectiveStyle;
    if (chromeStyle != null) {
      effectiveStyle = chromeStyle!;
    } else if (appBarBackgroundColor == Colors.transparent) {
      effectiveStyle = AppShellChromeStyle.transparent;
    } else if (appBarBackgroundColor == AppColors.primary) {
      effectiveStyle = AppShellChromeStyle.brandNavy;
    } else if (appBarBackgroundColor != null) {
      effectiveStyle = AppShellChromeStyle.surfaceElevated;
    } else {
      effectiveStyle = shouldShowBack
          ? AppShellChromeStyle.surfaceElevated
          : AppShellChromeStyle.transparent;
    }

    final Color effectiveBg;
    if (appBarBackgroundColor != null) {
      effectiveBg = appBarBackgroundColor!;
    } else {
      switch (effectiveStyle) {
        case AppShellChromeStyle.transparent:
          effectiveBg = Colors.transparent;
          break;
        case AppShellChromeStyle.brandNavy:
          effectiveBg = AppColors.primary;
          break;
        case AppShellChromeStyle.surfaceElevated:
          effectiveBg = theme.colorScheme.surface;
          break;
      }
    }

    final Color effectiveFg;
    if (appBarForegroundColor != null) {
      effectiveFg = appBarForegroundColor!;
    } else {
      switch (effectiveStyle) {
        case AppShellChromeStyle.transparent:
          effectiveFg = theme.colorScheme.onSurface;
          break;
        case AppShellChromeStyle.brandNavy:
          effectiveFg = AppColors.onPrimary;
          break;
        case AppShellChromeStyle.surfaceElevated:
          effectiveFg = theme.colorScheme.onSurface;
          break;
      }
    }

    final PreferredSizeWidget? effectiveBottom;
    if (bottom != null) {
      effectiveBottom = bottom;
    } else if (effectiveStyle == AppShellChromeStyle.surfaceElevated) {
      effectiveBottom = PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          height: 1.0,
        ),
      );
    } else {
      effectiveBottom = null;
    }

    Widget? effectiveTitle = titleWidget;
    if (effectiveTitle == null) {
      if (title != null && subtitle != null) {
        effectiveTitle = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centerTitle
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              title!,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: effectiveFg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle!,
              style: AppTypography.labelMd.copyWith(
                color: effectiveFg.withValues(alpha: 0.8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      } else if (title != null) {
        effectiveTitle = Text(
          title!,
          style: AppTypography.titleMd.copyWith(
            fontWeight: FontWeight.bold,
            color: effectiveFg,
          ),
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && shouldShowBack) {
      effectiveLeading = IconButton(
        icon: const Icon(Icons.arrow_back),
        color: effectiveFg,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onBackPressed ?? () => Navigator.maybePop(context),
      );
    }

    return AppBar(
      title: effectiveTitle,
      centerTitle: centerTitle,
      leading: effectiveLeading,
      automaticallyImplyLeading: leading == null && showBackButton == null,
      actions: actions,
      bottom: effectiveBottom,
      backgroundColor: effectiveBg,
      foregroundColor: effectiveFg,
      elevation: appBarElevation,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    );
  }
}
