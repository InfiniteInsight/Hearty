/// Thrown when the backend rejects a request because the user has no active
/// license (HTTP 403 with body `{"detail":"no_active_license"}`).
///
/// Mirrors [OfflineException]: a typed signal so callers can route to the
/// "no active access" gated state instead of treating it as a generic error.
class NoActiveLicenseException implements Exception {
  final String message;
  const NoActiveLicenseException([this.message = 'No active license']);
  @override
  String toString() => 'NoActiveLicenseException: $message';
}
