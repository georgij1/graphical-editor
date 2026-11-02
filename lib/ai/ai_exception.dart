/// Error raised when the local AI backend cannot be reached or returns an
/// unexpected response.
class AiException implements Exception {
  AiException(this.message);
  final String message;

  @override
  String toString() => message;
}
