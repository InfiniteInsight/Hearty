class OfflineException implements Exception {
  final String message;
  const OfflineException([this.message = 'No network connection']);
  @override
  String toString() => 'OfflineException: $message';
}
