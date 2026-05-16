import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import 'home_screen.dart';
import '../../live_tv/presentation/live_tv_screen.dart';
import '../../movies/presentation/movies_screen.dart';
import '../../movies/presentation/movie_detail_screen.dart';
import '../../series/presentation/series_screen.dart';
import '../../search/presentation/search_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../player/presentation/player_screen.dart';
import '../../auth/data/models.dart' show Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;
import '../../auth/domain/providers.dart';

/// Main navigation shell — 6 tabs: Home, Live TV, Movies, Series, Search, Profile.
class AppShell extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;
  const AppShell({super.key, this.onLogout});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  // ─── Navigation: Live TV ──────────────────────────────────

  void _onChannelTap(Channel channel) {
    _navigateToLivePlayer(channel);
  }

  Future<void> _navigateToLivePlayer(Channel channel) async {
    _showLoadingDialog();
    try {
      final api = ref.read(stalkerApiProvider);
      final streamUrl = await api.createLink(channel.cmd, 'itv');
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      _openPlayer(streamUrl, channel.name, contentId: 'ch_${channel.id}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError('Failed to load channel: ${_cleanError(e)}');
    }
  }

  // ─── Navigation: Movies ───────────────────────────────────

  void _onMovieTap(VodItem movie) {
    // Open detail screen — play button there calls createLink
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(movie: movie),
    ));
  }

  // ─── Navigation: Series ───────────────────────────────────

  void _onSeriesTap(SeriesItem series) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(series: series),
    ));
  }

  // ─── Helpers ─────────────────────────────────────────────

  void _openPlayer(String streamUrl, String title,
      {String? subtitle, String? contentId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: streamUrl,
        title: title,
        subtitle: subtitle,
        contentId: contentId,
      ),
    ));
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanError(dynamic e) =>
      e.toString().replaceAll('Exception: ', '').replaceAll('Exception:', '');

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
          onChannelTap: _onChannelTap,
          onMovieTap: _onMovieTap,
          onSeriesTap: _onSeriesTap),
      LiveTvScreen(onChannelTap: _onChannelTap),
      MoviesScreen(onMovieTap: _onMovieTap),
      SeriesScreen(onSeriesTap: _onSeriesTap),
      SearchScreen(
          onChannelTap: _onChannelTap,
          onMovieTap: _onMovieTap,
          onSeriesTap: _onSeriesTap),
      ProfileScreen(onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundLight,
          border:
              Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: AppDimensions.bottomNavHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home_rounded, 'Home', 0),
                _navItem(Icons.live_tv_rounded, 'Live TV', 1),
                _navItem(Icons.movie_rounded, 'Movies', 2),
                _navItem(Icons.tv_rounded, 'Series', 3),
                _navItem(Icons.search_rounded, 'Search', 4),
                _navItem(Icons.person_rounded, 'Profile', 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
                size: AppDimensions.bottomNavIconSize,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
