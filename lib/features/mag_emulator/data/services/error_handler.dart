import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_logger.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_auth_service.dart';

class MagErrorHandler extends Interceptor {
  final MagLogger logger;
  final MagAuthService authService;
  
  String? lastCriticalError;

  MagErrorHandler({
    required this.logger,
    required this.authService,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Log request
    final reqId = logger.logRequest(
      method: options.method,
      url: options.uri.toString(),
      queryParams: options.queryParameters,
      headers: options.headers,
      body: options.data,
      action: options.queryParameters['action']?.toString(),
    );
    
    options.extra['reqId'] = reqId;
    options.extra['startTime'] = DateTime.now().millisecondsSinceEpoch;
    
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Log response
    final reqId = response.requestOptions.extra['reqId'] as String?;
    final startTime = response.requestOptions.extra['startTime'] as int?;
    final duration = startTime != null ? DateTime.now().millisecondsSinceEpoch - startTime : 0;

    if (reqId != null) {
      logger.logResponse(
        requestId: reqId,
        statusCode: response.statusCode,
        durationMs: duration,
        body: response.data,
      );
    }

    super.onResponse(response, handler);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final reqId = err.requestOptions.extra['reqId'] as String?;
    final startTime = err.requestOptions.extra['startTime'] as int?;
    final duration = startTime != null ? DateTime.now().millisecondsSinceEpoch - startTime : 0;

    String friendlyMessage = _getFriendlyErrorMessage(err);
    
    if (reqId != null) {
      logger.logResponse(
        requestId: reqId,
        statusCode: err.response?.statusCode,
        durationMs: duration,
        error: friendlyMessage,
      );
    }

    // Handle 401 Re-authentication
    if (err.response?.statusCode == 401 || err.response?.statusCode == 403) {
      // Prevent infinite loop if re-auth also fails
      if (err.requestOptions.extra['isRetry'] == true) {
        lastCriticalError = 'Authentication failed permanently';
        return handler.next(err.copyWith(message: 'Authentication failed. Please check credentials.'));
      }

      try {
        logger.logGeneric(LogLevel.warning, 'AUTH', 'Attempting re-authentication after 401/403');
        await authService.authenticate();
        
        // Retry the original request
        final retryOptions = err.requestOptions;
        retryOptions.extra['isRetry'] = true;
        
        // Update auth header
        final token = authService.sessionManager.getBearerToken();
        if (token != null) {
          retryOptions.headers['Authorization'] = 'Bearer $token';
        }

        final dio = Dio();
        final response = await dio.fetch(retryOptions);
        return handler.resolve(response);
        
      } catch (e) {
        lastCriticalError = 'Re-authentication failed';
        return handler.next(err.copyWith(message: 'Authentication failed. Please check credentials.'));
      }
    }

    lastCriticalError = friendlyMessage;
    // Translate error to user-friendly message
    return handler.next(err.copyWith(message: friendlyMessage));
  }

  String _getFriendlyErrorMessage(DioException err) {
    if (err.response?.statusCode != null) {
      final statusCode = err.response!.statusCode;
      if (statusCode == 429) {
        return 'Rate limited. Please wait and try again.';
      }
      if (statusCode == 500 || statusCode == 502 || statusCode == 503) {
         return 'Portal server error ($statusCode)';
      }
    }

    if (err.type == DioExceptionType.connectionTimeout || 
        err.type == DioExceptionType.sendTimeout || 
        err.type == DioExceptionType.receiveTimeout) {
      return 'Connection timeout - check your network';
    }

    if (err.type == DioExceptionType.connectionError || err.type == DioExceptionType.unknown) {
      return 'Cannot reach portal server';
    }

    return err.message ?? 'Unknown network error';
  }
}
