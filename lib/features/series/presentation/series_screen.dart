import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/common_widgets.dart';
import '../domain/models.dart' show SeriesItem, Episode;
import '../../auth/domain/providers.dart';
import '../../player/presentation/player_screen.dart';
import '../../../core/config/app_config.dart';

// ─── Series List Screen ──────────────────────────────────────

class SeriesScreen extends ConsumerStatefulWidget {
  final void Function(SeriesItem series)? onSeriesTap;

  const SeriesScreen({super.key, this.onSeriesTap});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(seriesCategoriesProvider);
    final series = ref.watch(seriesProvider(_selectedCategory));
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: AppColors.background,
            title: const Text('Series'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: categories.when(
                loading: () => const SizedBox(height: 50),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Could not load categories: $e',
                      style: TextStyle(color: AppColors.error, fontSize: 12)),
                ),
                data: (cats) => SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _selectedCategory == null,
                          onSelected: (_) => setState(() => _selectedCategory = null),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _selectedCategory == null
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      ...cats.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(cat.title),
                              selected: _selectedCategory == cat.id,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = cat.id),
                              selectedColor: AppColors.primary,
                              labelStyle: TextStyle(
                                color: _selectedCategory == cat.id
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        body: series.when(
          loading: () => const LoadingIndicator(message: 'Loading series...'),
          error: (e, st) => ErrorDisplay(
            message: 'Failed to load series: ${e.toString().replaceAll('Exception:', '').trim()}',
            onRetry: () => ref.invalidate(seriesProvider(_selectedCategory)),
          ),
          data: (seriesList) {
            if (seriesList.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_off, color: AppColors.textTertiary, size: 48),
                    SizedBox(height: 12),
                    Text('No series available',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Try a different category',
                        style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                  ],
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(AppDimensions.md),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.55,
                crossAxisSpacing: AppDimensions.sm,
                mainAxisSpacing: AppDimensions.sm,
              ),
              itemCount: seriesList.length,
              itemBuilder: (context, index) {
                final s = seriesList[index];
                final isFav = favorites['series']?.contains(s.id) ?? false;
                return PosterCard(
                  title: s.name,
                  imageUrl: s.poster,
                  subtitle: s.year.isNotEmpty ? s.year : null,
                  isFavorite: isFav,
                  onTap: () => widget.onSeriesTap?.call(s),
                  onFavoriteTap: () {
                    ref.read(favoritesProvider.notifier).toggleFavorite('series', s.id);
                  },
                  width: double.infinity,
                  height: 170,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─── Series Detail Screen ─────────────────────────────────────

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final SeriesItem series;

  const SeriesDetailScreen({super.key, required this.series});

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int _selectedSeasonIndex = 0;
  String? _playingEpisodeId;

  Future<void> _playEpisode(Episode ep) async {
    setState(() => _playingEpisodeId = ep.id);

    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      final streamUrl = await stalkerApi.createLink(
        ep.cmd,
        AppConfig.typeSeries,
        seriesId: widget.series.id,
      );

      if (!mounted) return;
      setState(() => _playingEpisodeId = null);

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: widget.series.name,
          subtitle: ep.name,
          contentId: 'ep_${ep.id}',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingEpisodeId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Playback failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(seriesInfoProvider(widget.series.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Hero poster
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  widget.series.poster.isNotEmpty
                      ? Image.network(
                          widget.series.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterFallback(),
                        )
                      : _posterFallback(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.4, 1.0],
                        colors: [Colors.transparent, AppColors.background],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(AppDimensions.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Title
                Text(
                  widget.series.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),

                // Metadata
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (widget.series.year.isNotEmpty) _metaBadge(widget.series.year),
                    if (widget.series.rating.isNotEmpty &&
                        widget.series.rating != 'null')
                      _metaBadge('⭐ ${widget.series.rating}'),
                    if (widget.series.genre.isNotEmpty &&
                        widget.series.genre != 'null')
                      _metaBadge(widget.series.genre),
                    if (widget.series.seriesCount.isNotEmpty &&
                        widget.series.seriesCount != 'null')
                      _metaBadge('${widget.series.seriesCount} episodes'),
                  ],
                ),

                const SizedBox(height: 16),

                // Description
                if (widget.series.description.isNotEmpty &&
                    widget.series.description != 'null') ...[
                  Text(
                    widget.series.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                ],

                // Seasons and episodes
                seasonsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 12),
                          Text('Loading episodes...',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, color: AppColors.error, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Could not load episodes',
                          style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.toString().replaceAll('Exception:', '').trim(),
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(seriesInfoProvider(widget.series.id)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (seasons) {
                    if (seasons.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No episodes found for this series',
                            style: TextStyle(color: AppColors.textTertiary),
                          ),
                        ),
                      );
                    }

                    final currentSeason = seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Season selector
                        if (seasons.length > 1) ...[
                          Text(
                            'Seasons',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: seasons.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final isSelected = i == _selectedSeasonIndex;
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedSeasonIndex = i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      seasons[i].name,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Episode list
                        Text(
                          'Episodes (${currentSeason.episodes.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),

                        if (currentSeason.episodes.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('No episodes in this season',
                                  style: TextStyle(color: AppColors.textTertiary)),
                            ),
                          )
                        else
                          ...currentSeason.episodes.map((ep) => _EpisodeCard(
                                episode: ep,
                                isLoading: _playingEpisodeId == ep.id,
                                onTap: ep.cmd.isEmpty ? null : () => _playEpisode(ep),
                              )),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFallback() {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(Icons.tv, color: AppColors.textTertiary, size: 64),
      ),
    );
  }

  Widget _metaBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

// ─── Episode Card ─────────────────────────────────────────────

class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final bool isLoading;
  final VoidCallback? onTap;

  const _EpisodeCard({
    required this.episode,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Episode number
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: onTap != null
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        onTap != null ? Icons.play_arrow_rounded : Icons.lock_outline,
                        color: onTap != null
                            ? AppColors.primary
                            : AppColors.textTertiary,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Name and description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ep ${episode.episodeNumber}: ${episode.name}',
                    style: TextStyle(
                      color: onTap != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (episode.description.isNotEmpty &&
                      episode.description != 'null') ...[
                    const SizedBox(height: 2),
                    Text(
                      episode.description,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Duration
            if (episode.duration.isNotEmpty && episode.duration != 'null')
              Text(
                '${episode.duration}m',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
