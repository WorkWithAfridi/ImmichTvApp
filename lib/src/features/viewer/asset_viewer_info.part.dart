part of 'asset_viewer_screen.dart';

class _AssetInfoPanel extends StatelessWidget {
  const _AssetInfoPanel({
    required this.detail,
    required this.isLoading,
    required this.closeFocusNode,
    required this.onClose,
  });

  final AssetDetail? detail;
  final bool isLoading;
  final FocusNode closeFocusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      top: 72,
      bottom: 128,
      right: AppSpacing.xl,
      child: FocusTraversalGroup(
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            color: const Color(0xE6111820),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.focus,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Asset info',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TvFocusable(
                      focusNode: closeFocusNode,
                      onPressed: onClose,
                      builder: (context, focusState) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: focusState.isFocused
                                ? AppColors.focus.withValues(alpha: 0.24)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                              color: focusState.isFocused
                                  ? AppColors.focus
                                  : AppColors.borderStrong,
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.xs),
                            child: Icon(Icons.close_rounded, size: 18),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : detail == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Details are not available for this photo.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (detail!.description.isNotEmpty)
                                  _InfoRow(
                                    label: 'Description',
                                    value: detail!.description,
                                  ),
                                if (detail!.camera.isNotEmpty)
                                  _InfoRow(
                                    label: 'Camera',
                                    value: detail!.camera,
                                  ),
                                if (detail!.takenAt != null)
                                  _InfoRow(
                                    label: 'Taken',
                                    value: detail!.takenAt!.toLocal().toString(),
                                  ),
                                if (detail!.location.isNotEmpty)
                                  _InfoRow(
                                    label: 'Location',
                                    value: detail!.location,
                                  ),
                                if (detail!.originalFileName.isNotEmpty)
                                  _InfoRow(
                                    label: 'File',
                                    value: detail!.originalFileName,
                                  ),
                                for (final entry in detail!.metadata.entries)
                                  _InfoRow(
                                    label: entry.key,
                                    value: entry.value,
                                  ),
                                if (detail!.ocrTexts.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.text_fields_rounded,
                                        size: 16,
                                        color: AppColors.warning,
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        'Detected text',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  ...detail!.ocrTexts.map(
                                    (text) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.sm,
                                      ),
                                      child: Text(
                                        text,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ToggleInfoIntent extends Intent {
  const _ToggleInfoIntent();
}
