import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  const portal = 'http://tv.stream4k.cc';
  const mac = '00:1E:99:2C:D2:08';
  const endpoint = '$portal/stalker_portal/server/load.php';
  final cookieStr = 'mac=${Uri.encodeComponent(mac)}; stb_lang=en; timezone=Asia/Kolkata';

  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30), followRedirects: true));
  String token = '';

  Future<Map<String, dynamic>> req(Map<String, String> params) async {
    final resp = await dio.get(endpoint, queryParameters: params, options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Accept': '*/*',
        'Cookie': cookieStr,
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      validateStatus: (s) => s != null && s < 600,
    ));
    final data = resp.data;
    if (data is String) {
      try { return jsonDecode(data) as Map<String, dynamic>; }
      catch (_) { return {'_raw': data, '_status': resp.statusCode}; }
    }
    return (data as Map<String, dynamic>?) ?? {};
  }

  // Handshake — fresh token EVERY time
  Future<void> reauth() async {
    final hs = await req({'type': 'stb', 'action': 'handshake', 'prehash': '0', 'JsHttpRequest': '1-xml'});
    token = hs['js']?['token']?.toString() ?? '';
    print('New token: $token');
  }

  await reauth();

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
  }

  // Find first item with has_files=1
  Map? workingMovie;
  for (final item in items1) {
    final m = item as Map;
    if (m['has_files'] == 1) { workingMovie = m; break; }
  }
  print('Working movie: ${workingMovie?['name']} (id=${workingMovie?['id']})');

  // Fresh token before create_link
  await reauth();

  if (workingMovie != null) {
    final cmd = workingMovie['cmd'].toString();
    final movieId = workingMovie['id'].toString();
    print('\n--- VOD CREATE_LINK cmd=$cmd ---');
    final cl = await req({'type': 'vod', 'action': 'create_link', 'cmd': cmd, 'forced_storage': 'undefined', 'disable_ad': '0', 'JsHttpRequest': '1-xml'});
    final clJs = cl['js'];
    if (clJs is Map) {
      print('cmd=${clJs['cmd']}');
      print('error=${clJs['error']}');
      print('storage_id=${clJs['storage_id']}');
    } else {
      print('raw: ${jsonEncode(cl)}');
    }
    
    // Also check if cmd contains http already (no create_link needed for some portals)
    print('\nOriginal cmd value: $cmd');
    print('Starts with http: ${cmd.startsWith('http')}');
  }

  // Fresh token for series
  await reauth();

  // Series via get_ordered_list (try both with and without params)
  print('\n--- SERIES LIST (no category) ---');
  final sl = await req({'type': 'series', 'action': 'get_ordered_list', 'p': '1', 'sortby': 'added', 'hd': '0', 'JsHttpRequest': '1-xml'});
  print('js=${jsonEncode(sl['js'])}');
  print('text=${sl['text']}');

  await reauth();

  // Try get_series_categories action
  print('\n--- get_series_categories ---');
  final sca = await req({'type': 'series', 'action': 'get_series_categories', 'JsHttpRequest': '1-xml'});
  print('js=${jsonEncode(sca['js'])}');

  // Check if series is under vod with is_series flag
  print('\n--- VOD list with is_series filter ---');
  await reauth();
  final vls = await req({'type': 'vod', 'action': 'get_ordered_list', 'p': '1', 'sortby': 'added', 'hd': '0', 'is_series': '1', 'JsHttpRequest': '1-xml'});
  final vlsJs = vls['js'];
  if (vlsJs is Map) {
    final items = vlsJs['data'] as List? ?? [];
    print('items with is_series=1: ${items.length}');
    if (items.isNotEmpty) print('first: ${jsonEncode(items[0])}');
  } else {
    print('js=${jsonEncode(vlsJs)}');
  }

  print('\nDONE');
}
