import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'app_shell.dart';
import 'themed_empty_state.dart';
import 'themed_error_banner.dart';
import 'themed_loading_indicator.dart';

/// ListScreenTemplate is a standardized composition template for list-driven screens.
/// It encapsulates:
/// - Screen scaffold & navigation chrome via [AppShell]
/// - Standard loading, empty, and error state transitions with [AnimatedSwitcher]
/// - Configurable pull-to-refresh ([RefreshIndicator])
/// - Standard list item rhythm and separators using [AppSpacing]
/// - Optional top/pinned header (e.g., search/filters/metrics) and footer
class ListScreenTemplate<T> extends StatelessWidget {
  // --- AppShell Navigation & Chrome Properties ---
  final String? title;
  final String? subtitle;
  final Widget? titleWidget;
  final Widget? leading;
  final bool? showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final PreferredSizeWidget? customAppBar;
  final PreferredSizeWidget? bottom;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool isEmbeddedInTab;
  final bool useSafeArea;
  final Color? backgroundColor;
  final Color? appBarBackgroundColor;
  final Color? appBarForegroundColor;
  final double appBarElevation;
  final bool? resizeToAvoidBottomInset;
  final bool centerTitle;

  // --- Data & State Properties ---
  /// The collection of data items to display.
  final List<T>? items;

  /// Whether the data is currently being fetched or reloaded.
  final bool isLoading;

  /// Optional error message to surface when loading or refreshing fails.
  final String? errorMessage;

  /// Callback to retry fetching data after an error.
  final VoidCallback? onRetry;

  /// Callback for pull-to-refresh gesture.
  final Future<void> Function()? onRefresh;

  // --- Header, Footer & List Layout ---
  /// Optional widget pinned above the list content (e.g., search bar, filters).
  final Widget? header;

  /// Optional widget placed below the list content.
  final Widget? footer;

  /// Builder for rendering each item in [items].
  final Widget Function(BuildContext context, T item, int index)? itemBuilder;

  /// Optional builder for custom list separator. If null, standard spacing is applied.
  final Widget Function(BuildContext context, int index)? separatorBuilder;

  /// Vertical spacing between list items when [separatorBuilder] is null. Defaults to [AppSpacing.sm].
  final double itemSpacing;

  /// Padding applied around the list view. Defaults to horizontal [AppSpacing.marginMobile] and vertical [AppSpacing.md].
  final EdgeInsetsGeometry? listPadding;

  /// Scroll physics for the list view. Defaults to [AlwaysScrollableScrollPhysics].
  final ScrollPhysics physics;

  /// Optional scroll controller for the list.
  final ScrollController? scrollController;

  /// Whether the scroll view should shrink wrap its contents. Defaults to false.
  final bool shrinkWrap;

  // --- State Customization ---
  /// Custom loading widget overriding default [ThemedLoadingIndicator].
  final Widget? loadingWidget;

  /// Custom loading message shown below spinner when [loadingWidget] is null.
  final String? loadingMessage;

  /// Custom empty widget overriding default [ThemedEmptyState].
  final Widget? emptyWidget;

  /// Icon displayed in the default empty state. Defaults to [Icons.inbox_outlined].
  final IconData emptyIcon;

  /// Title displayed in the default empty state.
  final String emptyTitle;

  /// Description displayed in the default empty state.
  final String emptyDescription;

  /// Optional button text for action in empty state.
  final String? emptyActionText;

  /// Optional callback when empty state action button is pressed.
  final VoidCallback? onEmptyActionPressed;

  /// Custom error widget overriding default [ThemedErrorBanner].
  final Widget? errorWidget;

  const ListScreenTemplate({
    super.key,
    // Chrome / Shell
    this.title,
    this.subtitle,
    this.titleWidget,
    this.leading,
    this.showBackButton,
    this.onBackPressed,
    this.actions,
    this.customAppBar,
    this.bottom,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.endDrawer,
    this.isEmbeddedInTab = false,
    this.useSafeArea = true,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.appBarElevation = 0,
    this.resizeToAvoidBottomInset,
    this.centerTitle = false,
    // State & Data
    required this.items,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    // List & Layout
    this.header,
    this.footer,
    this.itemBuilder,
    this.separatorBuilder,
    this.itemSpacing = AppSpacing.sm,
    this.listPadding,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.scrollController,
    this.shrinkWrap = false,
    // Custom States
    this.loadingWidget,
    this.loadingMessage,
    this.emptyWidget,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'No items found',
    this.emptyDescription = 'There are no items to display at this time.',
    this.emptyActionText,
    this.onEmptyActionPressed,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      titleWidget: titleWidget,
      leading: leading,
      showBackButton: showBackButton,
      onBackPressed: onBackPressed,
      actions: actions,
      customAppBar: customAppBar,
      bottom: bottom,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      drawer: drawer,
      endDrawer: endDrawer,
      isEmbeddedInTab: isEmbeddedInTab,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      appBarBackgroundColor: appBarBackgroundColor,
      appBarForegroundColor: appBarForegroundColor,
      appBarElevation: appBarElevation,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      centerTitle: centerTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header!,
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.durationMedium,
              switchInCurve: AppMotion.curveStateChange,
              switchOutCurve: AppMotion.curveStateChange,
              child: _buildStateBody(context),
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }

  Widget _buildStateBody(BuildContext context) {
    final currentItems = items;

    // 1. Initial Loading State (when no items exist yet)
    if (isLoading && (currentItems == null || currentItems.isEmpty)) {
      return loadingWidget ??
          ThemedLoadingIndicator(
            key: const ValueKey('list_template_loading'),
            message: loadingMessage,
          );
    }

    // 2. Error State (when items are empty)
    if (errorMessage != null &&
        (currentItems == null || currentItems.isEmpty)) {
      if (errorWidget != null) {
        return errorWidget!;
      }
      final errorContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ThemedErrorBanner(
            key: const ValueKey('list_template_error'),
            message: errorMessage!,
            onRetry: onRetry,
          ),
        ),
      );

      if (onRefresh != null) {
        return RefreshIndicator(
          onRefresh: onRefresh!,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: AppSpacing.xl),
              errorContent,
            ],
          ),
        );
      }
      return errorContent;
    }

    // 3. Empty State
    if (currentItems == null || currentItems.isEmpty) {
      final emptyContent = emptyWidget ??
          ThemedEmptyState(
            key: const ValueKey('list_template_empty'),
            icon: emptyIcon,
            title: emptyTitle,
            description: emptyDescription,
            actionText: emptyActionText,
            onActionPressed: onEmptyActionPressed,
          );

      if (onRefresh != null) {
        return RefreshIndicator(
          onRefresh: onRefresh!,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: AppSpacing.xl),
              emptyContent,
            ],
          ),
        );
      }
      return emptyContent;
    }

    // 4. Loaded List State
    final effectivePadding = listPadding ??
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile,
          vertical: AppSpacing.md,
        );

    Widget listView = ListView.separated(
      key: const ValueKey('list_template_list'),
      controller: scrollController,
      physics: physics,
      shrinkWrap: shrinkWrap,
      padding: effectivePadding,
      itemCount: currentItems.length,
      separatorBuilder:
          separatorBuilder ?? (context, index) => SizedBox(height: itemSpacing),
      itemBuilder: (context, index) {
        if (itemBuilder != null) {
          return itemBuilder!(context, currentItems[index], index);
        }
        return const SizedBox.shrink();
      },
    );

    if (onRefresh != null) {
      listView = RefreshIndicator(
        onRefresh: onRefresh!,
        child: listView,
      );
    }

    return listView;
  }
}
