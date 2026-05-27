import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  const portal = 'http://tv.stream4k.cc';
  const mac = '00:1E:99:2C:D2:08';
  const endpoint = '$portal/stalker_portal/server/load.php';
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30), followRedirects: true));
  String token = '';

  final Map<String, String> cookies = {
    'mac': mac,
    'stb_lang': 'en',
    'timezone': 'Europe/Kyiv', // use Europe/Kyiv to match real headers
  };

  Future<Map<String, dynamic>> req(Map<String, String> params) async {
    final cookieHeader = cookies.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('; ');
    print('[REQ] params=$params Cookie=$cookieHeader Token=$token');
    final resp = await dio.get(endpoint, queryParameters: params, options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 4 rev: 231 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Accept': '*/*',
        'Referer': '$portal/c/',
        'Cookie': cookieHeader,
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      validateStatus: (s) => s != null && s < 600,
    ));

    print('[RESP] status=${resp.statusCode} headers=${resp.headers}');
    print('[DATA] ${resp.data is Map || resp.data is List ? jsonEncode(resp.data) : resp.data}');

    // Parse Set-Cookie from response
    final setCookies = resp.headers['set-cookie'];
    if (setCookies != null) {
      for (final setCookie in setCookies) {
        final parts = setCookie.split(';').first.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          cookies[key] = Uri.decodeComponent(val);
        }
      }
      print('[COOKIES UPDATED] cookies=$cookies');
    }

    final data = resp.data;
    if (data is String) {
      try { return jsonDecode(data) as Map<String, dynamic>; }
      catch (_) { return {'_raw': data, '_status': resp.statusCode}; }
    }
    return (data as Map<String, dynamic>?) ?? {};
  }

  // Perform full authentication sequence
  Future<bool> authenticate() async {
    print('\n=== AUTHENTICATION FLOW ===');
    // Clear token for handshake
    token = '';
    
    // Step 1: Handshake
    final hs = await req({'type': 'stb', 'action': 'handshake', 'prehash': '0', 'JsHttpRequest': '1-xml'});
    final hsJs = hs['js'];
    if (hsJs is! Map || hsJs['token'] == null) {
      print('Handshake failed: ${jsonEncode(hs)}');
      return false;
    }
    token = hsJs['token'].toString();
    print('Token received: $token');

    // Step 2: Get Profile
    final profile = await req({'type': 'stb', 'action': 'get_profile', 'JsHttpRequest': '1-xml'});
    if (profile['_raw'] == 'Authorization failed.') {
      print('get_profile failed: Authorization failed');
      return false;
    }
    print('Profile: ${jsonEncode(profile['js'])}');

    // Step 3: Get Main Info
    final mainInfo = await req({'type': 'stb', 'action': 'get_main_info', 'JsHttpRequest': '1-xml'});
    print('Main Info: ${jsonEncode(mainInfo['js'])}');

    // Step 4: Get Modules
    final modules = await req({'type': 'stb', 'action': 'get_modules', 'JsHttpRequest': '1-xml'});
    print('Modules loaded successfully: ${jsonEncode(modules['js'])}');
    
    return true;
  }

  final authenticated = await authenticate();
  if (!authenticated) {
    print('Authentication failed!');
    return;
  }

  // VOD list page 1 — check has_files
  print('\n--- VOD LIST page 1 ---');
  final vl = await req({'type': 'vod', 'action': 'get_ordered_list', 'p': '1', 'sortby': 'added', 'hd': '0', 'JsHttpRequest': '1-xml'});
  final vlJs = vl['js'];
  List items1 = [];
  if (vlJs is Map) {
    items1 = vlJs['data'] as List? ?? [];
    print('total_items=${vlJs['total_items']} page_items=${vlJs['max_page_items']}');
    for (int i = 0; i < items1.length.clamp(0, 5); i++) {
      final m = items1[i] as Map;
      print('[$i] id=${m['id']} has_files=${m['has_files']} cmd=${m['cmd']} screenshot=${m['screenshot_uri']} name=${m['name']}');
    }
  } else {
    print('VOD list failed: ${jsonEncode(vl)}');
  }

  // Find first few items in a movie category (category=18)
  print('\n--- LOADING MOVIES FROM CATEGORY 18 ---');
  final mvList = await req({'type': 'vod', 'action': 'get_ordered_list', 'category': '18', 'p': '1', 'sortby': 'added', 'hd': '0', 'JsHttpRequest': '1-xml'});
  List movieItems = [];
  if (mvList['js'] is Map && mvList['js']['data'] is List) {
    movieItems = mvList['js']['data'] as List;
  } else if (mvList['js'] is List) {
    movieItems = mvList['js'] as List;
  }
  print('Loaded ${movieItems.length} items from category 18.');
  for (int i = 0; i < movieItems.length.clamp(0, 3); i++) {
    final m = movieItems[i] as Map;
    print('  [$i] id=${m['id']} name=${m['name']} is_series=${m['is_series']} is_movie=${m['is_movie']} cmd=${m['cmd']}');
  }

  List<Map> workingMovies = [];
  for (final item in movieItems) {
    final m = item as Map;
    if (m['has_files'] == 1) {
      workingMovies.add(m);
      if (workingMovies.length >= 3) break;
    }
  }
  print('Found ${workingMovies.length} candidate movie items.');

  for (final movie in workingMovies) {
    final cmd = movie['cmd'].toString();
    final name = movie['name'].toString();
    final id = movie['id'].toString();
    print('\n--- TESTING VOD CREATE_LINK FOR MOVIE: "$name" (id=$id, cmd=$cmd) ---');
    final cl = await req({'type': 'vod', 'action': 'create_link', 'cmd': cmd, 'forced_storage': 'undefined', 'disable_ad': '0', 'JsHttpRequest': '1-xml'});
    final clJs = cl['js'];
    if (clJs is Map) {
      print('  cmd=${clJs['cmd']}');
      print('  error=${clJs['error']}');
      print('  storage_id=${clJs['storage_id']}');
    } else {
      print('  raw: ${jsonEncode(cl)}');
    }
  }

  // Series via get_ordered_list (try both with and without params)
  print('\n--- SERIES LIST (no category) ---');
  final sl = await req({'type': 'series', 'action': 'get_ordered_list', 'p': '1', 'sortby': 'added', 'hd': '0', 'JsHttpRequest': '1-xml'});
  print('Raw Series List Response: ${jsonEncode(sl)}');
  print('js=${jsonEncode(sl['js'])}');

  // Try get_series_categories action
  print('\n--- get_series_categories ---');
  final sca = await req({'type': 'series', 'action': 'get_series_categories', 'JsHttpRequest': '1-xml'});
  print('Raw Series Categories Response: ${jsonEncode(sca)}');
  print('js=${jsonEncode(sca['js'])}');

  // Try type=vod, action=get_categories
  print('\n--- type=vod, action=get_categories ---');
  final vca = await req({'type': 'vod', 'action': 'get_categories', 'JsHttpRequest': '1-xml'});
  print('Raw VOD Categories Response: ${jsonEncode(vca)}');
  if (vca['js'] is List) {
    final list = vca['js'] as List;
    print('Total VOD categories: ${list.length}');
    for (int i = 0; i < list.length.clamp(0, 10); i++) {
      print('  [$i] id=${list[i]['id']} name=${list[i]['category_name']} alias=${list[i]['category_alias']}');
    }
  }

  // Check if series is under vod with is_series flag
  print('\n--- VOD list with is_series filter ---');
  final vls = await req({'type': 'vod', 'action': 'get_ordered_list', 'p': '1', 'sortby': 'added', 'hd': '0', 'is_series': '1', 'JsHttpRequest': '1-xml'});
  print('Raw VOD list with is_series filter response: ${jsonEncode(vls)}');
  final vlsJs = vls['js'];
  Map? firstSeries;
  if (vlsJs is Map) {
    final items = vlsJs['data'] as List? ?? [];
    print('items with is_series=1: ${items.length}');
    if (items.isNotEmpty) {
      firstSeries = items[0] as Map;
      print('first series: id=${firstSeries['id']} name=${firstSeries['name']} cmd=${firstSeries['cmd']} has_files=${firstSeries['has_files']}');
    }
  }

  if (firstSeries != null) {
    final seriesId = firstSeries['id'].toString();
    print('\n--- TRYING TO LOAD EPISODES FOR SERIES $seriesId ---');

    // Attempt 1: type=vod, action=get_ordered_list with movie_id
    print('\n--- Attempt 1: type=vod, action=get_ordered_list, movie_id=$seriesId ---');
    final att1 = await req({'type': 'vod', 'action': 'get_ordered_list', 'movie_id': seriesId, 'JsHttpRequest': '1-xml'});
    print('Attempt 1 response: ${jsonEncode(att1['js'])}');

    // Attempt 5: Load episodes for Season 3 (id=136021)
    const seasonId = '136021';
    print('\n--- Attempt 5: type=vod, action=get_ordered_list, movie_id=$seriesId, season_id=$seasonId ---');
    final att5 = await req({'type': 'vod', 'action': 'get_ordered_list', 'movie_id': seriesId, 'season_id': seasonId, 'JsHttpRequest': '1-xml'});
    print('Attempt 5 response: ${jsonEncode(att5['js'])}');

    const episodeId = '2913346';
    const episodeNum = '132';
    const movieId = '464336'; // Marty Supreme movie ID

    print('\n=========================================');
    print('  Targeted VOD Movie create_link Experiments (Movie ID: $movieId)');
    print('=========================================');

    // Movie Experiment 1: User's suggestion (movie_id + cmd + stb parameters)
    print('\n--- Movie Experiment 1: cmd, movie_id, forced_storage=0, disable_ad=0, volume=100, play_mode=0 ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$movieId.mpg',
      'movie_id': movieId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Movie Experiment 2: movie_id only
    print('\n--- Movie Experiment 2: movie_id only ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'movie_id': movieId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Movie Experiment 3: cmd only, with stb parameters
    print('\n--- Movie Experiment 3: cmd + stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$movieId.mpg',
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Movie Experiment 4: ffmpeg-wrapped cmd + movie_id + stb parameters
    print('\n--- Movie Experiment 4: ffmpeg wrapped cmd + movie_id + stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': 'ffmpeg /media/$movieId.mpg',
      'movie_id': movieId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    print('\n=========================================');
    print('  Targeted Series Episode create_link Experiments (Episode ID: $episodeId, Parent Series: $seriesId)');
    print('=========================================');

    // Episode Experiment 1: cmd = parent series, series = episode id, with stb parameters
    print('\n--- Episode Experiment 1: cmd=parent, series=episodeId, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$seriesId.mpg',
      'series': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 2: cmd = parent series, movie_id = episode id, with stb parameters
    print('\n--- Episode Experiment 2: cmd=parent, movie_id=episodeId, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$seriesId.mpg',
      'movie_id': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 3: cmd = parent series, movie_id = parent, series = episode id
    print('\n--- Episode Experiment 3: cmd=parent, movie_id=parent, series=episodeId, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$seriesId.mpg',
      'movie_id': seriesId,
      'series': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 4: cmd = episode, movie_id = episode id
    print('\n--- Episode Experiment 4: cmd=episodeId, movie_id=episodeId, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$episodeId.mpg',
      'movie_id': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 5: movie_id = episode id only
    print('\n--- Episode Experiment 5: movie_id=episodeId only ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'movie_id': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 6: cmd = parent series, series = episode number
    print('\n--- Episode Experiment 6: cmd=parent, series=episodeNum, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$seriesId.mpg',
      'series': episodeNum,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Episode Experiment 7: cmd = episode, series = episode id
    print('\n--- Episode Experiment 7: cmd=episodeId, series=episodeId, stb parameters ---');
    await req({
      'type': 'vod',
      'action': 'create_link',
      'cmd': '/media/$episodeId.mpg',
      'series': episodeId,
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
      'JsHttpRequest': '1-xml',
    });

    // Attempt 4: type=vod, action=get_ordered_list with category and is_series
    if (firstSeries['category_id'] != null) {
      final catId = firstSeries['category_id'].toString();
      print('\n--- Attempt 4: type=vod, action=get_ordered_list, category=$catId, is_series=1 ---');
      final att4 = await req({'type': 'vod', 'action': 'get_ordered_list', 'category': catId, 'is_series': '1', 'p': '1', 'JsHttpRequest': '1-xml'});
      print('Attempt 4 response (first 2 items):');
      final att4Js = att4['js'];
      if (att4Js is Map && att4Js['data'] is List) {
        final data = att4Js['data'] as List;
        for (int i = 0; i < data.length.clamp(0, 2); i++) {
          print('  [$i] ${data[i]['name']}');
        }
      } else {
        print('  ${jsonEncode(att4)}');
      }
    }
  }

  print('\nDONE');
}
