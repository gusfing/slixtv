import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';

class VodItem {
  final String id;
  final String name;
  final String description;
  final String poster;
  final String cmd;
  final String categoryId;
  final String year;
  final String rating;
  final String director;
  final String actors;
  final String genre;
  final String duration;
  final bool hasFiles;

  const VodItem({
    required this.id,
    required this.name,
    this.description = '',
    this.poster = '',
    this.cmd = '',
    this.categoryId = '',
    this.year = '',
    this.rating = '',
    this.director = '',
    this.actors = '',
    this.genre = '',
    this.duration = '',
    this.hasFiles = true,
  });

  factory VodItem.fromJson(Map<String, dynamic> json, ApiClient client) {
    final poster = PosterResolver.resolve(json, client);
    
    // has_files=1 means content is available on the streaming server
    final hasFiles = json['has_files'] == 1 ||
        json['has_files'] == true ||
        json['has_files'] == '1';

    return VodItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ??
          json['o_name']?.toString() ??
          json['old_name']?.toString() ??
          '',
      description: _nonNull(json['description']) ??
          _nonNull(json['descr']) ??
          _nonNull(json['o_name']) ??
          '',
      poster: poster,
      cmd: StalkerParser.extractBestPlaybackCmd(json, null) ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      year: _nonNull(json['year']) ?? '',
      rating: _nonNull(json['rating_imdb'])?.toString() ??
          _nonNull(json['rating_kinopoisk'])?.toString() ??
          _nonNull(json['rate'])?.toString() ??
          '',
      director: _nonNull(json['director']) ?? '',
      actors: _nonNull(json['actors']) ?? _nonNull(json['cast']) ?? '',
      genre: _nonNull(json['genres_str']) ??
          _nonNull(json['genre_str']) ??
          _nonNull(json['genre']) ??
          '',
      duration: _nonNull(json['time']) ??
          _nonNull(json['length']) ??
          _nonNull(json['duration']) ??
          '',
      hasFiles: hasFiles,
    );
  }

  static String? _nonNull(dynamic v) {
    if (v == null || v == 'null' || v == '' || v == 0 || v == '0.0') return null;
    final s = v.toString();
    return s.isEmpty || s == 'null' ? null : s;
  }
}
