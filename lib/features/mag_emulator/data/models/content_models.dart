class MagCategory {
  final String id;
  final String title;

  MagCategory({required this.id, required this.title});

  factory MagCategory.fromMap(Map<String, dynamic> map) {
    return MagCategory(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? map['name']?.toString() ?? 'Unknown',
    );
  }
}

class MagChannel {
  final String id;
  final String name;
  final String number;
  final String logo;
  final String cmd;

  MagChannel({
    required this.id,
    required this.name,
    required this.number,
    required this.logo,
    required this.cmd,
  });

  factory MagChannel.fromMap(Map<String, dynamic> map, String baseUrl) {
    String logoUrl = map['logo']?.toString() ?? '';
    if (logoUrl.isNotEmpty && !logoUrl.startsWith('http')) {
      if (logoUrl.startsWith('/')) {
        logoUrl = '$baseUrl$logoUrl';
      } else {
        logoUrl = '$baseUrl/$logoUrl';
      }
    }

    return MagChannel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      number: map['number']?.toString() ?? '',
      logo: logoUrl,
      cmd: map['cmd']?.toString() ?? '',
    );
  }
}

class MagEpg {
  final String id;
  final String name;
  final String time;
  final String timeTo;
  final String tTime;

  MagEpg({
    required this.id,
    required this.name,
    required this.time,
    required this.timeTo,
    required this.tTime,
  });

  factory MagEpg.fromMap(Map<String, dynamic> map) {
    return MagEpg(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      time: map['time']?.toString() ?? '',
      timeTo: map['time_to']?.toString() ?? '',
      tTime: map['t_time']?.toString() ?? '',
    );
  }
}

class MagMovie {
  final String id;
  final String name;
  final String description;
  final String director;
  final String actors;
  final String year;
  final String rating;
  final String poster;
  final String cmd;

  MagMovie({
    required this.id,
    required this.name,
    required this.description,
    required this.director,
    required this.actors,
    required this.year,
    required this.rating,
    required this.poster,
    required this.cmd,
  });

  factory MagMovie.fromMap(Map<String, dynamic> map, String baseUrl) {
    String posterUrl = '';
    final posterFields = ['cover_big', 'cover', 'poster', 'screenshot_uri', 'icon', 'logo', 'image'];
    
    for (final field in posterFields) {
      if (map[field] != null && map[field].toString().isNotEmpty) {
        posterUrl = map[field].toString();
        break;
      }
    }

    if (posterUrl.isNotEmpty && !posterUrl.startsWith('http')) {
      if (posterUrl.startsWith('/')) {
        posterUrl = '$baseUrl$posterUrl';
      } else {
        posterUrl = '$baseUrl/$posterUrl';
      }
    }

    return MagMovie(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      description: map['description']?.toString() ?? '',
      director: map['director']?.toString() ?? '',
      actors: map['actors']?.toString() ?? '',
      year: map['year']?.toString() ?? '',
      rating: map['rating']?.toString() ?? '',
      poster: posterUrl,
      cmd: map['cmd']?.toString() ?? '',
    );
  }
}

class MagSeries {
  final String id;
  final String name;
  final String description;
  final String actors;
  final String director;
  final String year;
  final String poster;

  MagSeries({
    required this.id,
    required this.name,
    required this.description,
    required this.actors,
    required this.director,
    required this.year,
    required this.poster,
  });

  factory MagSeries.fromMap(Map<String, dynamic> map, String baseUrl) {
    String posterUrl = '';
    final posterFields = ['cover_big', 'cover', 'poster', 'screenshot_uri', 'icon', 'logo', 'image'];
    
    for (final field in posterFields) {
      if (map[field] != null && map[field].toString().isNotEmpty) {
        posterUrl = map[field].toString();
        break;
      }
    }

    if (posterUrl.isNotEmpty && !posterUrl.startsWith('http')) {
      if (posterUrl.startsWith('/')) {
        posterUrl = '$baseUrl$posterUrl';
      } else {
        posterUrl = '$baseUrl/$posterUrl';
      }
    }

    return MagSeries(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      description: map['description']?.toString() ?? '',
      actors: map['actors']?.toString() ?? '',
      director: map['director']?.toString() ?? '',
      year: map['year']?.toString() ?? '',
      poster: posterUrl,
    );
  }
}

class MagEpisode {
  final String id;
  final String name;
  final String season;
  final String episode;
  final String cmd;
  final String time;

  MagEpisode({
    required this.id,
    required this.name,
    required this.season,
    required this.episode,
    required this.cmd,
    required this.time,
  });

  factory MagEpisode.fromMap(Map<String, dynamic> map, String fallbackSeason) {
    return MagEpisode(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? map['title']?.toString() ?? 'Unknown',
      season: map['season']?.toString() ?? fallbackSeason,
      episode: map['episode']?.toString() ?? map['series']?.toString() ?? '',
      cmd: map['cmd']?.toString() ?? '',
      time: map['time']?.toString() ?? '',
    );
  }
}

class MagSeason {
  final String seasonNumber;
  final List<MagEpisode> episodes;

  MagSeason({required this.seasonNumber, required this.episodes});
}
