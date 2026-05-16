import '../../../core/network/api_client.dart';

/// Models for MAG/Stalker middleware data.

// ─── Auth Models ─────────────────────────────────────────────

class StalkerProfile {
  final String id;
  final String name;
  final String mac;
  final String ip;
  final String phone;
  final String lsUdp;
  final String endDate;
  final bool status;
  final Map<String, dynamic> raw;

  const StalkerProfile({
    required this.id,
    required this.name,
    required this.mac,
    required this.ip,
    this.phone = '',
    this.lsUdp = '',
    this.endDate = '',
    this.status = true,
    this.raw = const {},
  });

  factory StalkerProfile.fromJson(Map<String, dynamic> json) {
    String parsedName = json['name']?.toString() ?? '';
    if (parsedName.isEmpty) {
      parsedName = json['fname']?.toString() ??
          json['login']?.toString() ??
          'User';
    }
    // Stalker: status="0" = Active, status="1" = Inactive, blocked="1" = Blocked
    final isActive = json['status']?.toString() != '1' &&
        json['blocked']?.toString() != '1';

    return StalkerProfile(
      id: json['id']?.toString() ?? '',
      name: parsedName,
      mac: json['mac']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      lsUdp: json['ls_udp_url']?.toString() ?? '',
      endDate: json['end_date']?.toString() ??
          json['tariff_expired_date']?.toString() ??
          json['expire_billing_date']?.toString() ??
          '',
      status: isActive,
      raw: json,
    );
  }
}

class StalkerMainInfo {
  final String serverName;
  final String timezone;
  final bool allowLocalRecording;
  final String screensaverDelay;
  final Map<String, dynamic> raw;

  const StalkerMainInfo({
    required this.serverName,
    this.timezone = 'UTC',
    this.allowLocalRecording = false,
    this.screensaverDelay = '300',
    this.raw = const {},
  });

  factory StalkerMainInfo.fromJson(Map<String, dynamic> json) {
    return StalkerMainInfo(
      serverName: json['server_name']?.toString() ??
          json['portal_name']?.toString() ??
          '',
      timezone: json['timezone']?.toString() ?? 'UTC',
      allowLocalRecording: json['allow_local_recording'] == 1,
      screensaverDelay: json['screensaver_delay']?.toString() ?? '300',
      raw: json,
    );
  }
}

// ─── Category ────────────────────────────────────────────────

class Category {
  final String id;
  final String title;
  final String alias;
  final int? number;
  final int? channelCount;
  final String censored;

  const Category({
    required this.id,
    required this.title,
    this.alias = '',
    this.number,
    this.channelCount,
    this.censored = '0',
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      alias: json['alias']?.toString() ?? '',
      number: int.tryParse(json['number']?.toString() ?? ''),
      channelCount: int.tryParse(
          json['cnt']?.toString() ?? json['count']?.toString() ?? ''),
      censored: json['censored']?.toString() ?? '0',
    );
  }
}

// ─── Channel ─────────────────────────────────────────────────

class Channel {
  final String id;
  final String name;
  final String number;
  final String logo;
  final String cmd;
  final String categoryId;
  final bool useHttpTmpLink;
  final bool useLoadBalancing;
  final String tvGenreId;
  final bool isFavorite;
  final EpgProgram? currentProgram;
  final EpgProgram? nextProgram;

  const Channel({
    required this.id,
    required this.name,
    this.number = '',
    this.logo = '',
    this.cmd = '',
    this.categoryId = '',
    this.useHttpTmpLink = true,
    this.useLoadBalancing = false,
    this.tvGenreId = '',
    this.isFavorite = false,
    this.currentProgram,
    this.nextProgram,
  });

  Channel copyWith({
    bool? isFavorite,
    EpgProgram? currentProgram,
    EpgProgram? nextProgram,
  }) =>
      Channel(
        id: id, name: name, number: number, logo: logo, cmd: cmd,
        categoryId: categoryId, useHttpTmpLink: useHttpTmpLink,
        useLoadBalancing: useLoadBalancing, tvGenreId: tvGenreId,
        isFavorite: isFavorite ?? this.isFavorite,
        currentProgram: currentProgram ?? this.currentProgram,
        nextProgram: nextProgram ?? this.nextProgram,
      );

