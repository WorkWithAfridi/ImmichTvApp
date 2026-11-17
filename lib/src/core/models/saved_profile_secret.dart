class SavedProfileSecret {
  const SavedProfileSecret({this.password, this.apiKey, this.pin});

  final String? password;
  final String? apiKey;

  /// Null when the profile has no PIN configured.
  final String? pin;

  Map<String, dynamic> toJson() {
    return {'password': password, 'apiKey': apiKey, 'pin': pin};
  }

  factory SavedProfileSecret.fromJson(Map<String, dynamic> json) {
    return SavedProfileSecret(
      password: json['password'] as String?,
      apiKey: json['apiKey'] as String?,
      pin: json['pin'] as String?,
    );
  }
}
