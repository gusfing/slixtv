import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_logger.dart';

void main() {
  group('MagLogger', () {
    late MagLogger logger;

    setUp(() {
      logger = MagLogger();
    });

    test('should log request and return id', () {
      final id = logger.logRequest(
        method: 'GET',
        url: 'http://test.com',
        queryParams: {'action': 'handshake'},
      );

      expect(id, isNotEmpty);
      expect(logger.logs.length, 1);
      expect(logger.logs[0].level, LogLevel.info);
      expect(logger.logs[0].message, 'Request: GET http://test.com');
    });

    test('should mask Authorization header', () {
      logger.logRequest(
        method: 'GET',
        url: 'http://test.com',
        headers: {'Authorization': 'Bearer 123456789012345678901234567890'},
      );

      final reqData = logger.logs[0].requestData;
      expect(reqData!['headers']['Authorization'], 'Bearer 1234567890123456...');
    });

    test('should log response and correlate with request', () {
      final id = logger.logRequest(
        method: 'GET',
        url: 'http://test.com',
        action: 'handshake',
      );

      logger.logResponse(
        requestId: id,
        statusCode: 200,
        durationMs: 150,
        body: {'js': true},
      );

      expect(logger.logs.length, 2);
      expect(logger.logs[1].tag, 'MAG:handshake');
      expect(logger.logs[1].responseTimeMs, 150);
      expect(logger.logs[1].responseData!['statusCode'], 200);
    });

    test('should enforce circular buffer limit', () {
      for (int i = 0; i < 510; i++) {
        logger.logGeneric(LogLevel.info, 'TEST', 'Msg $i');
      }

      expect(logger.logs.length, 500);
      expect(logger.logs.first.message, 'Msg 10');
      expect(logger.logs.last.message, 'Msg 509');
    });

    test('should export JSON correctly', () {
      logger.logGeneric(LogLevel.info, 'TEST', 'Hello');
      
      final jsonStr = logger.exportJson();
      final decoded = json.decode(jsonStr) as List;
      
      expect(decoded.length, 1);
      expect(decoded[0]['message'], 'Hello');
      expect(decoded[0]['tag'], 'TEST');
    });
  });
}
