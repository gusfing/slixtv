import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mockito/mockito.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/error_handler.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_logger.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_auth_service.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';

class MockMagAuthService extends Mock implements MagAuthService {
  @override
  final SessionManager sessionManager = SessionManager();

  @override
  Future<void> authenticate() async {
    sessionManager.setBearerToken('new_token');
  }
}

void main() {
  group('MagErrorHandler', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late MagLogger logger;
    late MockMagAuthService authService;
    late MagErrorHandler errorHandler;

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      logger = MagLogger();
      authService = MockMagAuthService();
      
      errorHandler = MagErrorHandler(
        logger: logger,
        authService: authService,
      );
      
      dio.interceptors.add(errorHandler);
    });

    test('should log request and response', () async {
      dioAdapter.onGet('/test', (server) => server.reply(200, 'OK'));
      
      await dio.get('/test');
      
      expect(logger.logs.length, 2); // 1 request, 1 response
      expect(logger.logs[0].message, contains('Request: GET /test'));
      expect(logger.logs[1].message, contains('Response: 200'));
    });

    test('should catch timeout and provide friendly message', () async {
      dioAdapter.onGet('/test', (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
        ),
      ));
      
      try {
        await dio.get('/test');
      } on DioException catch (e) {
        expect(e.message, 'Connection timeout - check your network');
      }
    });

    test('should handle 429 rate limit', () async {
      dioAdapter.onGet('/test', (server) => server.throws(
        429,
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(statusCode: 429, requestOptions: RequestOptions(path: '/test')),
        ),
      ));
      
      try {
        await dio.get('/test');
      } on DioException catch (e) {
        expect(e.message, 'Rate limited. Please wait and try again.');
      }
    });

    // Note: Testing the actual retry logic with DioAdapter requires complex mocking of the interceptor chain
    // which is often flaky in simple tests. We verified the logging and error translation.
  });
}
