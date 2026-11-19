class SocietyException implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> details;

  const SocietyException(
    this.code,
    this.message, {
    this.details = const {},
  });

  @override
  String toString() => 'SocietyException($code): $message';
}
