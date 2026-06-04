/// Represents the currently signed‑in Google user.
class AuthenticatedUser {
  /// The unique, stable Google user identifier (the `sub` claim).
  final String googleUserId;

  /// The user’s email address from Google’s identity provider.
  final String? email;

  /// The user’s full display name.
  final String? displayName;

  const AuthenticatedUser({
    required this.googleUserId,
    this.email,
    this.displayName,
  });

  @override
  String toString() =>
      'AuthenticatedUser(googleUserId: $googleUserId, email: $email, displayName: $displayName)';
}