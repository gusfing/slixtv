import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';
import 'package:slix_iptv/core/utils/stalker_parser.dart';

class StreamResolutionException implements Exception {
  final String message;
  StreamResolutionException(this.message);
  @override
  String toString() => message;
}

class StreamResolver {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;

  StreamResolver({
    required this.dio,
    required this.sessionManager,
    required this.deviceIdentity,
  });

  static const List<String> prefixesToStrip = [
    'ffmpeg ',
    'ffrt3 ',
    'ffrt ',
    'auto ',
    '/ch/'
  ];

  String _stripPrefixes(String cmd) {
    String cleaned = cmd;
    bool changed;
    do {
      changed = false;
      for (final prefix in prefixesToStrip) {
        if (cleaned.startsWith(prefix)) {
          cleaned = cleaned.substring(prefix.length).trim();
          changed = true;
        }
      }
    } while (changed);
    return cleaned;
  }

  String _extractHttpUrl(String mixedString) {
    int index = mixedString.indexOf('http');
    if (index != -1) {
      return mixedString.substring(index).trim();
    }
    return mixedString;
  }

  String _selectFirstValidUrl(String spaceSeparatedUrls) {
    final urls = spaceSeparatedUrls.split(' ');
    for (final url in urls) {
      if (url.startsWith('http') || url.startsWith('rtsp')) {
        return url;
      }
    }
    return urls.isNotEmpty ? urls.first : '';
  }

  String _replaceLocalhost(String url) {
    if (sessionManager.portalBaseUrl == null) return url;
    
    final uri = Uri.tryParse(sessionManager.portalBaseUrl!);
    if (uri == null) return url;

    return url
        .replaceAll('localhost', uri.host)
        .replaceAll('127.0.0.1', uri.host);
  }

  String _extractNumericId(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match != null ? match.group(0)! : '';
  }

