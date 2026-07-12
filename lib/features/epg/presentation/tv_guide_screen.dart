import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, Category, EpgProgram;
import '../../player/presentation/player_screen.dart';

class TvGuideScreen extends ConsumerStatefulWidget {
  const TvGuideScreen({super.key});

  @override
  ConsumerState<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends ConsumerState<TvGuideScreen> {
  String? _selectedCategoryId;
  final List<Channel> _channels = [];
  bool _isLoadingChannels = false;
  Channel? _selectedChannel;
  String _searchQuery = '';

  void _fetchChannels() async {
    if (_selectedCategoryId == null) return;
    setState(() {
      _isLoadingChannels = true;
      _channels.clear();
      _selectedChannel = null;
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
          if (_channels.isNotEmpty) {
            _selectedChannel = _channels.first;
          }
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0F),
        title: const Text('TV Guide', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, _) => const Center(child: Text('Error loading categories')),
        data: (categories) {
          if (_selectedCategoryId == null && categories.isNotEmpty) {
            _selectedCategoryId = categories.first.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fetchChannels();
            });
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final channelList = Container(
                width: isMobile ? double.infinity : 300,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search channel...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          prefixIcon: const Icon(Icons.search, color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                      ),
                    ),
                    Expanded(
                      child: _isLoadingChannels
                          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                          : ListView.builder(
                              itemCount: filteredChannels.length,
                              itemBuilder: (context, index) {
                                final channel = filteredChannels[index];
                                final isSelected = _selectedChannel?.id == channel.id;
                                return ListTile(
                                  leading: channel.logo.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: channel.logo,
                                          httpHeaders: ApiClient().getStalkerHeaders(),
                                          width: 40, height: 40,
                                          errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white24),
                                        )
                                      : const Icon(Icons.tv, color: Colors.white24),
                                  title: Text(channel.name, style: const TextStyle(color: Colors.white)),
                                  selected: isSelected,
                                  selectedTileColor: AppColors.primary.withOpacity(0.15),
                                  onTap: () {
                                    setState(() => _selectedChannel = channel);
                                    if (isMobile) {
                                      _showMobileEpgBottomSheet();
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );

              final rightPane = _selectedChannel == null
                  ? const Expanded(child: Center(child: Text('Select a channel to view EPG', style: TextStyle(color: Colors.white54))))
                  : Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: const Color(0xFF0C0C0F),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('Schedule: ${_selectedChannel!.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
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
                    );

              if (isMobile) {
                return Column(
                  children: [
                    Container(
                      height: 56,
                      color: const Color(0xFF0C0C0F),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          final isSelected = _selectedCategoryId == cat.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(cat.title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70)),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: const Color(0xFF1A1A1E),
                              onSelected: (s) {
                                if (s) {
                                  setState(() => _selectedCategoryId = cat.id);
                                  _fetchChannels();
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(child: channelList),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Container(
                      width: 220,
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white10, width: 0.5))),
                      child: ListView.builder(
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          final isSelected = _selectedCategoryId == cat.id;
                          return ListTile(
                            title: Text(cat.title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70)),
                            selected: isSelected,
                            selectedTileColor: AppColors.primary.withOpacity(0.15),
                            onTap: () {
                              setState(() => _selectedCategoryId = cat.id);
                              _fetchChannels();
                            },
                          );
                        },
                      ),
                    ),
                    channelList,
                    rightPane,
                  ],
                );
              }
            },
          );
        },
      ),
    );
  }

  void _showMobileEpgBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Schedule: ${_selectedChannel!.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _playChannel(_selectedChannel!);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('WATCH NOW'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _EpgList(channelId: _selectedChannel!.id)),
            ],
          ),
        );
      },
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
        if (programs.isEmpty) {
          return const Center(child: Text('No schedule available.', style: TextStyle(color: Colors.white54)));
        }
        
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
                        Text(
                          program.name,
                          style: TextStyle(color: Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14),
                        ),
                        if (program.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            program.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
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
