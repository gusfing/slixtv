import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Category;
import '../domain/models.dart' show VodItem;
import '../../search/presentation/search_screen.dart';

class MoviesCategoryGridScreen extends ConsumerStatefulWidget {
  final Category category;
  final void Function(VodItem movie)? onMovieTap;

  const MoviesCategoryGridScreen({
    super.key,
    required this.category,
    this.onMovieTap,
  });

  @override
  ConsumerState<MoviesCategoryGridScreen> createState() => _MoviesCategoryGridScreenState();
}

class _MoviesCategoryGridScreenState extends ConsumerState<MoviesCategoryGridScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<VodItem> _movies = [];
  int _currentPage = 1;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  
  VodItem? _focusedMovie;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchMovies();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _fetchMovies(isLoadMore: true);
      }
    }
  }

  Future<void> _fetchMovies({bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() => _isLoadingMore = true);
    }

    try {
      final authState = ref.read(authProvider);
      final List<VodItem> newMovies;
      if (authState.authType == 'xtream') {
        newMovies = await ref.read(xtreamApiProvider).getVodStreams(
          categoryId: widget.category.id,
          page: _currentPage,
        );
      } else {
        newMovies = await ref.read(moviesServiceProvider).getOrderedList(
          categoryId: widget.category.id,
          page: _currentPage,
        );
      }

      if (mounted) {
        setState(() {
          if (!isLoadMore) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
          _movies.addAll(newMovies);
          if (newMovies.length < 14) {
            _hasMore = false;
          } else {
            _currentPage++;
          }
          if (_focusedMovie == null && _movies.isNotEmpty) {
            _focusedMovie = _movies.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Row(
          children: [
            // ─── Left Side: Grid View ───
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Video Club / ${widget.category.title}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.grid_view_rounded, color: Colors.white, size: 24),
                        const SizedBox(width: 16),
                        const Icon(Icons.format_list_bulleted_rounded, color: Colors.white54, size: 24),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: Colors.white, size: 24),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SearchScreen()),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        const Text('A-Z Sort By', style: TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 24),
                      ],
                    ),
                  ),
                  // Grid
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : _movies.isEmpty
                            ? const Center(child: Text('No movies found', style: TextStyle(color: Colors.white54)))
                            : GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 24,
                                  childAspectRatio: 0.65, // Taller posters
                                ),
                                itemCount: _movies.length + (_isLoadingMore ? 4 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _movies.length) {
                                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                                  }
                                  final movie = _movies[index];
                                  final isFocused = _focusedMovie?.id == movie.id;

                                  return _GridMovieCard(
                                    movie: movie,
                                    isFocused: isFocused,
                                    onFocus: () => setState(() => _focusedMovie = movie),
                                    onTap: () => widget.onMovieTap?.call(movie),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            // ─── Right Side: Detail Panel ───
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.only(top: 24, left: 16, right: 24, bottom: 0),
                color: Colors.transparent,
                child: _focusedMovie == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 72), // offset to align with grid start
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Poster
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _focusedMovie!.poster.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: _focusedMovie!.poster,
                                            httpHeaders: ApiClient().getStalkerHeaders(),
                                            width: double.infinity,
                                            height: 280, // Fixed height for responsive poster
                                            fit: BoxFit.cover,
                                            alignment: Alignment.topCenter,
                                            placeholder: (_, __) => Container(height: 280, width: double.infinity, color: const Color(0xFF2A2A2A)),
                                            errorWidget: (_, __, ___) => Container(height: 280, width: double.infinity, color: const Color(0xFF2A2A2A)),
                                          )
                                        : Container(height: 280, width: double.infinity, color: const Color(0xFF2A2A2A)),
                                  ),
                                  const SizedBox(height: 24),
                                  // Title
                                  Text(
                                    _focusedMovie!.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  // Meta info
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (_focusedMovie!.year.isNotEmpty)
                                        Text(_focusedMovie!.year, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                      if (_focusedMovie!.rating.isNotEmpty && _focusedMovie!.rating != '0' && _focusedMovie!.rating != '0.0')
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                            const SizedBox(width: 4),
                                            Text(_focusedMovie!.rating, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      if (_focusedMovie!.duration.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.schedule_rounded, color: Colors.white54, size: 16),
                                            const SizedBox(width: 4),
                                            Text(_focusedMovie!.duration, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Description
                                  if (_focusedMovie!.description.isNotEmpty) ...[
                                    Text(
                                      _focusedMovie!.description,
                                      style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                  // Details
                                  _DetailRow('Genre', _focusedMovie!.genre.isNotEmpty ? _focusedMovie!.genre : widget.category.title),
                                  if (_focusedMovie!.director.isNotEmpty) _DetailRow('Director', _focusedMovie!.director),
                                  if (_focusedMovie!.actors.isNotEmpty) _DetailRow('Cast', _focusedMovie!.actors),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}


class _GridMovieCard extends StatefulWidget {
  final VodItem movie;
  final bool isFocused;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  const _GridMovieCard({
    required this.movie,
    required this.isFocused,
    required this.onFocus,
    required this.onTap,
  });

  @override
  State<_GridMovieCard> createState() => _GridMovieCardState();
}

class _GridMovieCardState extends State<_GridMovieCard> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (focused) widget.onFocus();
      },
      child: MouseRegion(
        onEnter: (_) => widget.onFocus(),
        child: GestureDetector(
          onTap: () {
            if (widget.isFocused) {
              widget.onTap();
            } else {
              widget.onFocus();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isFocused ? const Color(0xFFE50914) : Colors.transparent,
                width: 3,
              ),
            ),
            child: Stack(
              children: [
                // Poster Image
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: widget.movie.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.movie.poster,
                            httpHeaders: ApiClient().getStalkerHeaders(),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF2A2A2A)),
                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF2A2A2A)),
                          )
                        : Container(color: const Color(0xFF2A2A2A)),
                  ),
                ),
                // Gradient for bottom text readability
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 80,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(9),
                        bottomRight: Radius.circular(9),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.9),
                          Colors.black.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top Badges (HD & Heart)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(color: Colors.white, width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HD',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.favorite_border_rounded, color: Colors.white, size: 22),
                    ],
                  ),
                ),
                // Title at the bottom
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    widget.movie.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Hover/Focus Overlay (Play button)
                if (widget.isFocused)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
