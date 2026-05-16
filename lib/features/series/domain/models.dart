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

  const Episode({
    required this.id,
    required this.name,
    required this.cmd,
    required this.episodeNumber,
    this.duration = '',
    this.poster = '',
    this.description = '',
  });

  factory Episode.fromJson(Map<String, dynamic> json, int index, ApiClient client, {String? seriesCmd}) {
    final poster = PosterResolver.resolve(json, client);
    
    // Utilize the robust extractor for the episode object itself
    String cmd = StalkerParser.extractBestPlaybackCmd(json, null) ?? '';
    if (cmd.isEmpty && seriesCmd != null && seriesCmd.isNotEmpty) {
      cmd = seriesCmd;
    }

    return Episode(
      id: json['id']?.toString() ?? index.toString(),
      name: json['name']?.toString() ??
          json['title']?.toString() ??
          'Episode ${index + 1}',
      cmd: cmd,
      episodeNumber: int.tryParse(json['series_num']?.toString() ?? '') ??
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
    );
  }
}
