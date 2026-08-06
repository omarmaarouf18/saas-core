import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/themed_card.dart';

class OwnerHistoryScreen extends StatelessWidget {
  final bool isEmbeddedInTab;
  const OwnerHistoryScreen({super.key, this.isEmbeddedInTab = false});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.xl,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.history_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'History & Audit Logs',
                  style: AppTypography.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Combined audit log, job activity, and wallet ledger history coming soon.',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isEmbeddedInTab) {
      return SingleChildScrollView(child: content);
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text('History & Audit Logs'),
      ),
      body: SingleChildScrollView(child: content),
    );
  }
}
