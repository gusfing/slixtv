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
  final Map<String, dynamic>? rawJson;

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
    this.rawJson,
  });

  factory VodItem.fromJson(Map<String, dynamic> json, ApiClient client) {
    final poster = PosterResolver.resolve(json, client);
    
    // has_files=1 means content is available on the streaming server
    final hasFiles = json['has_files'] == 1 ||
        json['has_files'] == true ||
        json['has_files'] == '1';

    final movieId = json['id']?.toString() ?? '';
    final movieName = json['name']?.toString() ??
        json['o_name']?.toString() ??
        json['old_name']?.toString() ??
        '';

    // ── CMD EXTRACTION ────────────────────────────────────────
    // Use exact cmd returned by portal catalog response
    final rawJsonCmd = json['cmd']?.toString() ?? '';
    
    // Try extracting from alternate fields if cmd is empty
    final altFields = ['ffmpeg_cmd', 'stream_cmd', 'stream_url', 'play_url', 'video_url', 'url', 'file'];
    String? altCmd;
    for (final f in altFields) {
      final v = json[f]?.toString();
      if (v != null && v.isNotEmpty) { altCmd = v; break; }
    }

    String cmd = rawJsonCmd;
    if (cmd.isEmpty && altCmd != null && altCmd.isNotEmpty) {
      cmd = altCmd;
    }

    print('[VOD_FROM_JSON_CMD] movieId=$movieId name=$movieName rawJsonCmd=$rawJsonCmd altCmd=$altCmd chosenCmd=$cmd');

    return VodItem(
      id: movieId,
      name: movieName,
      description: _nonNull(json['description']) ??
          _nonNull(json['descr']) ??
          _nonNull(json['o_name']) ??
          '',
      poster: poster,
      cmd: cmd,
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
      rawJson: json,
    );
  }

  /// Creates a copy of this item with updated info fields, preserving cmd
  /// unless a better (non-/media/) replacement is explicitly provided.
  VodItem copyWith({
    String? description,
    String? poster,
    String? cmd,
    String? year,
    String? rating,
    String? director,
    String? actors,
    String? genre,
    String? duration,
    bool? hasFiles,
    Map<String, dynamic>? rawJson,
  }) {
    return VodItem(
      id: id,
      name: name,
      description: description ?? this.description,
      poster: poster ?? this.poster,
      cmd: cmd ?? this.cmd,
      categoryId: categoryId,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      director: director ?? this.director,
      actors: actors ?? this.actors,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      hasFiles: hasFiles ?? this.hasFiles,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'poster': poster,
      'cmd': cmd,
      'category_id': categoryId,
      'year': year,
      'rating': rating,
      'director': director,
      'actors': actors,
      'genre': genre,
      'duration': duration,
      'has_files': hasFiles ? 1 : 0,
    };
  }

  static String? _nonNull(dynamic v) {
    if (v == null || v == 'null' || v == '' || v == 0 || v == '0.0') return null;
    final s = v.toString();
    return s.isEmpty || s == 'null' ? null : s;
  }
}
