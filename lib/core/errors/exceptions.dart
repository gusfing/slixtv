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

/// Detailed exception thrown when Stalker's create_link endpoint fails.
/// Captures every byte of the network exchange for absolute transparency.
class CreateLinkException implements Exception {
  final String message;
  final String url;
  final String method;
  final Map<String, dynamic> queryParams;
  final dynamic requestBody;
  final Map<String, dynamic> requestHeaders;
  final String cookiesSent;
  final int? responseStatusCode;
  final Map<String, List<String>> responseHeaders;
  final String rawResponseBody;
  final String? portalError; // e.g. 'nothing_to_play', 'access_denied', etc.
  final DateTime timestamp;

  CreateLinkException({
    required this.message,
    required this.url,
    required this.method,
    required this.queryParams,
    required this.requestBody,
    required this.requestHeaders,
    required this.cookiesSent,
    this.responseStatusCode,
    required this.responseHeaders,
    required this.rawResponseBody,
    this.portalError,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'CreateLinkException(message: $message, url: $url, portalError: $portalError)';
  }
}

class StalkerRedirectException implements Exception {
  final String redirectUrl;

  const StalkerRedirectException({required this.redirectUrl});

  @override
  String toString() => 'StalkerRedirectException(redirectUrl: $redirectUrl)';
}
