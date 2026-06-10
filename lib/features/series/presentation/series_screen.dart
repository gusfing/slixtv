import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../../core/widgets/common_widgets.dart';

import '../../auth/data/models.dart' show Category, SubtitleInfo;
import '../../auth/domain/providers.dart';
import '../../player/presentation/player_screen.dart';
import '../../../core/widgets/parental_pin_dialog.dart';
import '../domain/models.dart';


// ─── Series List Screen (matches MoviesScreen layout) ────────

class SeriesScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  final void Function(SeriesItem series)? onSeriesTap;

  const SeriesScreen({super.key, this.categoryId, this.onSeriesTap});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedCategory;
  String _selectedCategoryName = 'All';
  final ScrollController _scrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final List<SeriesItem> _series = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  String _searchQuery = "";
  final _searchController = TextEditingController();
  final Map<String, bool> _expandedGroups = {};
  bool _pendingAdultAuth = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.categoryId;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSeries(isRefresh: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sidebarScrollController.dispose();
    _searchController.dispose();
    ref.read(parentalLockProvider.notifier).lockSession();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _fetchSeries(isRefresh: false);
      }
    }
  }

  Future<void> _selectCategory(String? categoryId, String categoryName) async {
    if (_selectedCategory == categoryId) return;

    final isAdult = isAdultContent(categoryName: categoryName);
    final lockState = ref.read(parentalLockProvider);
    final needsAuth = isAdult && lockState.isLocked && !lockState.isSessionUnlocked;

    setState(() {
      _selectedCategory = categoryId;
      _selectedCategoryName = categoryName;
      _searchQuery = '';
      _searchController.clear();
      _series.clear();
      _pendingAdultAuth = needsAuth;
    });

    if (needsAuth) return;

    _fetchSeries(isRefresh: true);
  }

  Future<void> _unlockAdultCategory() async {
    print('DEBUG: _unlockAdultCategory (Series) called');
    try {
      final authenticated = await ParentalPinDialog.show(context);
      print('DEBUG: ParentalPinDialog (Series) returned: $authenticated');
      if (!authenticated) return;
      ref.read(parentalLockProvider.notifier).unlockSession();
      if (mounted) {
        setState(() => _pendingAdultAuth = false);
        _fetchSeries(isRefresh: true);
      }
    } catch (e, stackTrace) {
      print('DEBUG: Exception in _unlockAdultCategory (Series): $e\n$stackTrace');
    }
  }

  Widget _buildAdultLockOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.lock_rounded, color: AppColors.error, size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'Adult Content',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'This category is protected.\nEnter your PIN to view content.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            autofocus: true,
            onPressed: _unlockAdultCategory,
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: const Text('Enter PIN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchSeries({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _series.clear();
        _currentPage = 1;
        _hasMore = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final authState = ref.read(authProvider);
      final List<SeriesItem> newSeries;
      if (authState.authType == 'xtream') {
        newSeries = await ref.read(xtreamApiProvider).getSeries(
          categoryId: _selectedCategory,
          page: _currentPage,
        );
      } else {
        newSeries = await ref.read(seriesServiceProvider).getOrderedList(
          categoryId: _selectedCategory,
          page: _currentPage,
        );
      }

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
          _series.addAll(newSeries);
          if (newSeries.length < 14) {
            _hasMore = false;
          } else {
            _currentPage++;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isRefresh) {
            _isLoading = false;
            _errorMessage = 'Failed to load series: ${e.toString().replaceAll('Exception: ', '')}';
          } else {
            _isLoadingMore = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSeries = _searchQuery.isEmpty
        ? _series
        : _series.where((s) => s.name.toLowerCase().contains(_searchQuery)).toList();
    final categoriesAsync = ref.watch(seriesCategoriesProvider);

    categoriesAsync.whenData((categories) {
      if (_selectedCategory == null && categories.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedCategory == null) {
            final nonAdultCats = categories.where((c) => !isAdultContent(categoryName: c.title)).toList();
            final defaultCat = nonAdultCats.isNotEmpty ? nonAdultCats.first : categories.first;
            _selectCategory(defaultCat.id, defaultCat.title);
          }
        });
      } else if (_selectedCategory != null) {
        final selectedCat = categories.firstWhere(
          (c) => c.id == _selectedCategory,
          orElse: () => Category(id: _selectedCategory!, title: _selectedCategoryName),
        );
        final isAdult = isAdultContent(categoryName: selectedCat.title);
        final lockState = ref.read(parentalLockProvider);
        if (isAdult && lockState.isLocked && !lockState.isSessionUnlocked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_pendingAdultAuth) {
              setState(() {
                _pendingAdultAuth = true;
                _series.clear();
              });
            }
          });
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            // ─── Left Sidebar: Categories ───
            Container(
              width: 180,
              decoration: const BoxDecoration(
                color: Color(0xFF111114),
                border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              child: Column(
                children: [
                  // Sidebar header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.video_library_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        const Text(
                          'Series',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),

                  // Category list
                  Expanded(
                    child: categoriesAsync.when(
                      loading: () => const Center(
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                      error: (err, _) => Center(
                        child: Text('Error', style: TextStyle(color: AppColors.error, fontSize: 11)),
                      ),
                      data: (categories) {
                        final List<CategoryGroup> localGroups = [];
                        final Map<String, List<Category>> tempGroups = {};
                        final List<Category> ungrouped = [];

                        for (final cat in categories) {
                          if (cat.title.contains('|')) {
                            final parts = cat.title.split('|');
                            final prefix = parts[0].trim();
                            if (prefix.isNotEmpty) {
                              tempGroups.putIfAbsent(prefix, () => []).add(cat);
                              continue;
                            }
                          }
                          ungrouped.add(cat);
                        }

                        tempGroups.forEach((prefix, list) {
                          localGroups.add(CategoryGroup(prefix, list));
                        });

                        if (ungrouped.isNotEmpty) {
                          localGroups.add(CategoryGroup('General', ungrouped));
                        }

                        localGroups.sort((a, b) {
                          final aAdult = a.name.toLowerCase() == 'adult' || isAdultContent(categoryName: a.name);
                          final bAdult = b.name.toLowerCase() == 'adult' || isAdultContent(categoryName: b.name);
                          if (aAdult && !bAdult) return 1;
                          if (!aAdult && bAdult) return -1;
                          if (a.name == 'General') return -1;
                          if (b.name == 'General') return 1;
                          return a.name.compareTo(b.name);
                        });

                        for (final group in localGroups) {
                          group.categories.sort((a, b) {
                            final aAdult = isAdultContent(categoryName: a.title);
                            final bAdult = isAdultContent(categoryName: b.title);
                            if (aAdult && !bAdult) return 1;
                            if (!aAdult && bAdult) return -1;
                            return a.title.compareTo(b.title);
                          });
                        }

                        // Expand all groups by default (except adult groups), while preserving user preferences
                        for (final group in localGroups) {
                          final isAdult = group.name.toLowerCase() == 'adult' || isAdultContent(categoryName: group.name);
                          _expandedGroups.putIfAbsent(group.name, () => !isAdult);
                        }

                        // Force expand group containing the selected category
                        if (_selectedCategory != null) {
                          for (final group in localGroups) {
                            if (group.categories.any((c) => c.id == _selectedCategory)) {
                              _expandedGroups[group.name] = true;
                            }
                          }
                        }

                        return SingleChildScrollView(
                          controller: _sidebarScrollController,
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final group in localGroups) ...[
                                _SidebarGroupHeader(
                                  name: group.name,
                                  isExpanded: _expandedGroups[group.name] ?? false,
                                  onTap: () {
                                    setState(() {
                                      _expandedGroups[group.name] = !(_expandedGroups[group.name] ?? false);
                                    });
                                  },
                                ),
                                if (_expandedGroups[group.name] ?? false)
                                  ...group.categories.map((cat) {
                                    String cleanName = cat.title;
                                    if (cleanName.contains('|')) {
                                      final parts = cleanName.split('|');
                                      if (parts.length > 1) {
                                        cleanName = parts.sublist(1).join('|').trim();
                                      }
                                    }

                                    return _SidebarCategoryTile(
                                      name: cleanName,
                                      isSelected: _selectedCategory == cat.id,
                                      onTap: () => _selectCategory(cat.id, cat.title),
                                      indent: true,
                                    );
                                  }),
                                const SizedBox(height: 4),
                              ]
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ─── Right Content: Series Grid ───
            Expanded(
              child: Column(
                children: [
                  // Compact top bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          _selectedCategoryName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${filteredSeries.length}${_hasMore ? '+' : ''})',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        const Spacer(),
                        // Search bar
                        SizedBox(
                          width: 200,
                          height: 32,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),

                  // Series grid
                  Expanded(
                    child: _pendingAdultAuth
                        ? _buildAdultLockOverlay()
                        : _isLoading
                            ? const LoadingIndicator(message: 'Loading series...')
                            : _errorMessage != null
                                ? ErrorDisplay(
                                    message: _errorMessage!,
                                    onRetry: () => _fetchSeries(isRefresh: true),
                                  )
                                : filteredSeries.isEmpty
                                    ? const Center(
                                        child: Text('No series available', style: TextStyle(color: Colors.white30)),
                                      )
                                    : GridView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.all(10),
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 5,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          childAspectRatio: 0.62,
                                        ),
                                        itemCount: filteredSeries.length + (_isLoadingMore ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index >= filteredSeries.length) {
                                            return const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                                              ),
                                            );
                                          }
                                          final s = filteredSeries[index];
                                          return _PosterCard(
                                            title: s.name,
                                            image: s.poster,
                                            onTap: () => widget.onSeriesTap?.call(s),
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

// ─── Sidebar Category Tile ────────────────────────────────
class _SidebarCategoryTile extends StatefulWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;
  final bool indent;

  const _SidebarCategoryTile({
    required this.name,
    required this.isSelected,
    required this.onTap,
    this.indent = false,
  });

  @override
  State<_SidebarCategoryTile> createState() => _SidebarCategoryTileState();
}

class _SidebarCategoryTileState extends State<_SidebarCategoryTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _isFocused;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.only(
            left: widget.indent ? 28 : 14,
            right: 14,
            top: 10,
            bottom: 10,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? AppColors.primary : Colors.white60,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarGroupHeader extends StatefulWidget {
  final String name;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarGroupHeader({
    required this.name,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_SidebarGroupHeader> createState() => _SidebarGroupHeaderState();
}

class _SidebarGroupHeaderState extends State<_SidebarGroupHeader> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final active = _isFocused;
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? AppColors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
                  color: active ? AppColors.primary : Colors.white30,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  widget.isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  color: active ? AppColors.primary : Colors.white30,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryGroup {
  final String name;
  final List<Category> categories;
  CategoryGroup(this.name, this.categories);
}

// ─── Poster Card ─────────────────────────────────────────
class _PosterCard extends StatefulWidget {
  final String title;
  final String image;
  final VoidCallback onTap;

  const _PosterCard({
    required this.title,
    required this.image,
    required this.onTap,
  });

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
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
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Large poster area
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(7),
                      topRight: Radius.circular(7),
                    ),
                    child: widget.image.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.image,
                            httpHeaders: ApiClient().getStalkerHeaders(),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppColors.surface,
                              child: const Center(
                                child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surface,
                              child: const Center(
                                child: Icon(Icons.tv_rounded, color: Colors.white24, size: 32),
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.surface,
                            child: const Center(
                              child: Icon(Icons.tv_rounded, color: Colors.white24, size: 32),
                            ),
                          ),
                  ),
                ),
                // Compact title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  Future<void> _playEpisode(Episode ep, List<Episode> episodes, int index) async {
    setState(() => _playingEpisodeId = ep.id);
    String cmd = ep.cmd;
    
    try {
      final authState = ref.read(authProvider);
      String streamUrl = cmd;
      List<SubtitleInfo> externalSubtitles = const [];
      
      if (authState.authType != 'xtream') {
        final stalkerApi = ref.read(stalkerApiProvider);
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
        }

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
            debugPrint('SERIES_SCREEN: createLink failed, falling back to direct URL: $directUrl');
            streamUrl = directUrl;
          } else {
            rethrow;
          }
        }
      }

      if (!mounted) return;
      setState(() => _playingEpisodeId = null);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: widget.series.name,
          subtitle: ep.name,
          contentId: 'ep_' + ep.id,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playback failed: ' + e.toString().replaceAll('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(seriesInfoProvider((seriesCmd: widget.series.cmd, seriesId: widget.series.id)));
    final favorites = ref.watch(favoritesProvider);
    final isLiked = favorites['series']?.contains(widget.series.id) ?? false;

    // Join metadata for left pane display
    final metadataParts = [
      if (widget.series.year.isNotEmpty) widget.series.year,
      if (widget.series.genre.isNotEmpty && widget.series.genre != 'null') widget.series.genre,
      if (widget.series.seriesCount.isNotEmpty && widget.series.seriesCount != 'null') '${widget.series.seriesCount} Ep',
    ];
    final metadataString = metadataParts.join('   •   ');

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
                  // App bar (Standard Left-aligned Back, Right-aligned Favorite)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isLiked ? Colors.red : Colors.white,
                            size: 22,
                          ),
                          onPressed: () {
                            ref.read(favoritesProvider.notifier).toggleFavorite('series', widget.series.id);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Side-by-side details layout (Fits in single viewport!)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Pane: Info & Synopsis (32% width)
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.32,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cover Poster
                                Row(
                                  children: [
                                    Container(
                                      width: 100,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.5),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: widget.series.poster.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: widget.series.poster,
                                                httpHeaders: ApiClient().getStalkerHeaders(),
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 36, color: Colors.white24),
                                              )
                                            : const Icon(Icons.movie, size: 36, color: Colors.white24),
                                      ),
                                    ),
                                    if (widget.series.rating.isNotEmpty && widget.series.rating != '0' && widget.series.rating != '0.0' && widget.series.rating != 'null') ...[
                                      const SizedBox(width: 16),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            widget.series.rating,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Series Title
                                Text(
                                  widget.series.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),

                                // Metadata row
                                if (metadataString.isNotEmpty) ...[
                                  Text(
                                    metadataString,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // Director / Cast details
                                if (widget.series.director.isNotEmpty && widget.series.director != 'null') ...[
                                  Text(
                                    'Director: ${widget.series.director}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                if (widget.series.actors.isNotEmpty && widget.series.actors != 'null') ...[
                                  Text(
                                    'Cast: ${widget.series.actors}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                // Scrollable Synopsis
                                const Text(
                                  'PLOT SUMMARY',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        widget.series.description.isNotEmpty && widget.series.description != 'null'
                                            ? widget.series.description
                                            : 'No plot synopsis is available for this title.',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),

                          // Right Pane: Seasons selector (Top) and Episodes List (Bottom)
                          Expanded(
                            child: seasonsAsync.when(
                              loading: () => const LoadingIndicator(message: 'Loading episodes...'),
                              error: (err, _) => Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
                                    const SizedBox(height: 12),
                                    Text('Failed to load season details: $err', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                                      style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                                    ),
                                  );
                                }

                                final currentSeason = seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)];

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Season Selector Tabs Row
                                    if (seasons.length > 1)
                                      Container(
                                        height: 38,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: seasons.length,
                                          itemBuilder: (context, i) {
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 10),
                                              child: _SeasonTab(
                                                title: seasons[i].name.toUpperCase(),
                                                isSelected: i == _selectedSeasonIndex,
                                                onTap: () => setState(() => _selectedSeasonIndex = i),
                                              ),
                                            );
                                          },
                                        ),
                                      ),

                                    // Episode Cards List
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: currentSeason.episodes.length,
                                        itemBuilder: (context, i) {
                                          final ep = currentSeason.episodes[i];
                                          final isPlaying = _playingEpisodeId == ep.id;
                                          return _EpisodeCard(
                                            episode: ep,
                                            isLoading: isPlaying,
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

class _SeasonTab extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeasonTab({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SeasonTab> createState() => _SeasonTabState();
}

class _SeasonTabState extends State<_SeasonTab> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _isFocused || _isHovered;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary
                  : active
                      ? AppColors.surfaceLight
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? AppColors.primary : Colors.white10,
                width: 1,
              ),
            ),
            child: Text(
              widget.title,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
