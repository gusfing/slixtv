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

    final movieId = json['id']?.toString() ?? '';
    final movieName = json['name']?.toString() ??
        json['o_name']?.toString() ??
        json['old_name']?.toString() ??
        '';

    // ── CMD EXTRACTION ────────────────────────────────────────
    // Read the raw json['cmd'] FIRST before running extractBestPlaybackCmd.
    // We do NOT pass it through the extractor blindly — if it's a /media/ path,
    // we skip it and try alternate fields.
    final rawJsonCmd = json['cmd']?.toString() ?? '';
    
    // Try extracting from alternate fields (ffmpeg_cmd, stream_cmd, etc.)
    // but explicitly exclude the raw cmd field so we can evaluate it separately.
    final altFields = ['ffmpeg_cmd', 'stream_cmd', 'stream_url', 'play_url', 'video_url', 'url', 'file'];
    String? altCmd;
    for (final f in altFields) {
      final v = json[f]?.toString();
      if (v != null && v.isNotEmpty) { altCmd = v; break; }
    }

    // Priority:
    // 1. rawJsonCmd if it's a real STB stream (not /media/)
    // 2. altCmd from alternate fields
    // 3. rawJsonCmd even if /media/ (last resort, so the field isn't empty)
    String cmd;
    if (rawJsonCmd.isNotEmpty && !rawJsonCmd.startsWith('/media/')) {
      cmd = rawJsonCmd;
    } else if (altCmd != null && altCmd.isNotEmpty) {
      cmd = altCmd;
    } else {
      cmd = rawJsonCmd; // keep /media/ as last resort so we still have something
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