  Future<Map<String, dynamic>> _stalkerRequest({
    required String type,
    required String action,
    Map<String, String>? extraParams,
  }) async {
    if (sessionManager.portalBaseUrl == null || sessionManager.portalEndpoint == null) {
      throw StreamResolutionException('Portal endpoint not set');
    }
    final url = '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
    final params = <String, String>{
      'type': type,
      'action': action,
      'JsHttpRequest': '1-xml',
      ...?extraParams,
    };
    final headers = MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );
    final response = await dio.get(
      url,
      queryParameters: params,
      options: Options(headers: headers),
    );
    return ResponseParser.parseResponse(response);
  }

  Future<String> resolveStreamUrl(String type, String cmd, {String? series, String? duration}) async {
    // 1. Pre-process the command
    String processedCmd = _stripPrefixes(cmd);
    processedCmd = _extractHttpUrl(processedCmd);
    processedCmd = _selectFirstValidUrl(processedCmd);
    processedCmd = _replaceLocalhost(processedCmd);

    // 2. Direct HTTP bypass
    if (processedCmd.startsWith('http://') || processedCmd.startsWith('https://')) {
      if (!processedCmd.contains('localhost') && !processedCmd.contains('127.0.0.1')) {
        return processedCmd;
      }
    }

    if (processedCmd.startsWith('udp://') || processedCmd.startsWith('rtsp://')) {
      // Log warning for unsupported
      // Using generic print since logger is in Task 15
      print('Warning: Unsupported protocol scheme: $processedCmd');
    }

    String resolvedCmd = cmd;
    if ((type == 'series' || type == 'vod') &&
        !resolvedCmd.startsWith('http') &&
        !resolvedCmd.startsWith('rtsp') &&
        !resolvedCmd.startsWith('/media/file_')) {
      print('StreamResolver: Intercepted catalog cmd: $resolvedCmd. Resolving file ID...');
      try {
        final parentId = _extractNumericId(resolvedCmd);
        if (parentId.isNotEmpty) {
          if (series != null && series.isNotEmpty) {
            // It's a Series Episode
            print('StreamResolver: Querying get_ordered_list for parent series: movie_id=$parentId');
            final seasonsRes = await _stalkerRequest(
              type: 'vod',
              action: 'get_ordered_list',
              extraParams: {
                'movie_id': parentId,
              },
            );
            final seasonsJs = seasonsRes['js'];
            if (seasonsJs != null && seasonsJs != false) {
              final rawList = StalkerParser.extractList(
                seasonsJs is Map ? seasonsJs['data'] ?? seasonsJs : seasonsJs
              );

              final hasSeasons = rawList.any((e) =>
                  e is Map<String, dynamic> &&
                  (e['is_season'] == true ||
                      e['is_season'] == 'true' ||
                      e['is_season'] == 1 ||
                      e['is_season'] == '1'));

              // Check if this is a file list (portal returned files directly)
              final hasFiles = rawList.any((e) =>
                  e is Map<String, dynamic> &&
                  (e['is_file'] == true ||
                      e['is_file'] == 'true' ||
                      e['is_file'] == 1 ||
                      e['is_file'] == '1'));

              if (hasFiles && !hasSeasons) {
                // Portal returned file items directly. Use the first file's ID.
                // The 'series' param is an episode number but these items are files,
                // not episodes — there's no series_number to match against.
                // Pick the file whose index matches the episode number, or the first.
                final epIndex = (int.tryParse(series) ?? 1) - 1;
                final targetFile = epIndex >= 0 && epIndex < rawList.length
                    ? rawList[epIndex]
                    : rawList.first;
                if (targetFile is Map<String, dynamic>) {
                  final fileId = targetFile['id']?.toString();
                  if (fileId != null && fileId.isNotEmpty) {
                    resolvedCmd = '/media/file_$fileId.mpg';
                    print('StreamResolver: Resolved flat-file series cmd to: $resolvedCmd');
                  }
                }
              } else if (hasSeasons) {
                String? foundEpisodeId;
                String? foundSeasonId;

                // For each season, get episodes and search for the episode number
                for (final season in rawList) {
                  if (season is Map<String, dynamic>) {
                    final seasonId = season['id']?.toString() ?? '';
                    if (seasonId.isNotEmpty) {
                      print('StreamResolver: Querying episodes for season $seasonId');
                      final epRes = await _stalkerRequest(
                        type: 'vod',
                        action: 'get_ordered_list',
                        extraParams: {
                          'movie_id': parentId,
                          'season_id': seasonId,
                        },
                      );
                      final epJs = epRes['js'];
                      if (epJs != null && epJs != false) {
                        final epList = StalkerParser.extractList(
                          epJs is Map ? epJs['data'] ?? epJs : epJs
                        );
                        for (final ep in epList) {
                          if (ep is Map<String, dynamic>) {
                            // Check if these are file items
                            final epIsFile = ep['is_file'] == true || ep['is_file'] == 1 || ep['is_file'] == '1' || ep['is_file'] == 'true';
                            if (epIsFile) {
                              // File items: use index-based matching or first file
                              final epIndex = (int.tryParse(series) ?? 1) - 1;
                              final targetFile = epIndex >= 0 && epIndex < epList.length
                                  ? epList[epIndex]
                                  : epList.first;
                              if (targetFile is Map<String, dynamic>) {
                                foundEpisodeId = targetFile['id']?.toString();
                                foundSeasonId = seasonId;
                              }
                              break;
                            }
                            final epNum = ep['series_number']?.toString() ??
                                ep['series_num']?.toString() ??
                                ep['episode_num']?.toString() ??
                                '';
                            if (epNum == series) {
                              foundEpisodeId = ep['id']?.toString();
                              foundSeasonId = seasonId;
                              break;
                            }
                          }
                        }
                      }
                    }
                  }
                  if (foundEpisodeId != null) break;
                }

                if (foundEpisodeId != null) {
                  // Resolve the episode container to its actual playable file ID
                  print('StreamResolver: Episode container ID found: $foundEpisodeId. Querying for file...');
                  try {
                    final fileRes = await _stalkerRequest(
                      type: 'vod',
                      action: 'get_ordered_list',
                      extraParams: {
                        'movie_id': parentId,
                        if (foundSeasonId != null && foundSeasonId.isNotEmpty) 'season_id': foundSeasonId,
                        'episode_id': foundEpisodeId,
                      },
                    );
                    final fileJs = fileRes['js'];
                    if (fileJs != null && fileJs != false) {
                      final fileList = StalkerParser.extractList(
                        fileJs is Map ? fileJs['data'] ?? fileJs : fileJs
                      );
                      if (fileList.isNotEmpty) {
                        final firstFile = fileList.first;
                        if (firstFile is Map<String, dynamic>) {
                          final fileId = firstFile['id']?.toString();
                          if (fileId != null && fileId.isNotEmpty) {
                            foundEpisodeId = fileId;
                            print('StreamResolver: Resolved to actual file ID: $fileId');
                          }
                        }
                      }
                    }
                  } catch (e) {
                    print('StreamResolver: Failed to fetch actual file for episode container: $e');
                  }

                  resolvedCmd = '/media/file_$foundEpisodeId.mpg';
                  print('StreamResolver: Resolved season-based series cmd to: $resolvedCmd');
                } else {
                  print('StreamResolver: Warning: Episode number $series not found for parent series $parentId');
                }
              } else {
                // Flat series with no is_file flag — search by series_number
                String? foundEpisodeId;
                for (final ep in rawList) {
                  if (ep is Map<String, dynamic>) {
                    final epNum = ep['series_number']?.toString() ??
                        ep['series_num']?.toString() ??
                        ep['episode_num']?.toString() ??
                        '';
                    if (epNum == series) {
                      foundEpisodeId = ep['id']?.toString();
                      break;
                    }
                  }
                }
                if (foundEpisodeId != null) {
                  print('StreamResolver: Flat episode container ID found: $foundEpisodeId. Querying for file...');
                  try {
                    final fileRes = await _stalkerRequest(
                      type: 'vod',
                      action: 'get_ordered_list',
                      extraParams: {
                        'movie_id': parentId,
                        'episode_id': foundEpisodeId,
                      },
                    );
                    final fileJs = fileRes['js'];
                    if (fileJs != null && fileJs != false) {
                      final fileList = StalkerParser.extractList(
                        fileJs is Map ? fileJs['data'] ?? fileJs : fileJs
                      );
                      if (fileList.isNotEmpty) {
                        final firstFile = fileList.first;
                        if (firstFile is Map<String, dynamic>) {
                          final fileId = firstFile['id']?.toString();
                          if (fileId != null && fileId.isNotEmpty) {
                            foundEpisodeId = fileId;
                            print('StreamResolver: Resolved flat series to actual file ID: $fileId');
                          }
                        }
                      }
                    }
                  } catch (e) {
                    print('StreamResolver: Failed to fetch actual file for flat episode container: $e');
                  }

                  resolvedCmd = '/media/file_$foundEpisodeId.mpg';
                  print('StreamResolver: Resolved flat series cmd to: $resolvedCmd');
                } else {
                  print('StreamResolver: Warning: Episode number $series not found for parent series $parentId');
                }
              }
            }
          } else {
            // It's a Movie
            print('StreamResolver: Querying get_ordered_list for movie file: movie_id=$parentId');
            final listRes = await _stalkerRequest(
              type: 'vod',
              action: 'get_ordered_list',
              extraParams: {
                'movie_id': parentId,
              },
            );
            final listJs = listRes['js'];
            if (listJs != null && listJs != false) {
              final rawList = StalkerParser.extractList(
                listJs is Map ? listJs['data'] ?? listJs : listJs
              );
              if (rawList.isNotEmpty) {
                final firstItem = rawList.first;
                if (firstItem is Map<String, dynamic>) {
                  final fileId = firstItem['id']?.toString();
                  if (fileId != null && fileId.isNotEmpty) {
                    resolvedCmd = '/media/file_$fileId.mpg';
                    print('StreamResolver: Resolved movie cmd to: $resolvedCmd');
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        print('StreamResolver: Failed to resolve file command: $e');
      }
    }


    // 3. Send create_link request
    if (sessionManager.portalBaseUrl == null || sessionManager.portalEndpoint == null) {
      throw StreamResolutionException('Portal endpoint not set');
    }

    final url = '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
    final queryParams = {
      'type': type,
      'action': 'create_link',
      'cmd': resolvedCmd,
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'JsHttpRequest': '1-xml',
      if (series != null) 'series': series,
      if (duration != null) 'duration': duration,
    };

    final headers = MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParams,
        options: Options(headers: headers),
      );

      final parsed = ResponseParser.parseResponse(response);
      final js = parsed['js'];
      final rawText = parsed['text']?.toString() ?? '';
      final isTimeout = rawText.contains('Connection timeout') || rawText.contains('Failed to connect');

      if (isTimeout) {
        throw StreamResolutionException(
          'The portal storage server is temporarily offline (Connection Timeout). Please try again later.'
        );
      }

      if (js == false || js == null) {
        throw StreamResolutionException('Failed to get link data from portal');
      }

      if (js is Map && js.containsKey('error')) {
        if (js['error'] == 'nothing_to_play') {
          throw StreamResolutionException('The portal is currently unable to play this item (nothing_to_play).');
        }
        throw StreamResolutionException('Portal error: ${js['error']}');
      }

      String finalUrl = '';
      if (js is Map) {
        if (js.containsKey('cmd')) {
          finalUrl = js['cmd'].toString();
        } else if (js.containsKey('url')) {
          finalUrl = js['url'].toString();
        }
      } else if (js is String) {
        finalUrl = js;
      }

      if (finalUrl.isEmpty) {
        throw StreamResolutionException('Empty stream URL returned');
      }

      // 4. Post-process the result
      finalUrl = _stripPrefixes(finalUrl);
      finalUrl = _extractHttpUrl(finalUrl);
      finalUrl = _selectFirstValidUrl(finalUrl);
      finalUrl = _replaceLocalhost(finalUrl);

      // 5. Dio automatically follows redirects up to a certain limit
      // If we need manual redirect following, we would do it here using dio.options.followRedirects = false
      // For now, we assume Dio handles the 5 redirects natively.

      return finalUrl;

    } on DioException catch (e) {
      throw StreamResolutionException('Network error resolving stream: ${e.message}');
    }
  }
}
