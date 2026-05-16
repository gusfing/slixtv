import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;

/// Netflix-style Home screen with hero banner and horizontal rows.
class HomeScreen extends ConsumerStatefulWidget {
  final void Function(Channel channel)? onChannelTap;
  final void Function(VodItem movie)? onMovieTap;
  final void Function(SeriesItem series)? onSeriesTap;

  const HomeScreen({
    super.key,
    this.onChannelTap,
    this.onMovieTap,
    this.onSeriesTap,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(allChannelsProvider);
    final movies = ref.watch(moviesProvider(null));
    final series = ref.watch(seriesProvider(null));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          ref.invalidate(allChannelsProvider);
          ref.invalidate(moviesProvider(null));
          ref.invalidate(seriesProvider(null));
        },
        child: CustomScrollView(
          slivers: [
            // Hero Banner
            SliverToBoxAdapter(
              child: _buildHeroBanner(channels),
            ),

            // Continue Watching (placeholder for now — populated from watch history)
            SliverToBoxAdapter(
              child: FadeInUp(
                delay: const Duration(milliseconds: 100),
                child: _buildSection(
                  title: AppStrings.continueWatching,
                  child: _buildChannelRow(channels),
                ),
              ),
            ),

            // Live TV
            SliverToBoxAdapter(
              child: FadeInUp(
                delay: const Duration(milliseconds: 200),
                child: _buildSection(
                  title: AppStrings.liveTV,
                  child: _buildChannelRow(channels),
                ),
              ),
            ),

            // Trending Movies
            SliverToBoxAdapter(
              child: FadeInUp(
                delay: const Duration(milliseconds: 300),
                child: _buildSection(
                  title: AppStrings.trendingMovies,
                  child: _buildMovieRow(movies),
                ),
              ),
            ),

            // Series
            SliverToBoxAdapter(
              child: FadeInUp(
                delay: const Duration(milliseconds: 400),
                child: _buildSection(
                  title: AppStrings.series,
                  child: _buildSeriesRow(series),
                ),
              ),
            ),

            // Recently Added
            SliverToBoxAdapter(
              child: FadeInUp(
                delay: const Duration(milliseconds: 500),
                child: _buildSection(
                  title: AppStrings.recentlyAdded,
                  child: _buildMovieRow(movies),
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner(AsyncValue<List<Channel>> channelsAsync) {
    return channelsAsync.when(
      loading: () => const ShimmerHero(),
      error: (e, _) => const SizedBox(height: AppDimensions.heroMobileHeight),
      data: (channels) {
        if (channels.isEmpty) return const SizedBox(height: 200);
        final featured = channels.take(1).first;
        return GestureDetector(
          onTap: () => widget.onChannelTap?.call(featured),
          child: SizedBox(
            height: AppDimensions.heroMobileHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.3),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
                // Channel logo if available
                if (featured.logo.isNotEmpty)
                  Positioned(
                    top: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Image.network(
                        featured.logo,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      ),
                    ),
                  ),
                // Content overlay
                Positioned(
                  bottom: 40,
                  left: AppDimensions.md,
                  right: AppDimensions.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        featured.name,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (featured.currentProgram != null)
                        Text(
                          'Now: ${featured.currentProgram!.name}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.success,
                              ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => widget.onChannelTap?.call(featured),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Watch Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.info_outline, size: 20),
                            label: const Text('Info'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.textTertiary),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        child,
      ],
    );
  }

  Widget _buildChannelRow(AsyncValue<List<Channel>> channelsAsync) {
    return channelsAsync.when(
      loading: () => const ShimmerRow(
        itemWidth: AppDimensions.channelCardWidth,
        itemHeight: AppDimensions.channelCardHeight,
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
        child: Text('Error loading channels', style: TextStyle(color: AppColors.error)),
      ),
      data: (channels) {
        if (channels.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimensions.md),
            child: Text('No channels available', style: TextStyle(color: AppColors.textTertiary)),
          );
        }
        return SizedBox(
          height: AppDimensions.channelCardHeight + 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
            itemCount: channels.length.clamp(0, 20),
            separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.sm),
            itemBuilder: (context, index) {
              final channel = channels[index];
              return GestureDetector(
                onTap: () => widget.onChannelTap?.call(channel),
                child: Container(
                  width: AppDimensions.channelCardWidth,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (channel.logo.isNotEmpty)
                        Image.network(
                          channel.logo,
                          height: 36,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.tv, color: AppColors.textTertiary, size: 28),
                        )
                      else
                        Icon(Icons.tv, color: AppColors.textTertiary, size: 28),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          channel.name,
                          style: Theme.of(context).textTheme.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMovieRow(AsyncValue<List<VodItem>> moviesAsync) {
    return moviesAsync.when(
      loading: () => const ShimmerRow(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
        child: Text('Error loading movies', style: TextStyle(color: AppColors.error)),
      ),
      data: (movies) {
        if (movies.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimensions.md),
            child: Text('No movies available', style: TextStyle(color: AppColors.textTertiary)),
          );
        }
        return SizedBox(
          height: AppDimensions.posterHeight + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
            itemCount: movies.length.clamp(0, 20),
            separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.sm),
            itemBuilder: (context, index) {
              final movie = movies[index];
              return PosterCard(
                title: movie.name,
                imageUrl: movie.poster,
                subtitle: movie.year.isNotEmpty ? movie.year : null,
                onTap: () => widget.onMovieTap?.call(movie),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSeriesRow(AsyncValue<List<SeriesItem>> seriesAsync) {
    return seriesAsync.when(
      loading: () => const ShimmerRow(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
        child: Text('Error loading series', style: TextStyle(color: AppColors.error)),
      ),
      data: (seriesList) {
        if (seriesList.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimensions.md),
            child: Text('No series available', style: TextStyle(color: AppColors.textTertiary)),
          );
        }
        return SizedBox(
          height: AppDimensions.posterHeight + 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
            itemCount: seriesList.length.clamp(0, 20),
            separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.sm),
            itemBuilder: (context, index) {
              final s = seriesList[index];
              return PosterCard(
                title: s.name,
                imageUrl: s.poster,
                subtitle: s.year.isNotEmpty ? s.year : null,
                onTap: () => widget.onSeriesTap?.call(s),
              );
            },
          ),
        );
      },
    );
  }
}