  factory Channel.fromJson(Map<String, dynamic> json, {ApiClient? client}) {
    final rawLogo = json['logo']?.toString() ?? '';
    final logo = client?.resolveUrl(rawLogo) ?? rawLogo;
    return Channel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      logo: logo,
      cmd: json['cmd']?.toString() ?? '',
      categoryId: json['tv_genre_id']?.toString() ?? '',
      useHttpTmpLink:
          json['use_http_tmp_link'] == 1 || json['use_http_tmp_link'] == true,
      useLoadBalancing: json['use_load_balancing'] == 1,
      tvGenreId: json['tv_genre_id']?.toString() ?? '',
    );
  }
}

// ─── EPG ─────────────────────────────────────────────────────

class EpgProgram {
  final String id;
  final String name;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String channelId;
  final bool isLive;

  const EpgProgram({
    required this.id,
    required this.name,
    this.description = '',
    required this.startTime,
    required this.endTime,
    this.channelId = '',
    this.isLive = false,
  });

  double get progress {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final total = endTime.difference(startTime).inSeconds;
    final elapsed = now.difference(startTime).inSeconds;
    return total > 0 ? elapsed / total : 0.0;
  }

  String get timeRange {
    String fmt(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${fmt(startTime)} - ${fmt(endTime)}';
  }

  factory EpgProgram.fromJson(Map<String, dynamic> json) {
    return EpgProgram(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['title']?.toString() ?? '',
      description:
          json['descr']?.toString() ?? json['description']?.toString() ?? '',
      startTime: _parseTime(
          json['time']?.toString() ?? json['start_timestamp']?.toString()),
      endTime: _parseTime(
          json['time_to']?.toString() ?? json['stop_timestamp']?.toString()),
      channelId: json['ch_id']?.toString() ?? '',
    );
  }

  static DateTime _parseTime(String? t) {
    if (t == null || t.isEmpty) return DateTime.now();
    final ts = int.tryParse(t);
    if (ts != null) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return DateTime.tryParse(t) ?? DateTime.now();
  }
}

// ─── VOD / Movie ─────────────────────────────────────────────

class VodItem {
  final String id;
  final String name;
  final String description;
  final String poster;   // always absolute URL
  final String cmd;      // raw MAG cmd — pass to createLink, NOT directly to player
  final String categoryId;
  final String year;
  final String rating;
  final String director;
  final String actors;
  final String genre;
  final String duration;  // in minutes (string)
  final bool hasFiles;    // false = content unavailable on server
  final bool isFavorite;
  final int watchProgress;

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
    this.isFavorite = false,
    this.watchProgress = 0,
  });

  VodItem copyWith({
    bool? isFavorite,
    int? watchProgress,
    String? description,
    String? rating,
    String? director,
    String? actors,
    String? genre,
    String? duration,
  }) =>
      VodItem(
        id: id, name: name,
        description: description ?? this.description,
        poster: poster, cmd: cmd, categoryId: categoryId, year: year,
        rating: rating ?? this.rating,
        director: director ?? this.director,
        actors: actors ?? this.actors,
        genre: genre ?? this.genre,
        duration: duration ?? this.duration,
        hasFiles: hasFiles,
        isFavorite: isFavorite ?? this.isFavorite,
        watchProgress: watchProgress ?? this.watchProgress,
      );

  factory VodItem.fromJson(Map<String, dynamic> json, {ApiClient? client}) {
    // Poster field priority: cover_big > cover > poster > screenshot_uri > icon > logo > image
    final rawPoster = json['cover_big']?.toString().isNotEmpty == true
        ? json['cover_big'].toString()
        : json['cover']?.toString().isNotEmpty == true
            ? json['cover'].toString()
            : json['poster']?.toString().isNotEmpty == true
                ? json['poster'].toString()
                : json['screenshot_uri']?.toString().isNotEmpty == true
                    ? json['screenshot_uri'].toString()
                    : json['icon']?.toString().isNotEmpty == true
                        ? json['icon'].toString()
                        : json['logo']?.toString().isNotEmpty == true
                            ? json['logo'].toString()
                            : json['image']?.toString() ?? '';

    // Resolve relative URLs to absolute using portal base
    final poster = (rawPoster.isNotEmpty && rawPoster != 'null')
        ? (client?.resolveUrl(rawPoster) ?? rawPoster)
        : '';

    // cmd: the MAG stream command sent to createLink (not played directly)
    final cmd = json['cmd']?.toString() ?? json['video_url']?.toString() ?? '';

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

  static String? _nonNull(dynamic v) {
    if (v == null || v == 'null' || v == '' || v == 0 || v == '0.0') return null;
    final s = v.toString();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

// ─── Series ──────────────────────────────────────────────────

class SeriesItem {
  final String id;
  final String name;
  final String description;
  final String poster;     // always absolute URL
  final String categoryId;
  final String year;
  final String rating;
  final String genre;
  final String director;
  final String actors;
  final String seriesCount;
  final List<Season> seasons;
  final bool isFavorite;

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
    this.seasons = const [],
    this.isFavorite = false,
  });

  SeriesItem copyWith({List<Season>? seasons, bool? isFavorite}) => SeriesItem(
        id: id, name: name, description: description, poster: poster,
        categoryId: categoryId, year: year, rating: rating, genre: genre,
        director: director, actors: actors, seriesCount: seriesCount,
        seasons: seasons ?? this.seasons,
        isFavorite: isFavorite ?? this.isFavorite,
      );

  factory SeriesItem.fromJson(Map<String, dynamic> json, {ApiClient? client}) {
    final rawPoster = json['cover_big']?.toString().isNotEmpty == true
        ? json['cover_big'].toString()
        : json['cover']?.toString().isNotEmpty == true
            ? json['cover'].toString()
            : json['poster']?.toString().isNotEmpty == true
                ? json['poster'].toString()
                : json['screenshot_uri']?.toString().isNotEmpty == true
                    ? json['screenshot_uri'].toString()
                    : json['icon']?.toString().isNotEmpty == true
                        ? json['icon'].toString()
                        : json['logo']?.toString().isNotEmpty == true
                            ? json['logo'].toString()
                            : json['image']?.toString() ?? '';

    // Resolve relative URLs to absolute using portal base
    final poster = (rawPoster.isNotEmpty && rawPoster != 'null')
        ? (client?.resolveUrl(rawPoster) ?? rawPoster)
        : '';

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

// ─── Season ──────────────────────────────────────────────────

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

// ─── Episode ─────────────────────────────────────────────────

class Episode {
  final String id;
  final String name;
  final String cmd;      // raw MAG cmd → pass to createLink
  final int episodeNumber;
  final String duration;
  final String poster;
  final String description;
  final int watchProgress;

  const Episode({
    required this.id,
    required this.name,
    required this.cmd,
    required this.episodeNumber,
    this.duration = '',
    this.poster = '',
    this.description = '',
    this.watchProgress = 0,
  });

  factory Episode.fromJson(Map<String, dynamic> json, int index, {ApiClient? client}) {
    final rawPoster = json['cover_big']?.toString().isNotEmpty == true
        ? json['cover_big'].toString()
        : json['cover']?.toString().isNotEmpty == true
            ? json['cover'].toString()
            : json['poster']?.toString().isNotEmpty == true
                ? json['poster'].toString()
                : json['screenshot_uri']?.toString().isNotEmpty == true
                    ? json['screenshot_uri'].toString()
                    : json['icon']?.toString().isNotEmpty == true
                        ? json['icon'].toString()
                        : json['logo']?.toString().isNotEmpty == true
                            ? json['logo'].toString()
                            : json['image']?.toString() ?? '';

    final poster = rawPoster.isNotEmpty && rawPoster != 'null'
        ? (client?.resolveUrl(rawPoster) ?? rawPoster)
        : '';

    final cmd = json['cmd']?.toString() ?? json['video_url']?.toString() ?? '';

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
