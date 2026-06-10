import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show SubtitleInfo;
import '../../player/presentation/player_screen.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/stalker_parser.dart';
import '../domain/models.dart' show SeriesItem, Season, Episode;

class SeriesSeasonsScreen extends ConsumerStatefulWidget {
  final SeriesItem series;

  const SeriesSeasonsScreen({super.key, required this.series});

  @override
  ConsumerState<SeriesSeasonsScreen> createState() => _SeriesSeasonsScreenState();
}

class _SeriesSeasonsScreenState extends ConsumerState<SeriesSeasonsScreen> {
  int _selectedSeasonIndex = 0;
  String? _playingEpisodeId;

  Future<void> _playEpisode(Episode ep, List<Episode> episodes, int index) async {
    setState(() => _playingEpisodeId = ep.id);

    final episode = ep.rawJson;
    String cmd = ep.cmd;

    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      List<SubtitleInfo> externalSubtitles = const [];

      String? directUrl;
      if (!cmd.startsWith('/media/file_')) {
        final parentId = widget.series.id;
        final episodeId = ep.id;
        final seasonId = ep.rawJson?['season_id']?.toString() ?? '';

        final response = await stalkerApi.resolveEpisodeFileResponse(
          seriesId: parentId,
          episodeId: episodeId,
          seasonId: seasonId,
        );
        debugPrint('RAW_SERIES_EPISODE_RESPONSE: $response');

        final js = response['js'];
        if (js != null && js != false) {
          final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
          if (rawList.isNotEmpty) {
            final firstItem = rawList.first;
            if (firstItem is Map<String, dynamic>) {
              directUrl = firstItem['cmd']?.toString() ?? firstItem['url']?.toString();
              final fileId = firstItem['id']?.toString();
              if (fileId != null && fileId.isNotEmpty) {
                cmd = '/media/file_$fileId.mpg';
              }
            }
          }
        }
      } else {
        debugPrint('RAW_SERIES_EPISODE_RESPONSE: {}');
      }

      debugPrint('SELECTED_EPISODE_JSON: $episode');
      debugPrint('SELECTED_EPISODE_CMD: $cmd');

      String streamUrl;
      try {
        streamUrl = await stalkerApi.createLink(
          cmd,
          AppConfig.typeSeries,
          seriesId: ep.seriesNumber.isNotEmpty ? ep.seriesNumber : ep.id,
          itemObject: ep.rawJson,
          parentSeriesId: widget.series.id,
        );
        externalSubtitles = stalkerApi.lastResolvedSubtitles;
      } catch (e) {
        if (directUrl != null && directUrl.isNotEmpty) {
          debugPrint('SERIES_SEASONS_SCREEN: createLink failed, falling back to direct URL: $directUrl');
          streamUrl = directUrl;
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      setState(() => _playingEpisodeId = null);

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: widget.series.name,
          subtitle: ep.name,
          contentId: 'ep_${ep.id}',
          videoId: widget.series.id,
          originalCmd: cmd,
          contentType: 'series',
          seriesId: ep.id,
          episodes: episodes,
          currentEpisodeIndex: index,
          externalSubtitles: externalSubtitles,
          poster: widget.series.poster,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingEpisodeId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(seriesInfoProvider((seriesId: widget.series.id, seriesCmd: widget.series.cmd)));

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
              child: widget.series.poster.isNotEmpty
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                      child: Opacity(
                        opacity: 0.15,
                        child: CachedNetworkImage(
                          imageUrl: widget.series.poster,
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
                  // App Bar themed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.series.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),

                  // Main content splits (Seasons left, Episodes right)
                  Expanded(
                    child: seasonsAsync.when(
                      loading: () => const LoadingIndicator(message: 'Loading episodes...'),
                      error: (err, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                            const SizedBox(height: 12),
                            Text('Failed to load season details: $err', style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => ref.invalidate(seriesInfoProvider((seriesId: widget.series.id, seriesCmd: widget.series.cmd))),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                      data: (seasons) {
                        if (seasons.isEmpty) {
                          return const Center(
                            child: Text(
                              'No seasons available',
                              style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
                            ),
                          );
                        }

                        final currentSeason = seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)];

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Pane: Seasons selector (22% width)
                            Container(
                              width: MediaQuery.of(context).size.width * 0.22,
                              margin: const EdgeInsets.only(left: 16, bottom: 16, top: 8),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: seasons.length,
                                itemBuilder: (context, i) {
                                  final isSelected = i == _selectedSeasonIndex;
                                  return _SeasonCard(
                                    title: seasons[i].name.toUpperCase(),
                                    isSelected: isSelected,
                                    onTap: () => setState(() => _selectedSeasonIndex = i),
                                  );
                                },
                              ),
                            ),

                            // Right Pane: Episodes list
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: currentSeason.episodes.length,
                                itemBuilder: (context, i) {
                                  final ep = currentSeason.episodes[i];
                                  final isPlaying = _playingEpisodeId == ep.id;
                                  return _EpisodeCardItem(
                                    index: i + 1,
                                    episode: ep,
                                    isPlaying: isPlaying,
                                    onTap: ep.isLocked ? null : () => _playEpisode(ep, currentSeason.episodes, i),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
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

class _SeasonCard extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeasonCard({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SeasonCard> createState() => _SeasonCardState();
}

class _SeasonCardState extends State<_SeasonCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _isFocused;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: widget.isSelected ? AppColors.primary : Colors.transparent,
                width: 3.5,
              ),
            ),
          ),
          child: Text(
            widget.title,
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCardItem extends StatefulWidget {
  final int index;
  final Episode episode;
  final bool isPlaying;
  final VoidCallback? onTap;

  const _EpisodeCardItem({
    required this.index,
    required this.episode,
    required this.isPlaying,
    this.onTap,
  });

  @override
  State<_EpisodeCardItem> createState() => _EpisodeCardItemState();
}

class _EpisodeCardItemState extends State<_EpisodeCardItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = _isFocused || _isHovered;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.surfaceLight : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Play / Lock Circle indicator
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.episode.isLocked
                          ? Colors.transparent
                          : AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: widget.isPlaying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              widget.episode.isLocked ? Icons.lock_outline_rounded : Icons.play_arrow_rounded,
                              color: widget.episode.isLocked ? Colors.white30 : AppColors.primary,
                              size: 20,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Episode Cover Image
                  if (widget.episode.poster.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 48,
                        child: CachedNetworkImage(
                          imageUrl: widget.episode.poster,
                          httpHeaders: ApiClient().getStalkerHeaders(),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.movie_outlined, color: Colors.white24, size: 16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Details (Name, Plot)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EP ${widget.episode.episodeNumber}: ${widget.episode.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.episode.description.isNotEmpty && widget.episode.description != 'null') ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.episode.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Duration badge
                  if (widget.episode.duration.isNotEmpty)
                    Text(
                      '${widget.episode.duration} min',
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
