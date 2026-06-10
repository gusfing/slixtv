import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';

class SeriesItem {
  final String id;
  final String name;
  final String description;
  final String poster;
  final String categoryId;
  final String year;
  final String rating;
  final String genre;
  final String director;
  final String actors;
  final String seriesCount;
  final String cmd;

  const SeriesItem({
    required this.id,
    required this.name,
    this.description = '',
    this.poster = '',
    this.categoryId = '',
    this.year = '',
    this.rating = '',
    this.genre = '',
    this.director = '',
    this.actors = '',
    this.seriesCount = '',
    this.cmd = '',
  });

  factory SeriesItem.fromJson(Map<String, dynamic> json, ApiClient client) {
    final poster = PosterResolver.resolve(json, client);

    return SeriesItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ??
          json['descr']?.toString() ??
          '',
      poster: poster,
      categoryId: json['category_id']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      rating: json['rating_imdb']?.toString() ?? json['rating']?.toString() ?? '',
      genre: json['genre_str']?.toString() ?? json['genre']?.toString() ?? '',
      director: json['director']?.toString() ?? '',
      actors: json['actors']?.toString() ?? '',
      seriesCount: json['series_count']?.toString() ??
          json['count']?.toString() ??
          json['episode_count']?.toString() ??
          '',
      cmd: json['cmd']?.toString() ?? '',
    );
  }
}

class Season {
  final String id;
  final String name;
  final int seasonNumber;
  final List<Episode> episodes;

  const Season({
    required this.id,
    required this.name,
    required this.seasonNumber,
    this.episodes = const [],
  });
}

class Episode {
  final String id;
  final String name;
  final String cmd; 
  final int episodeNumber;
  final String duration;
  final String poster;
  final String description;
  final Map<String, dynamic>? rawJson;
  final bool isLocked;
  final String seriesNumber;

  const Episode({
    required this.id,
    required this.name,
    required this.cmd,
    required this.episodeNumber,
    this.duration = '',
    this.poster = '',
    this.description = '',
    this.rawJson,
    this.isLocked = false,
    this.seriesNumber = '',
  });

  factory Episode.fromJson(Map<String, dynamic> json, int index, ApiClient client, {String? seriesCmd}) {
    debugPrint('RAW_EPISODE_JSON: $json');

    final poster = PosterResolver.resolve(json, client);

    // The portal returns file items with is_file=true.
    // These have an 'id' that is the file ID, and a 'cmd' that is a direct HTTP URL.
    // create_link ONLY works with /media/file_<fileId>.mpg format — NOT with the
    // raw HTTP cmd from the catalog. So if this is a file item, use its id to build
    // the proper cmd. This is the same approach that fixed movies.
    final fileId = json['id']?.toString() ?? '';
    final isFile = json['is_file'] == true ||
        json['is_file'] == 'true' ||
        json['is_file'] == 1 ||
        json['is_file'] == '1';

    String cmd;
    if (isFile && fileId.isNotEmpty) {
      // Use /media/file_<id>.mpg — this is what create_link expects
      cmd = '/media/file_$fileId.mpg';
    } else {
      // Not a file item: try cmd/movie_url fields first
      String? foundCmd;
      for (final k in ['cmd', 'movie_url']) {
        final val = json[k]?.toString();
        if (val != null && val.trim().isNotEmpty && !val.startsWith('http')) {
          // Only use non-HTTP cmd values — HTTP values from the catalog fail create_link
          foundCmd = val;
          break;
        }
      }
      cmd = foundCmd ?? '';
    }

    // Extract series_number for the create_link 'series' parameter
    final seriesNum = json['series_number']?.toString() ??
        json['series_num']?.toString() ??
        json['episode_num']?.toString() ??
        '';

    final nameStr = json['name']?.toString() ??
        json['title']?.toString() ??
        'Episode ${index + 1}';

    int? parsedEpNum;
    if (nameStr.isNotEmpty) {
      final regExp = RegExp(r'(?:episode|ep|ep\.|e)\s*(\d+)', caseSensitive: false);
      final match = regExp.firstMatch(nameStr);
      if (match != null) {
        parsedEpNum = int.tryParse(match.group(1) ?? '');
      }
    }

    return Episode(
      id: fileId.isNotEmpty ? fileId : index.toString(),
      name: nameStr,
      cmd: cmd,
      episodeNumber: parsedEpNum ??
          int.tryParse(json['series_number']?.toString() ?? '') ??
          int.tryParse(json['series_num']?.toString() ?? '') ??
          int.tryParse(json['episode_num']?.toString() ?? '') ??
          index + 1,
      duration: json['time']?.toString() ??
          json['length']?.toString() ??
          json['duration']?.toString() ??
          '',
      poster: poster,
      description: json['descr']?.toString() ??
          json['description']?.toString() ??
          '',
      rawJson: json,
      isLocked: false,
      seriesNumber: seriesNum,
    );
  }
}
