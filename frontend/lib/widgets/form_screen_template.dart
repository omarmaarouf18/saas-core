import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'app_shell.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_card.dart';
import 'themed_error_banner.dart';

/// FormScreenTemplate is a standardized composition template for form-driven screens.
/// It encapsulates:
/// - Screen scaffold & navigation chrome via [AppShell]
/// - Standardized form field vertical rhythm and spacing using [AppSpacing]
/// - Pinned or inline header, brand chrome, and footer links
/// - Standard inline validation error display via [ThemedErrorBanner]
/// - Submitting and loading states that disable form interactions and animate button spinners
/// - Keyboard avoidance and scrollability via [SingleChildScrollView] + [AppShell.resizeToAvoidBottomInset]
/// - Embedded tab mode ([isEmbeddedInTab]) for screens rendered within tab shells (e.g., SettingsScreen)
class FormScreenTemplate extends StatelessWidget {
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
  final AppShellChromeStyle? chromeStyle;

  // --- Form Layout & Structure ---
  /// GlobalKey for form state validation. If provided, the form fields are wrapped in a [Form].
  final GlobalKey<FormState>? formKey;

  /// Ordered list of form field widgets rendered with [fieldSpacing] vertical spacing.
  /// Mutually exclusive with [body] when providing custom layout.
  final List<Widget>? children;

  /// Custom body widget overriding [children] construction.
  final Widget? body;

  /// Spacing between successive form field children. Defaults to [AppSpacing.md].
  final double fieldSpacing;

  /// Outer padding applied around the scrollable form content. Defaults to [EdgeInsets.all(AppSpacing.lg)].
  final EdgeInsetsGeometry padding;

  /// Optional widget rendered above the form fields (e.g. brand logo, top card, header text).
  final Widget? header;

  /// Optional widget rendered below the action buttons (e.g. alternative navigation links, disclaimers).
  final Widget? footer;

  /// Scroll physics for the form scroll view. Defaults to [AlwaysScrollableScrollPhysics].
  final ScrollPhysics physics;

  /// Optional scroll controller.
  final ScrollController? scrollController;

  /// Optional pull-to-refresh callback. When supplied, wraps the form scroll view in a [RefreshIndicator].
  final RefreshCallback? onRefresh;

  // --- Card Wrapping Option ---
  /// Whether to wrap the form fields in a [ThemedCard].
  final bool cardWrapper;

  /// Padding inside the card wrapper when [cardWrapper] is true. Defaults to [AppSpacing.lg].
  final double? cardPadding;

  /// Top accent color for the [ThemedCard] when [cardWrapper] is true.
  final Color? cardTopAccentColor;

  /// Top accent height for the [ThemedCard] when [cardWrapper] is true.
  final double cardTopAccentHeight;

  // --- Validation & Error Handling ---
  /// Optional error message to display at the top of the form fields.
  final String? errorMessage;

  /// Custom error banner widget overriding default [ThemedErrorBanner].
  final Widget? errorBanner;

  /// Optional retry callback passed to the error banner.
  final VoidCallback? onRetryError;

  // --- Submission & Action Buttons ---
  /// Whether the form is actively submitting. Disables form input and shows spinner on submit button.
  final bool isSubmitting;

  /// Whether the form is in a general loading state. Disables form input and shows spinner on submit button.
  final bool isLoading;

  /// Text displayed on the primary submit button.
  final String? submitButtonText;

  /// Callback when the primary submit button is pressed.
  final VoidCallback? onSubmit;

  /// Custom submit button overriding default [PrimaryButton].
  final Widget? submitButton;

  /// Key applied to the default [PrimaryButton].
  final Key? submitButtonKey;

  /// Leading icon for the default [PrimaryButton].
  final IconData? submitButtonIcon;

  /// Trailing icon for the default [PrimaryButton].
  final IconData? submitButtonTrailingIcon;

  /// Whether the primary submit button is enabled for interaction. Defaults to true.
  final bool isSubmitEnabled;

  /// Text displayed on the secondary action button.
  final String? secondaryButtonText;

  /// Callback when the secondary action button is pressed.
  final VoidCallback? onSecondaryAction;

  /// Custom secondary button overriding default [SecondaryButton].
  final Widget? secondaryButton;

  /// Key applied to the default [SecondaryButton].
  final Key? secondaryButtonKey;

  /// Icon for the default [SecondaryButton].
  final IconData? secondaryButtonIcon;

  /// Whether the default [SecondaryButton] is outlined. Defaults to false.
  final bool isSecondaryOutlined;

  /// Vertical spacing between the submit button and secondary button. Defaults to [AppSpacing.md].
  final double actionSpacing;

  /// Whether to disable all form child touch interactions during submission/loading via [IgnorePointer].
  /// Defaults to true.
  final bool disableOnSubmit;

