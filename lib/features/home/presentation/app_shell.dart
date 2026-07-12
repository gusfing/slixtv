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
import '../../favorites/presentation/favorites_screen.dart';
import '../../radio/presentation/radio_screen.dart';
import '../../epg/presentation/tv_guide_screen.dart';
import '../../player/presentation/player_screen.dart';
import '../../auth/data/models.dart' show Channel, Category;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;
import '../../auth/domain/providers.dart';
import '../../../core/widgets/parental_pin_dialog.dart';

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

  void _onChannelTap(Channel channel) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(tvCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == channel.categoryId,
        orElse: () => Category(id: channel.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: channel.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
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

  void _onMovieTap(VodItem movie) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(vodCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == movie.categoryId,
        orElse: () => Category(id: movie.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: movie.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(movie: movie),
    ));
  }

  // ─── Navigation: Series ───────────────────────────────────

  void _onSeriesTap(SeriesItem series) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(seriesCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == series.categoryId,
        orElse: () => Category(id: series.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: series.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
    if (!mounted) return;
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
          onSeriesTap: _onSeriesTap,
          onNavigateToTab: (index) => setState(() => _currentIndex = index),
          onLogout: widget.onLogout), // 0
      LiveTvScreen(onChannelTap: _onChannelTap), // 1
      MoviesScreen(onMovieTap: _onMovieTap), // 2
      SeriesScreen(onSeriesTap: _onSeriesTap), // 3
      const FavoritesScreen(), // 4
      const TvGuideScreen(), // 5
      const RadioScreen(), // 6
      ProfileScreen(onLogout: widget.onLogout), // 7
      const Center(child: Text('Settings (Coming Soon)', style: TextStyle(color: Colors.white))), // 8
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _buildSidebarNav(),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: screens),
          ),
        ],
      ),
    );
  }


  Widget _buildSidebarNav() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0F),
        border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            // Sidebar header (Matching the style)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Row(
                children: [
                  const Icon(Icons.apps_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 12),
                  const Text(
                    'SFLIXTV',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _navItem(Icons.home_outlined, 'HOME', 0),
                    _navItem(Icons.tv_outlined, 'LIVE TV', 1),
                    _navItem(Icons.movie_outlined, 'VIDEO CLUB', 2),
                    _navItem(Icons.video_library_outlined, 'SERIES', 3),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    _navItem(Icons.favorite_border_rounded, 'FAVORITES', 4),
                    _navItem(Icons.view_list_rounded, 'TV GUIDE', 5),
                    _navItem(Icons.radio_rounded, 'RADIO', 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    _navItem(Icons.person_outline_rounded, 'ACCOUNT', 7),
                    _navItem(Icons.settings_outlined, 'SETTINGS', 8),
                  ],
                ),
              ),
            ),
            
            // Logout at bottom
            if (widget.onLogout != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _navItem(Icons.logout_rounded, 'LOGOUT', -1, onTap: widget.onLogout),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index, {VoidCallback? onTap}) {
    final isSelected = _currentIndex == index;
    return Focus(
      onFocusChange: (focused) {}, // Managed by internal focus
      child: GestureDetector(
        onTap: onTap ?? () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
