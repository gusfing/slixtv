import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/network/api_client.dart';
import '../domain/models.dart' show VodItem;
import '../../auth/domain/providers.dart';
import '../../player/presentation/player_screen.dart';
import '../../auth/data/models.dart' show SubtitleInfo;

class MovieDetailScreen extends ConsumerStatefulWidget {
  final VodItem movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  bool _isLoadingStream = false;
  String? _streamError;

  Future<void> _playMovie(VodItem movie) async {
    if (_isLoadingStream) return;
    if (!movie.hasFiles) {
      setState(() => _streamError = 'This title is not yet available on the streaming server.');
      return;
    }
    if (movie.cmd.isEmpty) {
      setState(() => _streamError = 'No stream source found for this title.');
      return;
    }

    setState(() {
      _isLoadingStream = true;
      _streamError = null;
    });

    try {
      final moviesService = ref.read(moviesServiceProvider);
      final streamUrl = await moviesService.createVodLink(movie);
      final subtitles = moviesService.lastResolvedSubtitles;

      if (!mounted) return;
      setState(() => _isLoadingStream = false);

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: movie.name,
          subtitle: movie.year.isNotEmpty ? movie.year : null,
          contentId: 'vod_${movie.id}',
          videoId: movie.id,
          originalCmd: movie.cmd,
          contentType: 'vod',
          externalSubtitles: subtitles,
          poster: movie.poster,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('PortalException: ', '');
      setState(() {
        _isLoadingStream = false;
        _streamError = msg;
      });
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final favorites = ref.watch(favoritesProvider);
    final isLiked = favorites['movie']?.contains(movie.id) ?? false;

    // Join metadata for display
    final metadataParts = [
      if (movie.year.isNotEmpty) movie.year,
      if (movie.genre.isNotEmpty && movie.genre != 'null') movie.genre,
      if (movie.duration.isNotEmpty && movie.duration != 'null') 'm',
    ];
    final metadataString = metadataParts.join(' • ');

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              AppColors.backgroundLight,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background image blurred overlay
            Positioned.fill(
              child: movie.poster.isNotEmpty
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Opacity(
                        opacity: 0.15,
                        child: CachedNetworkImage(
                          imageUrl: movie.poster,
                          httpHeaders: ApiClient().getStalkerHeaders(),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : const SizedBox(),
            ),

            SafeArea(
              child: Column(
                children: [
                  // App bar (Standard Left-aligned Back, Right-aligned Favorite)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isLiked ? Colors.red : Colors.white,
                            size: 22,
                          ),
                          onPressed: () {
                            ref.read(favoritesProvider.notifier).toggleFavorite('movie', movie.id);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Main Details Layout - Vertical for Mobile
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Center Poster
                            Container(
                              width: 160,
                              height: 240,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: movie.poster.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: movie.poster,
                                        httpHeaders: ApiClient().getStalkerHeaders(),
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64, color: Colors.white24),
                                      )
                                    : const Icon(Icons.movie, size: 64, color: Colors.white24),
                              ),
                            ),
                            if (movie.rating.isNotEmpty && movie.rating != '0' && movie.rating != '0.0' && movie.rating != 'null') ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    movie.rating,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),
                            
                            // Title
                            Text(
                              movie.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),

                            // Horizontal Metadata row
                            if (metadataString.isNotEmpty) ...[
                              Text(
                                metadataString,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Action Watch Now Row
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: movie.hasFiles ? AppColors.primary : Colors.grey,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              icon: _isLoadingStream
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : const Icon(Icons.play_arrow_rounded, size: 24),
                              label: Text(
                                _isLoadingStream
                                    ? 'RESOLVING STREAM...'
                                    : movie.hasFiles
                                        ? 'WATCH NOW'
                                        : 'UNAVAILABLE',
                                        
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
                              ),
                              onPressed: movie.cmd.isEmpty || !movie.hasFiles ? null : () => _playMovie(movie),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Error message if any
                            if (_streamError != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.error.withOpacity(0.5)),
                                ),
                                child: Text(
                                  _streamError!,
                                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            const SizedBox(height: 20),

                            // Compact Cast / Director details
                            if (movie.director.isNotEmpty && movie.director != 'null') ...[
                              Text(
                                'Director: ',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (movie.actors.isNotEmpty && movie.actors != 'null') ...[
                              Text(
                                'Cast: ',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Synopsis
                            if (movie.description.isNotEmpty && movie.description != 'null') ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'PLOT SUMMARY',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  movie.description,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
