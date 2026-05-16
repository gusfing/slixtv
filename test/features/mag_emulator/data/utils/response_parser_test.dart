import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';

void main() {
  group('ResponseParser', () {
    Response createResponse(dynamic data, String contentType) {
      return Response(
        data: data,
        headers: Headers.fromMap({'content-type': [contentType]}),
        requestOptions: RequestOptions(path: ''),
      );
    }

    test('should parse JSON Map directly', () {
      final response = createResponse({'js': {'token': '123'}}, 'application/json');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js']['token'], '123');
    });

    test('should parse JSON String', () {
      final response = createResponse('{"js": {"token": "123"}}', 'application/json');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js']['token'], '123');
    });

    test('should handle js=false', () {
      final response = createResponse(false, 'application/json');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js'], false);
    });

    test('should parse XML into generic error or js=false', () {
      final xmlString = '<?xml version="1.0"?><error>Invalid request</error>';
      final response = createResponse(xmlString, 'text/xml');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js'], false);
      expect(result['error'], 'Invalid request');
    });

    test('should extract embedded JSON from HTML', () {
      final htmlString = '''
      <html>
        <body>
          <script>
            var data = {"js": {"extracted": true}};
          </script>
        </body>
      </html>
      ''';
      final response = createResponse(htmlString, 'text/html');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js']['extracted'], true);
    });

    test('should wrap string in js if JSON parse fails', () {
      final response = createResponse('just some raw string', 'text/plain');
      final result = ResponseParser.parseResponse(response);
      
      expect(result['js'], false);
      expect(result['raw'], 'just some raw string');
    });
  });
}
