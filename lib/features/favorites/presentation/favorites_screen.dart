import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;
import '../../movies/presentation/movie_detail_screen.dart';
import '../../series/presentation/series_screen.dart';
import '../../player/presentation/player_screen.dart';
import '../../../core/widgets/parental_pin_dialog.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0F),
        title: const Text('Favorites', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.tv), text: 'Live TV'),
            Tab(icon: Icon(Icons.movie), text: 'Movies'),
            Tab(icon: Icon(Icons.video_library), text: 'Series'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _FavoritesTab(type: 'channels'),
          _FavoritesTab(type: 'movies'),
          _FavoritesTab(type: 'series'),
        ],
      ),
    );
  }
}

class _FavoritesTab extends ConsumerStatefulWidget {
  final String type;
  const _FavoritesTab({required this.type});

  @override
  ConsumerState<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<_FavoritesTab> {
  bool _isLoading = true;
  List<dynamic> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFavorites();
  }

  Future<void> _fetchFavorites() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authState = ref.read(authProvider);
      final isXtream = authState.authType == 'xtream';
      List<dynamic> newItems = [];

      if (widget.type == 'channels') {
        if (isXtream) {
          newItems = await ref.read(xtreamApiProvider).getLiveStreams();
        } else {
          newItems = await ref.read(stalkerApiProvider).getChannels();
        }
      } else if (widget.type == 'movies') {
        if (isXtream) {
          newItems = await ref.read(xtreamApiProvider).getVodStreams();
        } else {
          newItems = await ref.read(moviesServiceProvider).getOrderedList();
        }
      } else if (widget.type == 'series') {
        if (isXtream) {
          newItems = await ref.read(xtreamApiProvider).getSeries();
        } else {
          newItems = await ref.read(seriesServiceProvider).getOrderedList();
        }
      }

      // Filter by local favorites
      final favIds = ref.read(favoritesProvider)[widget.type] ?? {};
      newItems = newItems.where((item) {
        if (item is Channel) return favIds.contains(item.id);
        if (item is VodItem) return favIds.contains(item.id);
        if (item is SeriesItem) return favIds.contains(item.id);
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _items = newItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load favorites: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchFavorites,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No ${widget.type} in favorites.',
          style: const TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final crossAxisCount = isMobile ? (widget.type == 'channels' ? 3 : 3) : 5;
        final childAspectRatio = widget.type == 'channels' ? 0.9 : 0.7;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            if (widget.type == 'channels') {
              return _buildChannelItem(item as Channel);
            } else if (widget.type == 'movies') {
              return _buildMovieItem(item as VodItem);
            } else {
              return _buildSeriesItem(item as SeriesItem);
            }
          },
        );
      },
    );
  }

  Widget _buildChannelItem(Channel channel) {
    return GestureDetector(
      onTap: () async {
        final lockState = ref.read(parentalLockProvider);
        if (lockState.isLocked && !lockState.isSessionUnlocked) {
          final authenticated = await ParentalPinDialog.show(context);
          if (!authenticated) return;
        }
        _playChannel(channel);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (channel.logo.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: CachedNetworkImage(
                    imageUrl: channel.logo,
                    httpHeaders: ApiClient().getStalkerHeaders(),
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white24, size: 40),
                  ),
                ),
              )
            else
              const Expanded(child: Icon(Icons.tv, color: Colors.white24, size: 40)),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF15151A),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Text(
                channel.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieItem(VodItem movie) {
    return GestureDetector(
      onTap: () async {
        final lockState = ref.read(parentalLockProvider);
        if (lockState.isLocked && !lockState.isSessionUnlocked) {
          final authenticated = await ParentalPinDialog.show(context);
          if (!authenticated) return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: movie.poster,
              httpHeaders: ApiClient().getStalkerHeaders(),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: AppColors.surface, child: const Icon(Icons.movie, color: Colors.white24, size: 40)),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Text(
                  movie.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesItem(SeriesItem series) {
    return GestureDetector(
      onTap: () async {
        final lockState = ref.read(parentalLockProvider);
        if (lockState.isLocked && !lockState.isSessionUnlocked) {
          final authenticated = await ParentalPinDialog.show(context);
          if (!authenticated) return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: series.poster,
              httpHeaders: ApiClient().getStalkerHeaders(),
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: AppColors.surface, child: const Icon(Icons.video_library, color: Colors.white24, size: 40)),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Text(
                  series.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playChannel(Channel channel) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      final streamUrl = await stalkerApi.createLink(channel.cmd, 'itv');
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: channel.name,
          contentId: 'ch_${channel.id}',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load channel: ${e.toString()}')));
    }
  }
}
