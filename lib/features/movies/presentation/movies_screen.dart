import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../domain/models.dart' show VodItem;

/// Movies screen with categories, posters, and filters.
class MoviesScreen extends ConsumerStatefulWidget {
  final void Function(VodItem movie)? onMovieTap;

  const MoviesScreen({super.key, this.onMovieTap});

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vodCategoriesProvider);
    final movies = ref.watch(moviesProvider(_selectedCategory));
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: AppColors.background,
            title: const Text('Movies'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: categories.when(
                loading: () => const SizedBox(height: 50),
                error: (_, __) => const SizedBox(height: 50),
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
                            color: _selectedCategory == null ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      ...cats.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(cat.title),
                              selected: _selectedCategory == cat.id,
                              onSelected: (_) => setState(() => _selectedCategory = cat.id),
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
        body: movies.when(
          loading: () => const LoadingIndicator(message: 'Loading movies...'),
          error: (e, _) => ErrorDisplay(
            message: 'Failed to load movies',
            onRetry: () => ref.invalidate(moviesProvider(_selectedCategory)),
          ),
          data: (movieList) {
            if (movieList.isEmpty) {
              return const Center(
                child: Text('No movies available', style: TextStyle(color: AppColors.textTertiary)),
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
              itemCount: movieList.length,
              itemBuilder: (context, index) {
                final movie = movieList[index];
                final isFav = favorites['movies']?.contains(movie.id) ?? false;
                return PosterCard(
                  title: movie.name,
                  imageUrl: movie.poster,
                  subtitle: movie.year.isNotEmpty ? '${movie.year} • ${movie.rating}' : null,
                  isFavorite: isFav,
                  onTap: () => widget.onMovieTap?.call(movie),
                  onFavoriteTap: () {
                    ref.read(favoritesProvider.notifier).toggleFavorite('movies', movie.id);
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
