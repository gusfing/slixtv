/// Base failure class for the application.
abstract class Failure {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const Failure({
    required this.message,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'Failure($message, statusCode: $statusCode)';
}

/// Network-related failures.
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.statusCode,
    super.originalError,
  });
}

/// Authentication failures (MAG handshake, token, etc.).
class AuthFailure extends Failure {
  const AuthFailure({
    required super.message,
    super.statusCode,
    super.originalError,
  });
}

/// Server returned an error response.
class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.statusCode,
    super.originalError,
  });
}

/// Local storage failures.
class CacheFailure extends Failure {
  const CacheFailure({
    required super.message,
    super.originalError,
  });
}

/// Stream/playback failures.
class PlaybackFailure extends Failure {
  const PlaybackFailure({
    required super.message,
    super.originalError,
  });
}

/// Portal-specific failures.
class PortalFailure extends Failure {
  const PortalFailure({
    required super.message,
    super.statusCode,
    super.originalError,
  });
}

/// Generic unknown failure.
class UnknownFailure extends Failure {
  const UnknownFailure({
    super.message = 'An unknown error occurred',
    super.originalError,
  });
}
