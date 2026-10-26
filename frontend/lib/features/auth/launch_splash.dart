import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';

/// UX-17 launch splash in the redesign: shown while AuthProvider restores
/// the stored session, so the sign-in page never flashes before the
/// session verdict exists. The A-Login brand tile (navy, gold box mark),
/// the wordmark and a spinner, centred on the page colour; no other text.
class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const Key('auth_splash_screen'),
      backgroundColor: c.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: QdColors.light.navy,
                  borderRadius: BorderRadius.circular(QdRadius.card),
                  border: dark ? Border.all(color: c.border) : null,
                ),
                child: Icon(Icons.inventory_2_outlined,
                    size: 36, color: QdColors.light.gold),
              ),
            ),
            const SizedBox(height: QdSpace.x4),
            Text(
              context.l10n.otpFooterBrand,
              style: QdText.header.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: QdSpace.x6),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
