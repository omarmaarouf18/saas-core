import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/app_shell.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';

class RatingScreen extends StatefulWidget {
  final Job job;

  const RatingScreen({super.key, required this.job});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _selectedStars = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingOtherStatus = true;
  bool _otherPartyHasRated = false;
  String _otherPartyName = "Driver / Employee";
  String _otherPartyRole = "Specialist";
  String? _otherPartyId;

  @override
  void initState() {
    super.initState();
    _determineParties();
    _checkOtherPartyRatingStatus();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _determineParties() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user != null) {
      if (user.role == 'employee') {
        // Employee is rating the Owner (customer)
        _otherPartyId = widget.job.ownerId;
        _otherPartyName = "Client / Owner";
        _otherPartyRole = "Owner";
      } else {
        // Owner/Customer is rating the Employee (driver)
        _otherPartyId = widget.job.employeeId;
        _otherPartyName = "Driver / Employee";
        _otherPartyRole = "Specialist";
      }
    }
  }

  Future<void> _checkOtherPartyRatingStatus() async {
    setState(() {
      _isLoadingOtherStatus = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final marketplaceProvider =
        Provider.of<MarketplaceProvider>(context, listen: false);

    try {
      // Fetch ratings received by the current user
      final res = await marketplaceProvider.fetchRatings(auth.token!);
      final list = res['ratings'] as List<dynamic>? ?? [];

      bool found = false;
      for (var item in list) {
        if (item is Map && item['job_id'] == widget.job.id) {
          // If we received a rating for this job from the other party
          if (item['rated_by'] == _otherPartyId) {
            found = true;
            break;
          }
        }
      }

      setState(() {
        _otherPartyHasRated = found;
        _isLoadingOtherStatus = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingOtherStatus = false;
      });
    }
  }

  Future<void> _submitRating() async {
    if (_otherPartyId == null) {
      final l10n = AppLocalizations.of(context)!;
      ThemedSnackBar.showError(context, l10n.ratingIdentityError);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final marketplaceProvider =
        Provider.of<MarketplaceProvider>(context, listen: false);

    try {
      await marketplaceProvider.rateJob(
        jobId: widget.job.id,
        ratedByToken: auth.token!,
        ratedUserId: _otherPartyId!,
        stars: _selectedStars,
        comment: _commentController.text.trim(),
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ThemedSnackBar.showSuccess(context, l10n.ratingSuccessMsg);
        // Refresh the other party status to see if it unlocks
        await _checkOtherPartyRatingStatus();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ThemedSnackBar.showError(
          context,
          l10n.ratingFailed(e.toString()),
          onRetry: _submitRating,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width > 600;

    final displayId = widget.job.id.length > 8
        ? AppTypography.uppercaseLabel(widget.job.id.substring(0, 8))
        : AppTypography.uppercaseLabel(widget.job.id);

    return AppShell(
      title: l10n.ratingTitle,
      backgroundColor: AppColors.scaffoldBackground,
      appBarBackgroundColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.tooltipRefreshStatus,
          onPressed: _checkOtherPartyRatingStatus,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Driver Profile Info Card (Stitch Reference)
                _buildDriverProfileCard(displayId),
                const SizedBox(height: AppSpacing.lg),

                // 2. Rating Headline & Subtitle (Stitch Question)
                _buildRatingHeader(),
                const SizedBox(height: AppSpacing.lg),

                // 3. Main Interactive Rating Card
                ThemedCard(
                  borderRadius: AppRadius.lg,
                  padding: AppSpacing.lg,
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildRatingForm(l10n)),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(
                              child: _buildBlindStatusVisualizer(
                                l10n,
                                colorScheme,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildRatingForm(l10n),
                            const SizedBox(height: AppSpacing.xl),
                            _buildBlindStatusVisualizer(l10n, colorScheme),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 4. Blind Rating Educational Info Grid
                _buildInfoCards(l10n, isWide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriverProfileCard(String displayId) {
    return ThemedCard(
      padding: AppSpacing.lg,
      child: Column(
        children: [
          EntityAvatar(
            name: _otherPartyName,
            radius: 36,
            defaultIcon: Icons.local_shipping,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _otherPartyName,
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.l10n.deliveryIdTag(displayId),
            style: AppTypography.labelMd.copyWith(
              color: AppColors.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingHeader() {
    return Center(
      child: Column(
        children: [
          Text(
            context.l10n.howWasDeliveryQuestion,
            style: AppTypography.headlineLgMobile.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              context.l10n.ratingsBlindExplanation,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Driver info row
        Row(
          children: [
            EntityAvatar(
              name: _otherPartyName,
              radius: 24,
              defaultIcon: Icons.local_shipping,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherPartyName,
                    style: AppTypography.bodyLg.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    _otherPartyRole,
                    style: AppTypography.labelLg.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Score stars (Stitch Star Rating Component)
        _buildStarRatingSelector(),
        const SizedBox(height: AppSpacing.lg),

        // Feedback input
        ThemedTextField(
          controller: _commentController,
          labelText: l10n.privateFeedbackLabel,
          hintText: l10n.feedbackExperienceHint,
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Submit Button (Stitch Primary CTA)
        PrimaryButton(
          text: l10n.ratingSubmitBtn,
          trailingIcon: Icons.send,
          onPressed: _submitRating,
          isLoading: _isSubmitting,
        ),
      ],
    );
  }

  Widget _buildStarRatingSelector() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (index) {
          final starValue = index + 1;
          final isSelected = starValue <= _selectedStars;
          return IconButton(
            tooltip: context.l10n.ratingTitle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () {
              setState(() {
                _selectedStars = starValue;
              });
            },
            icon: Icon(
              isSelected ? Icons.star : Icons.star_border,
              color:
                  isSelected ? AppColors.secondary : AppColors.outlineVariant,
              size: 44,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBlindStatusVisualizer(
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return ThemedCard(
      hasShadow: false,
      color: AppColors.surfaceContainerLow,
      borderRadius: AppRadius.lg,
      padding: AppSpacing.lg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoadingOtherStatus)
            ThemedLoadingIndicator(message: l10n.loadingStatus)
          else if (_otherPartyHasRated) ...[
            ThemedPanel(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 48,
                )),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.feedbackLockedInTitle,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              l10n.bothRatingsVisibleDesc,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 48,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  child: ThemedPanel(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                      width: 10,
                      height: 10),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.waitingOtherPartyTitle,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              l10n.otherPartyNotRatedDesc,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Progress Bar
            Row(
              children: [
                Expanded(
                  child: ThemedPanel(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.radiusXxs),
                      height: 6),
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: ThemedPanel(
                      color: AppColors.outline.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.radiusXxs),
                      height: 6),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCards(AppLocalizations l10n, bool isWide) {
    // Mobile: intrinsic-height column — the previous 1-column GridView with
    // childAspectRatio 3.5 forced ~84px tiles under ~110px of content and
    // overflowed at 360dp (caught by the rating_screen widget suite).
    if (!isWide) {
      return Column(
        children: [
          _buildInfoCard(
            icon: Icons.security_outlined,
            title: l10n.ratingFeatureUnbiased,
            subtitle: l10n.unbiasedRatingDesc,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildInfoCard(
            icon: Icons.verified_outlined,
            title: l10n.ratingFeatureTrust,
            subtitle: l10n.reliabilityRanksDesc,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildInfoCard(
            icon: Icons.history_toggle_off_outlined,
            title: l10n.ratingFeatureWindow,
            subtitle: l10n.windowDeadlineDesc,
          ),
        ],
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.8,
      children: [
        _buildInfoCard(
          icon: Icons.security_outlined,
          title: l10n.ratingFeatureUnbiased,
          subtitle: l10n.unbiasedRatingDesc,
        ),
        _buildInfoCard(
          icon: Icons.verified_outlined,
          title: l10n.ratingFeatureTrust,
          subtitle: l10n.reliabilityRanksDesc,
        ),
        _buildInfoCard(
          icon: Icons.history_toggle_off_outlined,
          title: l10n.ratingFeatureWindow,
          subtitle: l10n.windowDeadlineDesc,
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ThemedCard(
      hasShadow: false,
      color: AppColors.surfaceContainerLow,
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
