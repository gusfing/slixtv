// Custom exceptions for the application.

class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({required this.message, this.statusCode});

  @override
  String toString() => 'ServerException($message, statusCode: $statusCode)';
}

class AuthException implements Exception {
  final String message;

  const AuthException({required this.message});

  @override
  String toString() => 'AuthException($message)';
}

class CacheException implements Exception {
  final String message;

  const CacheException({required this.message});

  @override
  String toString() => 'CacheException($message)';
}

class PortalException implements Exception {
  final String message;
  final int? statusCode;

  const PortalException({required this.message, this.statusCode});

  @override
  String toString() => 'PortalException($message)';
}

class PlaybackException implements Exception {
  final String message;
  final String? streamUrl;

  const PlaybackException({required this.message, this.streamUrl});

  @override
  String toString() => 'PlaybackException($message, url: $streamUrl)';
}
