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
          onLogout: widget.onLogout),
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
      width: 78,
      decoration: const BoxDecoration(
        color: AppColors.backgroundLight,
        border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _navItem(Icons.home_rounded, 'Home', 0),
                  const SizedBox(height: 8),
                  _navItem(Icons.live_tv_rounded, 'Live TV', 1),
                  const SizedBox(height: 8),
                  _navItem(Icons.movie_rounded, 'Movies', 2),
                  const SizedBox(height: 8),
                  _navItem(Icons.tv_rounded, 'Series', 3),
                  const SizedBox(height: 8),
                  _navItem(Icons.search_rounded, 'Search', 4),
                  const SizedBox(height: 8),
                  _navItem(Icons.person_rounded, 'Profile', 5),
                ],
              ),
            ),
          ],
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
        width: 72,
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
                size: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
