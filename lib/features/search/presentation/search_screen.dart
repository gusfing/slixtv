import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;

class SearchScreen extends ConsumerStatefulWidget {
  final void Function(Channel)? onChannelTap;
  final void Function(VodItem)? onMovieTap;
  final void Function(SeriesItem)? onSeriesTap;

  const SearchScreen({
    super.key,
    this.onChannelTap,
    this.onMovieTap,
    this.onSeriesTap,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(AppConfig.searchDebounce, () {
      ref.read(searchQueryProvider.notifier).state = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final allMovies = ref.watch(moviesProvider(null));

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search movies, series or channels...',
              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: AppColors.textTertiary, size: 20),
                      onPressed: () {
                        _ctrl.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ),
      body: query.trim().length < 2
          ? _buildTrendingSection(allMovies)
          : results.when(
              loading: () => const LoadingIndicator(message: 'Searching...'),
              error: (e, _) => ErrorDisplay(message: 'Search failed'),
              data: (r) {
                final ch = r['channels'] ?? [];
                final mv = r['movies'] ?? [];
                final sr = r['series'] ?? [];

                if (ch.isEmpty && mv.isEmpty && sr.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sentiment_dissatisfied_rounded, size: 60, color: AppColors.textHint.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text(AppStrings.noResults, style: const TextStyle(color: AppColors.textTertiary)),
                      ],
                    ),
                  );
                }

                return CustomScrollView(
                  slivers: [
                    if (ch.isNotEmpty) ...[
                      const _SliverSectionTitle(title: 'Channels'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isLandscape ? 6 : 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.7,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final c = ch[index] as Channel;
                              return _GridItem(
                                title: c.name,
                                imageUrl: c.logo,
                                onTap: () => widget.onChannelTap?.call(c),
                              );
                            },
                            childCount: ch.length,
                          ),
                        ),
                      ),
                    ],
                    if (mv.isNotEmpty) ...[
                      const _SliverSectionTitle(title: 'Movies'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isLandscape ? 6 : 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.7,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final m = mv[index] as VodItem;
                              return _GridItem(
                                title: m.name,
                                imageUrl: m.poster,
                                onTap: () => widget.onMovieTap?.call(m),
                              );
                            },
                            childCount: mv.length,
                          ),
                        ),
                      ),
                    ],
                    if (sr.isNotEmpty) ...[
                      const _SliverSectionTitle(title: 'Series'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isLandscape ? 6 : 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.7,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final s = sr[index] as SeriesItem;
                              return _GridItem(
                                title: s.name,
                                imageUrl: s.poster,
                                onTap: () => widget.onSeriesTap?.call(s),
                              );
                            },
                            childCount: sr.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildTrendingSection(AsyncValue<List<VodItem>> movies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Top Searches',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: movies.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Could not load trending content')),
            data: (items) {
              final trending = items.take(10).toList();
              return ListView.builder(
                itemCount: trending.length,
                itemBuilder: (context, index) {
                  final m = trending[index];
                  return _TrendingTile(
                    title: m.name,
                    imageUrl: m.poster,
                    onTap: () => widget.onMovieTap?.call(m),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SliverSectionTitle extends StatelessWidget {
  final String title;
  const _SliverSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;

  const _GridItem({
    required this.title,
    this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null && imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      httpHeaders: ApiClient().getStalkerHeaders(),
                      placeholder: (context, url) => Container(color: AppColors.surface),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surface,
                        child: const Icon(Icons.movie, color: Colors.white24, size: 30),
                      ),
                    )
                  else
                    Container(
                      color: AppColors.surface,
                      child: const Icon(Icons.movie, color: Colors.white24, size: 30),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TrendingTile extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;

  const _TrendingTile({
    required this.title,
    this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        margin: const EdgeInsets.only(bottom: 2),
        color: AppColors.backgroundLight,
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 64,
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      httpHeaders: ApiClient().getStalkerHeaders(),
                      placeholder: (context, url) => Container(color: AppColors.surface),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surface,
                        child: const Icon(Icons.movie, color: Colors.white12),
                      ),
                    )
                  : Container(color: AppColors.surface),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
