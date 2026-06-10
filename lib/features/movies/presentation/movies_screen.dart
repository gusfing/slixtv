import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Category;
import '../domain/models.dart' show VodItem;
import '../../../core/widgets/parental_pin_dialog.dart';

class MoviesScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  final void Function(VodItem movie)? onMovieTap;

  const MoviesScreen({
    super.key,
    this.categoryId,
    this.onMovieTap,
  });

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  String? _selectedCategory;
  String _selectedCategoryName = 'All';
  final ScrollController _scrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final List<VodItem> _movies = [];
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
      _fetchMovies(isRefresh: true);
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
        _fetchMovies(isRefresh: false);
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
      _movies.clear();
      _pendingAdultAuth = needsAuth;
    });

    if (needsAuth) return;

    _fetchMovies(isRefresh: true);
  }

  Future<void> _unlockAdultCategory() async {
    print('DEBUG: _unlockAdultCategory called');
    try {
      final authenticated = await ParentalPinDialog.show(context);
      print('DEBUG: ParentalPinDialog returned: $authenticated');
      if (!authenticated) return;
      ref.read(parentalLockProvider.notifier).unlockSession();
      if (mounted) {
        setState(() => _pendingAdultAuth = false);
        _fetchMovies(isRefresh: true);
      }
    } catch (e, stackTrace) {
      print('DEBUG: Exception in _unlockAdultCategory: $e\n$stackTrace');
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

  Future<void> _fetchMovies({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _movies.clear();
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
      final List<VodItem> newMovies;
      if (authState.authType == 'xtream') {
        newMovies = await ref.read(xtreamApiProvider).getVodStreams(
          categoryId: _selectedCategory,
          page: _currentPage,
        );
      } else {
        newMovies = await ref.read(moviesServiceProvider).getOrderedList(
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
          _movies.addAll(newMovies);
          if (newMovies.length < 14) {
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
            _errorMessage = 'Failed to load movies: ${e.toString().replaceAll('Exception: ', '')}';
          } else {
            _isLoadingMore = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredMovies = _searchQuery.isEmpty
        ? _movies
        : _movies.where((m) => m.name.toLowerCase().contains(_searchQuery)).toList();
    final categoriesAsync = ref.watch(vodCategoriesProvider);

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
                _movies.clear();
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
                        const Icon(Icons.movie_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        const Text(
                          'Movies',
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
                        print('DEBUG_CATEGORIES: Total Categories = ${categories.length}, Categories: ${categories.map((c) => c.title).toList()}');
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

            // ─── Right Content: Movies Grid ───
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
                          '(${filteredMovies.length}${_hasMore ? '+' : ''})',
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

                  // Movie grid
                  Expanded(
                    child: _pendingAdultAuth
                        ? _buildAdultLockOverlay()
                        : _isLoading
                            ? const LoadingIndicator(message: 'Loading movies...')
                            : _errorMessage != null
                                ? ErrorDisplay(
                                    message: _errorMessage!,
                                    onRetry: () => _fetchMovies(isRefresh: true),
                                  )
                                : filteredMovies.isEmpty
                                    ? const Center(
                                        child: Text('No movies available', style: TextStyle(color: Colors.white30)),
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
                                        itemCount: filteredMovies.length + (_isLoadingMore ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index >= filteredMovies.length) {
                                            return const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                                              ),
                                            );
                                          }
                                          final movie = filteredMovies[index];
                                          return _PosterCard(
                                            title: movie.name,
                                            image: movie.poster,
                                            onTap: () => widget.onMovieTap?.call(movie),
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
                    color: AppColors.primary.withOpacity(0.2),
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
                                child: Icon(Icons.movie_creation_rounded, color: Colors.white24, size: 32),
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.surface,
                            child: const Center(
                              child: Icon(Icons.movie_creation_rounded, color: Colors.white24, size: 32),
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
