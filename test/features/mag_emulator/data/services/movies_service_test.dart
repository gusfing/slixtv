import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/movies_service.dart';

void main() {
  group('MoviesService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late StreamResolver streamResolver;
    late MoviesService moviesService;

    const baseUrl = 'http://portal.com';
    const endpoint = '/load.php';

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      sessionManager = SessionManager();
      sessionManager.clearSession();
      sessionManager.setPortalInfo(baseUrl, endpoint);
      deviceIdentity = DeviceIdentity.generate();
      
      streamResolver = StreamResolver(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );

      moviesService = MoviesService(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
        streamResolver: streamResolver,
      );
    });

    test('should fetch movie categories', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
            {'id': '1', 'title': 'Action'},
            {'id': '2', 'title': 'Comedy'}
          ]
        }),
        queryParameters: {'type': 'vod', 'action': 'get_categories'},
      );

      final categories = await moviesService.getCategories();
      
      expect(categories.length, 2);
      expect(categories[0].title, 'Action');
    });

    test('should fetch movies by category', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': {
            'data': [
              {'id': '1', 'name': 'Movie 1', 'cover_big': '/cover.jpg', 'cmd': 'movie_1'}
            ]
          }
        }),
        queryParameters: {'type': 'vod', 'action': 'get_ordered_list', 'category': '1', 'p': '1', 'sortby': 'added'},
      );

      final movies = await moviesService.getMoviesByCategory('1');
      
      expect(movies.length, 1);
      expect(movies[0].name, 'Movie 1');
      expect(movies[0].poster, 'http://portal.com/cover.jpg');
    });

    test('should fetch movie metadata', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': {
            'movie': {
              'id': '1', 'name': 'Movie 1', 'director': 'Director', 'year': '2023', 'rating': '5'
            }
          }
        }),
        queryParameters: {'type': 'vod', 'action': 'get_info', 'movie_id': '1'},
      );

      final movie = await moviesService.getMovieMetadata('1');
      
      expect(movie, isNotNull);
      expect(movie!.director, 'Director');
      expect(movie.year, '2023');
    });
  });
}