  const FormScreenTemplate({
    super.key,
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
    this.resizeToAvoidBottomInset = true,
    this.centerTitle = false,
    this.formKey,
    this.children,
    this.body,
    this.fieldSpacing = AppSpacing.md,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.header,
    this.footer,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.scrollController,
    this.onRefresh,
    this.cardWrapper = false,
    this.cardPadding,
    this.cardTopAccentColor,
    this.cardTopAccentHeight = 4.0,
    this.errorMessage,
    this.errorBanner,
    this.onRetryError,
    this.isSubmitting = false,
    this.isLoading = false,
    this.submitButtonText,
    this.onSubmit,
    this.submitButton,
    this.submitButtonKey,
    this.submitButtonIcon,
    this.submitButtonTrailingIcon,
    this.isSubmitEnabled = true,
    this.secondaryButtonText,
    this.onSecondaryAction,
    this.secondaryButton,
    this.secondaryButtonKey,
    this.secondaryButtonIcon,
    this.isSecondaryOutlined = false,
    this.actionSpacing = AppSpacing.md,
    this.disableOnSubmit = true,
    this.chromeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final bool busy = isSubmitting || isLoading;

    // 1. Build error banner if present
    Widget? errorWidget;
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      errorWidget = errorBanner ??
          ThemedErrorBanner(
            key: const Key('form_template_error_banner'),
            message: errorMessage!,
            onRetry: onRetryError,
          );
    }

    // 2. Build submit button if text or widget supplied
    Widget? resolvedSubmitButton = submitButton;
    if (resolvedSubmitButton == null && submitButtonText != null) {
      resolvedSubmitButton = PrimaryButton(
        key: submitButtonKey ?? const Key('form_template_submit_button'),
        text: submitButtonText!,
        onPressed: (isSubmitEnabled && !busy) ? onSubmit : null,
        isLoading: busy,
        icon: submitButtonIcon,
        trailingIcon: submitButtonTrailingIcon,
      );
    }

    // 3. Build secondary button if text or widget supplied
    Widget? resolvedSecondaryButton = secondaryButton;
    if (resolvedSecondaryButton == null && secondaryButtonText != null) {
      resolvedSecondaryButton = SecondaryButton(
        key: secondaryButtonKey ?? const Key('form_template_secondary_button'),
        text: secondaryButtonText!,
        onPressed: busy ? null : onSecondaryAction,
        icon: secondaryButtonIcon,
        isOutlined: isSecondaryOutlined,
      );
    }

    // 4. Build form fields content
    Widget formContent;
    if (body != null) {
      formContent = body!;
    } else if (children != null) {
      final List<Widget> spacedChildren = [];
      for (int i = 0; i < children!.length; i++) {
        if (i > 0) {
          spacedChildren.add(SizedBox(height: fieldSpacing));
        }
        spacedChildren.add(children![i]);
      }

      final Widget columnContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: spacedChildren,
      );

      if (cardWrapper) {
        formContent = ThemedCard(
          padding: cardPadding ?? AppSpacing.lg,
          topAccentColor: cardTopAccentColor,
          topAccentHeight: cardTopAccentHeight,
          child: columnContent,
        );
      } else {
        formContent = columnContent;
      }
    } else {
      formContent = const SizedBox.shrink();
    }

    if (formKey != null) {
      formContent = Form(
        key: formKey,
        child: formContent,
      );
    }

    // 5. Assemble the complete vertical layout
    final List<Widget> assembledElements = [];

    if (header != null) {
      assembledElements.add(header!);
      assembledElements.add(SizedBox(height: fieldSpacing));
    }

    if (errorWidget != null) {
      assembledElements.add(errorWidget);
      assembledElements.add(SizedBox(height: fieldSpacing));
    }

    assembledElements.add(formContent);

    if (resolvedSubmitButton != null || resolvedSecondaryButton != null) {
      assembledElements.add(SizedBox(height: fieldSpacing));
      if (resolvedSubmitButton != null) {
        assembledElements.add(resolvedSubmitButton);
      }
      if (resolvedSecondaryButton != null) {
        if (resolvedSubmitButton != null) {
          assembledElements.add(SizedBox(height: actionSpacing));
        }
        assembledElements.add(resolvedSecondaryButton);
      }
    }

    if (footer != null) {
      assembledElements.add(SizedBox(height: fieldSpacing));
      assembledElements.add(footer!);
    }

    Widget scrollableBody = SingleChildScrollView(
      physics: physics,
      controller: scrollController,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: assembledElements,
      ),
    );

    if (onRefresh != null) {
      scrollableBody = RefreshIndicator(
        onRefresh: onRefresh!,
        child: scrollableBody,
      );
    }

    if (disableOnSubmit && busy) {
      scrollableBody = IgnorePointer(
        ignoring: true,
        child: scrollableBody,
      );
    }

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
      chromeStyle: chromeStyle,
      body: scrollableBody,
    );
  }
}
