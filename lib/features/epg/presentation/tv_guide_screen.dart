import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, Category, EpgProgram;
import '../../player/presentation/player_screen.dart';

class _TvCategoryGroup {
  final String name;
  final List<Category> categories;
  _TvCategoryGroup(this.name, this.categories);
}

class TvGuideScreen extends ConsumerStatefulWidget {
  const TvGuideScreen({super.key});

  @override
  ConsumerState<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends ConsumerState<TvGuideScreen> {
  String? _selectedCategoryId;
  String _selectedCategoryName = '';
  final ScrollController _channelScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final List<Channel> _channels = [];
  bool _isLoadingChannels = false;
  Channel? _selectedChannel;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final Map<String, bool> _expandedGroups = {};
  bool _pendingAdultAuth = false;

  @override
  void dispose() {
    _channelScrollController.dispose();
    _sidebarScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectCategory(String? categoryId, String categoryName) async {
    if (_selectedCategoryId == categoryId) return;

    setState(() {
      _selectedCategoryId = categoryId;
      _selectedCategoryName = categoryName;
      _searchQuery = '';
      _searchController.clear();
      _channels.clear();
      _selectedChannel = null;
    });

    _fetchChannels();
  }

  Future<void> _fetchChannels() async {
    if (_selectedCategoryId == null) return;
    setState(() {
      _isLoadingChannels = true;
      _channels.clear();
    });

    try {
      final authState = ref.read(authProvider);
      List<Channel> newChannels;
      if (authState.authType == 'xtream') {
        newChannels = await ref.read(xtreamApiProvider).getLiveStreams(categoryId: _selectedCategoryId);
      } else {
        newChannels = await ref.read(stalkerApiProvider).getChannels(categoryId: _selectedCategoryId);
      }
      if (mounted) {
        setState(() {
          _channels.addAll(newChannels);
          _isLoadingChannels = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingChannels = false);
    }
  }

  void _playChannel(Channel channel) async {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load channel')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(tvCategoriesProvider);
    final filteredChannels = _searchQuery.isEmpty 
        ? _channels 
        : _channels.where((c) => c.name.toLowerCase().contains(_searchQuery)).toList();

    categoriesAsync.whenData((categories) {
      if (_selectedCategoryId == null && categories.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedCategoryId == null) {
            final defaultCat = categories.first;
            _selectCategory(defaultCat.id, defaultCat.title);
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        const Icon(Icons.list_alt_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        const Text('TV Guide', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(
                    child: categoriesAsync.when(
                      loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                      error: (err, _) => const Center(child: Text('Error', style: TextStyle(color: AppColors.error))),
                      data: (categories) {
                        final List<_TvCategoryGroup> localGroups = [];
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
                          localGroups.add(_TvCategoryGroup(prefix, list));
                        });

                        if (ungrouped.isNotEmpty) {
                          localGroups.add(_TvCategoryGroup('General', ungrouped));
                        }

                        for (final group in localGroups) {
                          _expandedGroups.putIfAbsent(group.name, () => true);
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
                                      isSelected: _selectedCategoryId == cat.id,
                                      onTap: () => _selectCategory(cat.id, cat.title),
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

            // ─── Middle: Channels List ───
            Container(
              width: 250,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search channel...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  Expanded(
                    child: _isLoadingChannels
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : filteredChannels.isEmpty
                            ? const Center(child: Text('No channels', style: TextStyle(color: Colors.white30, fontSize: 13)))
                            : ListView.separated(
                                controller: _channelScrollController,
                                padding: const EdgeInsets.all(8),
                                itemCount: filteredChannels.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final ch = filteredChannels[index];
                                  final isSelected = _selectedChannel?.id == ch.id;
                                  return InkWell(
                                    onTap: () => setState(() => _selectedChannel = ch),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSelected ? AppColors.primary.withOpacity(0.5) : Colors.transparent),
                                      ),
                                      child: Row(
                                        children: [
                                          if (ch.logo.isNotEmpty)
                                            CachedNetworkImage(
                                              imageUrl: ch.logo,
                                              width: 32, height: 24,
                                              httpHeaders: ApiClient().getStalkerHeaders(),
                                              errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white24, size: 20),
                                            )
                                          else
                                            const Icon(Icons.tv, color: Colors.white24, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(ch.name, style: TextStyle(color: isSelected ? AppColors.primary : Colors.white, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),

            // ─── Right: EPG Schedule ───
            Expanded(
              child: _selectedChannel == null
                  ? const Center(child: Text('Select a channel to view schedule', style: TextStyle(color: Colors.white54)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: const Color(0xFF0C0C0F),
                          child: Row(
                            children: [
                              Expanded(child: Text('Schedule: ${_selectedChannel!.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                              ElevatedButton.icon(
                                onPressed: () => _playChannel(_selectedChannel!),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Watch'),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _EpgList(channelId: _selectedChannel!.id)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpgList extends ConsumerWidget {
  final String channelId;
  const _EpgList({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgAsync = ref.watch(epgProvider(channelId));
    return epgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (err, _) => Center(child: Text('Failed to load EPG', style: TextStyle(color: AppColors.error))),
      data: (programs) {
        if (programs.isEmpty) return const Center(child: Text('No schedule available.', style: TextStyle(color: Colors.white54)));
        final now = DateTime.now();
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: programs.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
          itemBuilder: (context, index) {
            final program = programs[index];
            final isCurrent = program.startTime.isBefore(now) && program.endTime.isAfter(now);
            final timeFormat = DateFormat('h:mm a');
            return Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isCurrent ? Border.all(color: AppColors.primary, width: 0.5) : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(timeFormat.format(program.startTime), style: TextStyle(color: isCurrent ? AppColors.primary : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(timeFormat.format(program.endTime), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(program.name, style: TextStyle(color: Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                        if (program.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(program.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  final String name;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarGroupHeader({required this.name, required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.black26,
        child: Row(
          children: [
            Expanded(child: Text(name.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
            Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarCategoryTile extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarCategoryTile({required this.name, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          border: Border(left: BorderSide(color: isSelected ? AppColors.primary : Colors.transparent, width: 3)),
        ),
        child: Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}
