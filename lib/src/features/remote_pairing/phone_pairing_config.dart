class PhonePairingConfig {
  const PhonePairingConfig._();

  /// Override for private deployments and forks:
  /// `--dart-define=PHONE_COMPANION_URL=https://your-host/path/`.
  static const companionUrl = String.fromEnvironment(
    'PHONE_COMPANION_URL',
    defaultValue:
        'https://workwithafridi.github.io/immich_tv_app/phone_companion/',
  );
}
