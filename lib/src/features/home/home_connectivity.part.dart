part of 'home_screen.dart';

/// Non-modal, focusable status pill shown when a background refresh fails.
///
/// It overlays the content instead of replacing it so previously loaded media
/// stays browsable while the connection is down.
class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.lastUpdatedAt, required this.onRetry});

  final DateTime? lastUpdatedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    final localizations = MaterialLocalizations.of(context);
    final updatedTime = lastUpdatedAt == null
        ? null
        : localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastUpdatedAt!));

    return Positioned(
      right: scale.space(24, min: 14, max: 28),
      bottom: scale.space(16, min: 12, max: 20),
      child: TvFocusable(
        onPressed: onRetry,
        builder: (context, focusState) {
          return Semantics(
            button: true,
            label: updatedTime == null
                ? 'Offline. Showing cached library. Activate to retry.'
                : 'Offline. Showing library from $updatedTime. Activate to retry.',
            child: AnimatedContainer(
              duration: AppDurations.normal,
              padding: EdgeInsets.symmetric(
                horizontal: scale.space(16, min: 12, max: 18),
                vertical: scale.space(10, min: 8, max: 12),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2229),
                borderRadius: BorderRadius.circular(
                  scale.radius(AppRadii.lg, min: 12, max: 18),
                ),
                border: Border.all(
                  color: focusState.isFocused
                      ? AppColors.focus
                      : AppColors.warning.withValues(alpha: 0.55),
                  width: focusState.isFocused ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.warning,
                    size: scale.sizeOf(20, min: 18, max: 22),
                  ),
                  SizedBox(width: scale.space(AppSpacing.sm, min: 8, max: 10)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Offline — showing cached photos',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: scale.text(14, min: 12, max: 14),
                          ),
                        ),
                        if (updatedTime != null)
                          Text(
                            'Last updated $updatedTime',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                              fontSize: scale.text(12, min: 11, max: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: scale.space(AppSpacing.md, min: 10, max: 14)),
                  Icon(
                    Icons.refresh_rounded,
                    color: focusState.isFocused
                        ? AppColors.focus
                        : AppColors.textSecondary,
                    size: scale.sizeOf(20, min: 18, max: 22),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
