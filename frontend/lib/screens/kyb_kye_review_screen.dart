import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/document_viewer_dialog.dart';

class KybKyeReviewScreen extends StatefulWidget {
  final String? internalToken;
  final String? reviewerToken;

  const KybKyeReviewScreen({
    super.key,
    this.internalToken,
    this.reviewerToken,
  });

  @override
  State<KybKyeReviewScreen> createState() => _KybKyeReviewScreenState();
}

class _KybKyeReviewScreenState extends State<KybKyeReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSubmissions();
    });
  }

  Future<void> _fetchSubmissions() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user?.role == 'reviewer' || user?.role == 'admin') {
      await auth.fetchPendingSubmissions(
        internalToken: widget.internalToken,
        reviewerToken: widget.reviewerToken,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    final isReviewer = user?.role == 'reviewer' || user?.role == 'admin';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Pending KYB/KYE Submissions'),
        foregroundColor: AppColors.onPrimary,
        actions: [
          if (isReviewer)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Queue',
              onPressed: _fetchSubmissions,
            ),
        ],
      ),
      body: !isReviewer
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: ThemedEmptyState(
                  key: Key('kyb_kye_unauthorized_state'),
                  icon: Icons.gavel_outlined,
                  title: 'Access Denied',
                  description:
                      'This reviewer queue is restricted to authorized reviewer accounts only.',
                ),
              ),
            )
          : _buildContent(context, auth),
    );
  }

  Widget _buildContent(BuildContext context, AuthProvider auth) {
    if (auth.isLoadingPending && auth.pendingSubmissions.isEmpty) {
      return const ThemedLoadingIndicator(
        key: Key('kyb_kye_loading_indicator'),
        message: 'Loading pending submissions...',
      );
    }

    final submissions = auth.pendingSubmissions;
    final error = auth.pendingError;

    return RefreshIndicator(
      onRefresh: _fetchSubmissions,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null) ...[
              ThemedErrorBanner(
                key: const Key('kyb_kye_error_banner'),
                message: error,
                onRetry: _fetchSubmissions,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (submissions.isEmpty && !auth.isLoadingPending)
              const ThemedEmptyState(
                key: Key('kyb_kye_empty_state'),
                icon: Icons.assignment_turned_in_outlined,
                title: 'No Pending Submissions',
                description:
                    'All KYB/KYE verification requests have been processed.',
              )
            else
              ListView.separated(
                key: const Key('kyb_kye_list_view'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: submissions.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final item = submissions[index];
                  final userId = item['user_id'] ?? item['id'] ?? 'unknown';
                  final username = item['username'] ?? 'User';
                  final email = item['email'] ?? '';
                  final role =
                      (item['role'] ?? 'user').toString().toLowerCase();

                  final kycStatus = item['kyc_status'] ?? '';
                  final kyeStatus = item['kye_status'] ?? '';
                  final status = role == 'employee'
                      ? (kyeStatus.toString().isNotEmpty
                          ? kyeStatus.toString()
                          : 'pending_super_admin_approval')
                      : (kycStatus.toString().isNotEmpty
                          ? kycStatus.toString()
                          : 'pending_super_admin_approval');

                  final hasFront = item['id_front_url'] != null &&
                      item['id_front_url'] != '';
                  final hasBack =
                      item['id_back_url'] != null && item['id_back_url'] != '';
                  final hasSelfie =
                      item['selfie_url'] != null && item['selfie_url'] != '';
                  final hasProof = item['business_proof_url'] != null &&
                      item['business_proof_url'] != '';

                  final docErrors = item['document_errors'] is List
                      ? (item['document_errors'] as List)
                          .map((e) => e.toString())
                          .toList()
                      : <String>[];

                  return InkWell(
                    key: Key('submission_item_$userId'),
                    onTap: () => _openDocumentViewer(item, 'id_front'),
                    borderRadius: BorderRadius.circular(AppRadius.defaultValue),
                    child: ThemedCard(
                      padding: AppSpacing.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: AppTypography.bodyMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              StatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text(
                                  role == 'owner'
                                      ? 'KYB (Owner)'
                                      : 'KYE (Employee)',
                                  style: AppTypography.labelLg.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'ID: $userId',
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Uploaded Documents:',
                            style: AppTypography.labelLg.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _buildDocChip('Front ID', hasFront,
                                  onTap: () =>
                                      _openDocumentViewer(item, 'id_front')),
                              _buildDocChip('Back ID', hasBack,
                                  onTap: () =>
                                      _openDocumentViewer(item, 'id_back')),
                              _buildDocChip('Selfie', hasSelfie,
                                  onTap: () =>
                                      _openDocumentViewer(item, 'selfie')),
                              if (role == 'owner')
                                _buildDocChip('Business Proof', hasProof,
                                    onTap: () => _openDocumentViewer(
                                        item, 'business_proof')),
                            ],
                          ),
                          if (docErrors.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: docErrors
                                    .map(
                                      (err) => Text(
                                        '• $err',
                                        style: AppTypography.bodyMd.copyWith(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openDocumentViewer(Map<String, dynamic> submission,
      [String initialDocType = 'id_front']) {
    showDialog(
      context: context,
      builder: (context) => DocumentViewerDialog(
        submission: submission,
        initialDocType: initialDocType,
        internalToken: widget.internalToken,
        reviewerToken: widget.reviewerToken,
      ),
    );
  }

  Widget _buildDocChip(String label, bool isAvailable, {VoidCallback? onTap}) {
    return InkWell(
      onTap: isAvailable ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isAvailable
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.outlineVariant.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isAvailable
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAvailable ? Icons.check_circle : Icons.cancel,
              size: 14,
              color:
                  isAvailable ? AppColors.success : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.bodyMd.copyWith(
                color: isAvailable
                    ? AppColors.success
                    : AppColors.onSurfaceVariant,
                fontWeight: isAvailable ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
