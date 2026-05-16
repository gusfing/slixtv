import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart';

/// Live TV screen with category sidebar and channel list.
class LiveTvScreen extends ConsumerStatefulWidget {
  final void Function(Channel channel)? onChannelTap;

  const LiveTvScreen({super.key, this.onChannelTap});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  String? _selectedCategory;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(tvCategoriesProvider);
    final channels = ref.watch(channelsByCategoryProvider(_selectedCategory));
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Live TV'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              showSearch(
                context: context,
                delegate: _ChannelSearchDelegate(
                  ref: ref,
                  onChannelTap: widget.onChannelTap,
                ),
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Category sidebar
          SizedBox(
            width: 100,
            child: categories.when(
              loading: () => const LoadingIndicator(),
              error: (e, _) => const Center(
                child: Icon(Icons.error, color: AppColors.error),
              ),
              data: (cats) => ListView(
                children: [
                  _CategoryChip(
                    label: 'All',
                    isSelected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  ...cats.map((cat) => _CategoryChip(
                        label: cat.title,
                        count: cat.channelCount,
                        isSelected: _selectedCategory == cat.id,
                        onTap: () => setState(() => _selectedCategory = cat.id),
                      )),
                ],
              ),
            ),
          ),

          // Divider
          Container(
            width: 0.5,
            color: AppColors.divider,
          ),

          // Channel list
          Expanded(
            child: channels.when(
              loading: () => const LoadingIndicator(message: 'Loading channels...'),
              error: (e, _) => ErrorDisplay(
                message: 'Failed to load channels',
                onRetry: () => ref.invalidate(channelsByCategoryProvider(_selectedCategory)),
              ),
              data: (channelList) {
                if (channelList.isEmpty) {
                  return const Center(
                    child: Text(
                      'No channels in this category',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: channelList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final channel = channelList[index];
                    final isFav = favorites['channels']?.contains(channel.id) ?? false;
                    return ChannelTile(
                      name: channel.name,
                      logo: channel.logo,
                      currentShow: channel.currentProgram?.name,
                      isFavorite: isFav,
                      onTap: () => widget.onChannelTap?.call(channel),
                      onFavoriteTap: () {
                        ref.read(favoritesProvider.notifier).toggleFavorite('channels', channel.id);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.sm,
          vertical: AppDimensions.md,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (count != null)
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  final void Function(Channel)? onChannelTap;

  _ChannelSearchDelegate({required this.ref, this.onChannelTap});

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: AppColors.textTertiary),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.length < 2) {
      return const Center(
        child: Text(
          'Type to search channels...',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    final channelsAsync = ref.watch(allChannelsProvider);

    return channelsAsync.when(
      loading: () => const LoadingIndicator(),
      error: (e, _) => ErrorDisplay(message: 'Search failed'),
      data: (channels) {
        final filtered = channels
            .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        if (filtered.isEmpty) {
          return const Center(
            child: Text('No channels found', style: TextStyle(color: AppColors.textTertiary)),
          );
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final channel = filtered[index];
            return ChannelTile(
              name: channel.name,
              logo: channel.logo,
              onTap: () {
                onChannelTap?.call(channel);
                close(context, channel.id);
              },
            );
          },
        );
      },
    );
  }
}
