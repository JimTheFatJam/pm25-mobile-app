import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/update_service.dart';

/// A quiet, dismissible strip above the reading offering a newer release.
///
/// Styled from the theme like every other surface, but deliberately lighter
/// than a card: an available update is useful, not urgent, and must never
/// compete with the PM2.5 value for attention.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.info, required this.onDismiss, this.onDownload});

  final UpdateInfo info;
  final VoidCallback onDismiss;

  /// Injected by tests; defaults to opening the download URL in the browser.
  final Future<void> Function(UpdateInfo info)? onDownload;

  Future<void> _download() async {
    if (onDownload != null) return onDownload!(info);
    final uri = Uri.parse(info.downloadUrl);
    // Hands off to the browser; Android's own installer takes it from there,
    // so the app needs no install permission of its own.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.app;
    return Container(
      key: const Key('update-banner'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.iconTint,
        borderRadius: BorderRadius.circular(kInsetRadius),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.system_update_alt_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update available',
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
                const SizedBox(height: 2),
                Text('Version ${info.version} is ready to download.',
                    key: const Key('update-version'), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const Key('update-download'),
            onPressed: _download,
            child: const Text('Download'),
          ),
          IconButton(
            key: const Key('update-dismiss'),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, size: 18, color: colors.muted),
          ),
        ],
      ),
    );
  }
}
