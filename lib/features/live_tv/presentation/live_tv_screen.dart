import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/parental_pin_dialog.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, Category, EpgProgram;
import '../../player/presentation/player_screen.dart';

/// Reusable category group model for sidebar.
class _TvCategoryGroup {
  final String name;
  final List<Category> categories;
  _TvCategoryGroup(this.name, this.categories);
}

/// Live TV Screen – single-screen layout matching Movies/Series sidebar pattern.
class LiveTvScreen extends ConsumerStatefulWidget {
  final void Function(Channel channel)? onChannelTap;

  const LiveTvScreen({super.key, this.onChannelTap});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  String? _selectedCategoryId;
  String _selectedCategoryName = '';
  final ScrollController _channelScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final List<Channel> _channels = [];
  bool _isLoadingChannels = false;
  String? _channelError;
  String _searchQuery = "";
  final _searchController = TextEditingController();
  final Map<String, bool> _expandedGroups = {};

  // Inline player state
  Channel? _selectedChannel;
  Player? _player;
  VideoController? _videoController;
  bool _isPlayingInline = false;
  bool _isLoadingStream = false;
  String? _playError;
  bool _catchupExpanded = true;

  bool _isRightPanelCollapsed = false;
  bool _pendingAdultAuth = false;
  
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _player = Player();
    _player?.setVolume(100.0);
    _videoController = VideoController(_player!);
  }

  @override
  void dispose() {
    _player?.stop();
    _player?.dispose();
    _channelScrollController.dispose();
    _sidebarScrollController.dispose();
    _searchController.dispose();
    ref.read(parentalLockProvider.notifier).lockSession();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _selectCategory(String? categoryId, String categoryName) async {
    if (_selectedCategoryId == categoryId) return;

    final isAdult = isAdultContent(categoryName: categoryName);
    final lockState = ref.read(parentalLockProvider);
    final needsAuth = isAdult && lockState.isLocked && !lockState.isSessionUnlocked;

    // Set category immediately so sidebar highlights, but block content
    setState(() {
      _selectedCategoryId = categoryId;
      _selectedCategoryName = categoryName;
      _searchQuery = '';
      _searchController.clear();
      _channels.clear();
      _pendingAdultAuth = needsAuth;
    });

    if (needsAuth) {
      // Don't fetch anything - show lock screen instead
      return;
    }

    _fetchChannels();
  }

  Future<void> _unlockAdultCategory() async {
    print('DEBUG: _unlockAdultCategory (Live TV) called');
    try {
      final authenticated = await ParentalPinDialog.show(context);
      print('DEBUG: ParentalPinDialog (Live TV) returned: $authenticated');
      if (!authenticated) return;
      ref.read(parentalLockProvider.notifier).unlockSession();
      if (mounted) {
        setState(() => _pendingAdultAuth = false);
        _fetchChannels();
      }
    } catch (e, stackTrace) {
      print('DEBUG: Exception in _unlockAdultCategory (Live TV): $e\n$stackTrace');
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

  Future<void> _fetchChannels() async {
    if (_selectedCategoryId == null) return;

    setState(() {
      _isLoadingChannels = true;
      _channels.clear();
      _channelError = null;
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
          _isLoadingChannels = false;
          _channels.addAll(newChannels);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingChannels = false;
          _channelError = 'Failed to load channels: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _playChannelInline(Channel channel) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      if (isAdultContent(categoryName: _selectedCategoryName, itemName: channel.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }

    setState(() {
      _selectedChannel = channel;
      _isLoadingStream = true;
      _isPlayingInline = false;
      _playError = null;
    });

    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      final streamUrl = await stalkerApi.createLink(channel.cmd, 'itv');

      final apiClient = ref.read(apiClientProvider);
      final headers = {
        'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: Ethernet',
        'Accept': '*/*',
        'Accept-Language': 'en_US',
        'Referer': '${apiClient.portalBase}/c/',
      };
      final Map<String, String> cookies = {
        'stb_lang': 'en',
        'timezone': 'Europe/Kyiv',
      };
      if (apiClient.macAddress != null) {
        final mac = apiClient.macAddress!;
        cookies['mac'] = mac;
        if (apiClient.serialNumber != null) {
          cookies['sn'] = apiClient.serialNumber!;
        }
        headers['MAC'] = mac;
        headers['X-User-MAC'] = mac;
      }
      if (apiClient.token != null) {
        headers['Authorization'] = 'Bearer ${apiClient.token!}';
        cookies['token'] = apiClient.token!;
      }
      headers['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

      await _player?.open(Media(streamUrl, httpHeaders: headers));
      if (mounted) {
        setState(() {
          _isLoadingStream = false;
          _isPlayingInline = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStream = false;
          _playError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _playFullScreen() {
    if (_selectedChannel == null) return;
    _player?.pause();
    setState(() => _isPlayingInline = false);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: _player?.state.playlist.medias.first.uri ?? '',
        title: _selectedChannel!.name,
        subtitle: _selectedChannel!.currentProgram?.name,
        contentId: 'ch_${_selectedChannel!.id}',
      ),
    )).then((_) {
      if (mounted && _selectedChannel != null) {
        _playChannelInline(_selectedChannel!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(tvCategoriesProvider);
    final favorites = ref.watch(favoritesProvider);

    final filteredChannels = _searchQuery.isEmpty
        ? _channels
        : _channels.where((c) => c.name.toLowerCase().contains(_searchQuery)).toList();

    // Build category groups
    categoriesAsync.whenData((categories) {
      if (_selectedCategoryId == null && categories.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedCategoryId == null) {
            final nonAdultCats = categories.where((c) => !isAdultContent(categoryName: c.title)).toList();
            final defaultCat = nonAdultCats.isNotEmpty ? nonAdultCats.first : categories.first;
            _selectCategory(defaultCat.id, defaultCat.title);
          }
        });
      } else if (_selectedCategoryId != null) {
        final selectedCat = categories.firstWhere(
          (c) => c.id == _selectedCategoryId,
          orElse: () => Category(id: _selectedCategoryId!, title: _selectedCategoryName),
        );
        final isAdult = isAdultContent(categoryName: selectedCat.title);
        final lockState = ref.read(parentalLockProvider);
        if (isAdult && lockState.isLocked && !lockState.isSessionUnlocked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_pendingAdultAuth) {
              setState(() {
                _pendingAdultAuth = true;
                _channels.clear();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Left Sidebar: Categories ───
            if (_selectedChannel == null)
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
                        const Icon(Icons.live_tv_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        const Text(
                          'Live TV',
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Error loading', style: TextStyle(color: AppColors.error, fontSize: 11)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => ref.invalidate(tvCategoriesProvider),
                              child: const Text('Retry', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
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
                        if (_selectedCategoryId != null) {
                          for (final group in localGroups) {
                            if (group.categories.any((c) => c.id == _selectedCategoryId)) {
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
                                      count: cat.channelCount,
                                      isSelected: _selectedCategoryId == cat.id,
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

            // ─── Middle: Channels List ───
            Expanded(
              child: Column(
                children: [
                  // Compact top bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        if (_selectedChannel != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                            padding: const EdgeInsets.only(right: 12),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _selectedChannel = null;
                                _isPlayingInline = false;
                                _player?.stop();
                              });
                            },
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedCategoryName.isNotEmpty ? _selectedCategoryName : 'Select Category',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!_isLoadingChannels && _channels.isNotEmpty)
                                Text(
                                  '${filteredChannels.length} channel${filteredChannels.length != 1 ? 's' : ''}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Search channels
                        Flexible(
                          child: SizedBox(
                            width: 160,
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
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white10),

                  // Channel list
                  Expanded(
                    child: _pendingAdultAuth
                        ? _buildAdultLockOverlay()
                        : _isLoadingChannels
                            ? const LoadingIndicator(message: 'Loading channels...')
                            : _channelError != null
                                ? ErrorDisplay(
                                    message: _channelError!,
                                    onRetry: _fetchChannels,
                                  )
                                : _selectedCategoryId == null
                                    ? const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.live_tv_rounded, size: 48, color: Colors.white24),
                                            SizedBox(height: 8),
                                            Text(
                                              'Select a category',
                                              style: TextStyle(color: Colors.white38, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      )
                                    : filteredChannels.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No channels available',
                                              style: TextStyle(color: Colors.white30, fontSize: 13),
                                            ),
                                          )
                                        : ListView.separated(
                                            controller: _channelScrollController,
                                            padding: const EdgeInsets.all(8),
                                            itemCount: filteredChannels.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                                            itemBuilder: (context, index) {
                                              final ch = filteredChannels[index];
                                              final isSelected = _selectedChannel?.id == ch.id;
                                              final isFav = favorites['channels']?.contains(ch.id) ?? false;

                                              return _ChannelRowItem(
                                                channel: ch,
                                                isSelected: isSelected,
                                                isFav: isFav,
                                                onFavTap: () {
                                                  ref.read(favoritesProvider.notifier).toggleFavorite('channels', ch.id);
                                                },
                                                onTap: () => _playChannelInline(ch),
                                              );
                                            },
                                          ),
                  ),
                ],
              ),
            ),

            // ─── Right: Inline Player + EPG / Catch-up ───
            if (_selectedChannel != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _isRightPanelCollapsed
                    ? 60
                    : (MediaQuery.of(context).size.width > 900
                        ? MediaQuery.of(context).size.width * 0.4
                        : MediaQuery.of(context).size.width * 0.45),
                margin: const EdgeInsets.only(right: 8, bottom: 8, top: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isRightPanelCollapsed) ...[
                      // Inline Video Player container
                      Flexible(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(11),
                              topRight: Radius.circular(11),
                            ),
                            child: Container(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_isPlayingInline && _videoController != null)
                                  Video(
                                    controller: _videoController!,
                                    fit: BoxFit.contain,
                                    controls: NoVideoControls,
                                  ),
                                if (_isLoadingStream)
                                  const Center(
                                    child: CircularProgressIndicator(color: AppColors.primary),
                                  ),
                                if (_playError != null)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        _playError!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                                      ),
                                    ),
                                  ),

                                // Full screen overlay
                                if (_isPlayingInline)
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    child: IconButton(
                                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 28),
                                      onPressed: _playFullScreen,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ),

                      // Selected Channel Title bar with program info
                      _buildNowPlayingBar(),
                      const Divider(height: 1, color: Colors.white10),

                      // Catch-up / EPG Section (collapsible)
                      Expanded(child: _buildCatchupSection()),
                    ] else
                      Expanded(
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                          onPressed: () => setState(() => _isRightPanelCollapsed = false),
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

  /// Now-playing bar with channel name and current program info.
  Widget _buildNowPlayingBar() {
    final ch = _selectedChannel!;
    final prog = ch.currentProgram;
    final now = DateTime.now();

    double progress = 0.0;
    String timeInfo = '';
    String timeRemaining = '';

    if (prog != null) {
      final total = prog.endTime.difference(prog.startTime).inSeconds;
      if (total > 0) {
        final elapsed = now.difference(prog.startTime).inSeconds;
        progress = (elapsed / total).clamp(0.0, 1.0);
        final remaining = prog.endTime.difference(now).inMinutes;
        if (remaining > 0) {
          timeRemaining = '$remaining min left';
        }
      }
      final df = DateFormat('HH:mm');
      timeInfo = '${df.format(prog.startTime)} – ${df.format(prog.endTime)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Channel logo (small)
              if (ch.logo.isNotEmpty)
                Container(
                  width: 28,
                  height: 20,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: ch.logo,
                    httpHeaders: ApiClient().getStalkerHeaders(),
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                ),
              Expanded(
                child: Text(
                  ch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (prog != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              if (_catchupExpanded)
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        backgroundColor: AppColors.background,
                        insetPadding: const EdgeInsets.all(24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.white10)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${ch.name} - EPG Guide',
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _EpgTimelineList(channel: ch),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(Icons.fullscreen_rounded, color: Colors.white54, size: 20),
                  ),
                ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _catchupExpanded = !_catchupExpanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        color: _catchupExpanded ? AppColors.primary : Colors.white54,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'EPG',
                        style: TextStyle(
                          color: _catchupExpanded ? AppColors.primary : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                onPressed: () => setState(() => _isRightPanelCollapsed = true),
              ),
            ],
          ),
          if (prog != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    prog.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                if (timeRemaining.isNotEmpty)
                  Text(
                    timeRemaining,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              timeInfo,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Collapsible Catch-up / EPG section.
  Widget _buildCatchupSection() {
    if (!_catchupExpanded) return const SizedBox();

    return Expanded(
      child: Container(
        color: const Color(0xFF1A1A1F),
        child: _EpgTimelineList(channel: _selectedChannel!),
      ),
    );
  }
}


// ─── Sidebar Category Tile ────────────────────────────────
class _SidebarCategoryTile extends StatefulWidget {
  final String name;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;
  final bool indent;

  const _SidebarCategoryTile({
    required this.name,
    this.count,
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
            top: 9,
            bottom: 9,
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
          child: Row(
            children: [
              Expanded(
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
              if (widget.count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: TextStyle(
                      color: active ? AppColors.primary : Colors.white30,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
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


// ─── Channel Row Item ─────────────────────────────────────
class _ChannelRowItem extends StatefulWidget {
  final Channel channel;
  final bool isSelected;
  final bool isFav;
  final VoidCallback onFavTap;
  final VoidCallback onTap;

  const _ChannelRowItem({
    required this.channel,
    required this.isSelected,
    required this.isFav,
    required this.onFavTap,
    required this.onTap,
  });

  @override
  State<_ChannelRowItem> createState() => _ChannelRowItemState();
}

class _ChannelRowItemState extends State<_ChannelRowItem> {
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? AppColors.surfaceLight : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isSelected ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Logo or Icon
                Container(
                  width: 44,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: widget.channel.logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.logo,
                          httpHeaders: ApiClient().getStalkerHeaders(),
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white24, size: 18),
                        )
                      : const Icon(Icons.tv_rounded, color: Colors.white24, size: 18),
                ),
                const SizedBox(width: 12),

                // Channel Name & current EPG
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.channel.currentProgram != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.channel.currentProgram!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Favorites button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    widget.isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: widget.isFav ? Colors.red : Colors.white30,
                    size: 18,
                  ),
                  onPressed: widget.onFavTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ─── EPG Timeline List ────────────────────────────────────
class _EpgTimelineList extends ConsumerWidget {
  final Channel channel;

  const _EpgTimelineList({required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgAsync = ref.watch(simpleEpgProvider(channel.id));

    return epgAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
      error: (err, _) => const Center(
        child: Text('EPG Guide unavailable', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
      data: (epgList) {
        if (epgList.isEmpty) {
          return const Center(
            child: Text('No schedule guide available', style: TextStyle(color: Colors.white38, fontSize: 12)),
          );
        }

        final sorted = List<EpgProgram>.from(epgList)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        final now = DateTime.now();

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const Divider(height: 12, color: Colors.white10),
          itemBuilder: (context, index) {
            final ep = sorted[index];
            final isCurrent = ep.startTime.isBefore(now) && ep.endTime.isAfter(now);
            final isPast = ep.endTime.isBefore(now);

            return InkWell(
              onTap: () async {
                // If it's in the future, don't allow catchup
                if (ep.startTime.isAfter(now)) return;

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                );

                try {
                  final api = ref.read(stalkerApiProvider);
                  final startSecsStr = (ep.startTime.millisecondsSinceEpoch ~/ 1000).toString();
                  final durationSecs = ep.endTime.difference(ep.startTime).inSeconds.toString();

                  final streamUrl = await api.createLink(
                    'auto /media/${channel.id}.mpg',
                    'itv',
                    archiveStart: startSecsStr,
                    archiveDuration: durationSecs,
                  );

                  if (!context.mounted) return;
                  Navigator.of(context).pop(); // dismiss loading

                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      streamUrl: streamUrl,
                      title: channel.name,
                      subtitle: ep.name,
                      contentId: 'archive_${channel.id}_$startSecsStr',
                    ),
                  ));
                } catch (e) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop(); // dismiss loading
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Catch-up failed: $e')));
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Catch-up icon for past programs
                  if (isPast && !isCurrent)
                    Container(
                      margin: const EdgeInsets.only(right: 6, top: 1),
                      child: const Icon(Icons.replay_rounded, color: AppColors.primary, size: 14),
                    ),
                  // Timing
                  SizedBox(
                    width: 80,
                    child: Text(
                      ep.timeRange,
                      style: TextStyle(
                        color: isCurrent ? AppColors.primary : Colors.white60,
                        fontWeight: _fontWeight(isCurrent),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Title
                  Expanded(
                    child: Text(
                      ep.name,
                      style: TextStyle(
                        color: isCurrent ? AppColors.primary : Colors.white70,
                        fontWeight: _fontWeight(isCurrent),
                        fontSize: 12,
                      ),
                    ),
                  ),

                  // LIVE tag
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(color: AppColors.primary, fontSize: 8, fontWeight: FontWeight.bold),
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

  FontWeight _fontWeight(bool current) => current ? FontWeight.bold : FontWeight.normal;
}
