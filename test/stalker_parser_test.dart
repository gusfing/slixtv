import 'package:flutter_test/flutter_test.dart';
import '../lib/core/utils/stalker_parser.dart';
import '../lib/core/network/api_client.dart';

void main() {
  group('StalkerParser extractList tests', () {
    test('Should return flat list untouched', () {
      final input = [{'id': 1}, {'id': 2}];
      final result = StalkerParser.extractList(input);
      expect(result.length, 2);
    });

    test('Should unwrap {"data": [...]}', () {
      final input = {'data': [{'id': 1}]};
      final result = StalkerParser.extractList(input);
      expect(result.length, 1);
    });

    test('Should handle associative array bug {"0": {...}, "1": {...}}', () {
      final input = {
        'data': {
          '0': {'id': 1},
          '1': {'id': 2}
        }
      };
      final result = StalkerParser.extractList(input);
      expect(result.length, 2);
      expect((result[0] as Map)['id'], 1);
    });
  });

  group('PosterResolver tests', () {
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      client.configure(portalUrl: 'http://portal.com/stalker_portal', macAddress: '00:00:00:00:00:00');
    });

    test('Should resolve absolute URL correctly', () {
      final input = {'cover_big': 'http://external.com/image.jpg'};
      final result = PosterResolver.resolve(input, client);
      expect(result, 'http://external.com/image.jpg');
    });

    test('Should resolve relative URL against portal base', () {
      final input = {'screenshot_uri': '/misc/image.jpg'};
      final result = PosterResolver.resolve(input, client);
      expect(result, 'http://portal.com/misc/image.jpg');
    });

    test('Should prioritize cover_big over logo', () {
      final input = {
        'logo': 'http://external.com/logo.jpg',
        'cover_big': 'http://external.com/cover.jpg'
      };
      final result = PosterResolver.resolve(input, client);
      expect(result, 'http://external.com/cover.jpg');
    });
  });

  group('UrlNormalizer tests', () {
    test('Should strip ffmpeg directive', () {
      final input = 'ffmpeg http://live.stream.com/123';
      final result = UrlNormalizer.stripPlayerDirectives(input);
      expect(result, 'http://live.stream.com/123');
    });

    test('Should strip ffrt3 directive', () {
      final input = 'ffrt3 http://live.stream.com/123';
      final result = UrlNormalizer.stripPlayerDirectives(input);
      expect(result, 'http://live.stream.com/123');
    });

    test('Should handle multiple URLs separated by space', () {
      final input = 'ffmpeg http://server1.com/123 http://server2.com/123';
      final result = UrlNormalizer.stripPlayerDirectives(input);
      expect(result, 'http://server1.com/123');
    });
  });
}
