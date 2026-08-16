import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
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
  String _otherPartyName = "Marcus J.";
  String _otherPartyRole = "Driver / Specialist";
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ratingTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.tooltipRefreshStatus,
            onPressed: _checkOtherPartyRatingStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Context Header
            Center(
              child: Column(
                children: [
                  Text(
                    'JOB ID: ${widget.job.id.substring(0, widget.job.id.length > 8 ? 8 : widget.job.id.length).toUpperCase()}',
                    style: AppTypography.labelLg.copyWith(
                      color: AppColors.primary.withValues(alpha: 0.7),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    'Rate Your Experience',
                    style: AppTypography.headlineLgMobile.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      'Ratings are blind. Neither party will see the other\'s feedback until both have submitted.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Main Interactive Card
            ThemedCard(
              borderRadius: AppRadius.lg,
              padding: AppSpacing.lg,
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildRatingForm(colorScheme, theme)),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                            child: _buildBlindStatusVisualizer(
                                colorScheme, theme)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRatingForm(colorScheme, theme),
                        const SizedBox(height: AppSpacing.xl),
                        _buildBlindStatusVisualizer(colorScheme, theme),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Information Grid
            GridView.count(
              crossAxisCount: isWide ? 3 : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: isWide ? 1.8 : 3.5,
              children: [
                _buildInfoCard(
                  icon: Icons.security_outlined,
                  title: l10n.ratingFeatureUnbiased,
                  subtitle:
                      "Preventing retaliatory or social-pressure ratings.",
                ),
                _buildInfoCard(
                  icon: Icons.verified_outlined,
                  title: l10n.ratingFeatureTrust,
                  subtitle:
                      "Ratings directly impact platform reliability ranks.",
                ),
                _buildInfoCard(
                  icon: Icons.history_toggle_off_outlined,
                  title: l10n.ratingFeatureWindow,
                  subtitle:
                      "Submit within 24 hours to ensure your score counts.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingForm(ColorScheme colorScheme, ThemeData theme) {
    final l10n = context.l10n;
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

        // Score stars
        Text(
          'Score Experience',
          style: AppTypography.labelLg.copyWith(
            color: AppColors.onSurfaceVariant,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Row(
          children: List.generate(5, (index) {
            final starValue = index + 1;
            final isSelected = starValue <= _selectedStars;
            return IconButton(
              onPressed: () {
                setState(() {
                  _selectedStars = starValue;
                });
              },
              icon: Icon(
                isSelected ? Icons.star : Icons.star_border,
                color:
                    isSelected ? AppColors.secondary : AppColors.outlineVariant,
                size: 36,
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Feedback input
        ThemedTextField(
          controller: _commentController,
          labelText: l10n.privateFeedbackLabel,
          hintText: l10n.privateFeedbackHint,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.lg),

        PrimaryButton(
          text: "Submit Blind Rating",
          onPressed: _submitRating,
          isLoading: _isSubmitting,
        ),
      ],
    );
  }

  Widget _buildBlindStatusVisualizer(ColorScheme colorScheme, ThemeData theme) {
    final l10n = context.l10n;
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
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Feedback Locked In!",
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              "The other party has submitted their rating. Both feedbacks are now visible under profile summary.",
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
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Waiting for other party...",
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              "The other party has not yet rated this transaction. Your ratings will remain hidden until they submit.",
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
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.radiusXxs),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.outline.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.radiusXxs),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
