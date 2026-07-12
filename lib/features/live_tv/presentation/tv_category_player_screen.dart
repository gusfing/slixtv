import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:better_player/better_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/parental_pin_dialog.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, EpgProgram;
import '../../player/presentation/player_screen.dart';

class TvCategoryPlayerScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final String categoryName;

  const TvCategoryPlayerScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  ConsumerState<TvCategoryPlayerScreen> createState() => _TvCategoryPlayerScreenState();
}

class _TvCategoryPlayerScreenState extends ConsumerState<TvCategoryPlayerScreen> {
  final ScrollController _channelScrollController = ScrollController();
  final List<Channel> _channels = [];
  bool _isLoadingChannels = false;
  String? _channelError;
  String _searchQuery = "";
  final _searchController = TextEditingController();

  // Inline player state
  Channel? _selectedChannel;
  BetterPlayerController? _betterPlayerController;
  
  bool _isPlayingInline = false;
  bool _isLoadingStream = false;
  String? _playError;

  // Add variables for tracking fallback headers
  String? _currentStreamUrl;
  bool _hasInitializedWithHeaders = false;

  @override
  void initState() {
    super.initState();
    _betterPlayerController?.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
        final error = event.parameters?["error"]?.toString() ?? "Unknown error";
        if (_hasInitializedWithHeaders && _currentStreamUrl != null) {
          _hasInitializedWithHeaders = false;
          if (mounted) {
            setState(() => _playError = 'Retrying stream connection...');
          }
          Future.microtask(() => _playInlineInternal(_currentStreamUrl!, withHeaders: false, enableHwdec: false));
        } else {
          if (mounted) {
            setState(() {
              _isLoadingStream = false;
              _playError = error;
            });
          }
        }
      }
    });

    _fetchChannels();
  }

  @override
  void dispose() {
    // _player?.stop();
    _betterPlayerController?.dispose();
    _channelScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchChannels() async {
    setState(() {
      _isLoadingChannels = true;
      _channels.clear();
      _channelError = null;
    });

    try {
      final authState = ref.read(authProvider);
      List<Channel> newChannels;
      if (authState.authType == 'xtream') {
        newChannels = await ref.read(xtreamApiProvider).getLiveStreams(categoryId: widget.categoryId);
      } else {
        newChannels = await ref.read(stalkerApiProvider).getChannels(categoryId: widget.categoryId);
      }

      if (mounted) {
        setState(() {
          _isLoadingChannels = false;
          _channels.addAll(newChannels);
          if (_channels.isNotEmpty) {
            _playChannelInline(_channels.first);
          }
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
      if (isAdultContent(categoryName: widget.categoryName, itemName: channel.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedChannel = channel;
      _isLoadingStream = true;
      _playError = null;
      _isPlayingInline = false;
    });

    try {
      final authState = ref.read(authProvider);
      String streamUrl;

      if (authState.authType == 'xtream') {
        streamUrl = channel.cmd;
      } else {
        if (channel.cmd.startsWith('http')) {
          streamUrl = channel.cmd;
        } else {
          final stalkerApi = ref.read(stalkerApiProvider);
          streamUrl = await stalkerApi.createLink(channel.cmd, 'itv');
        }
      }

      _currentStreamUrl = streamUrl;
      _hasInitializedWithHeaders = true;

      await _playInlineInternal(streamUrl, withHeaders: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStream = false;
          _playError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _playInlineInternal(String streamUrl, {bool withHeaders = true, bool enableHwdec = true}) async {
    try {
      final authState = ref.read(authProvider);
      Map<String, String>? headers;

      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: true,
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            showControls: true,
            enablePlayPause: true,
            enableSkips: false,
            enableProgressText: false,
            enableProgressBar: false,
            enableAudioTracks: true,
            enableSubtitles: true,
            enableQualities: true,
            enableFullscreen: false,
            controlBarColor: Colors.black87,
            textColor: Colors.white,
            iconsColor: Colors.white,
          ),
        ),
        betterPlayerDataSource: BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          streamUrl,
          headers: headers,
          cacheConfiguration: const BetterPlayerCacheConfiguration(
            useCache: true,
            preCacheSize: 10 * 1024 * 1024,
            maxCacheSize: 100 * 1024 * 1024,
            maxCacheFileSize: 10 * 1024 * 1024,
          ),
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 15000,
            maxBufferMs: 50000,
            bufferForPlaybackMs: 2500,
            bufferForPlaybackAfterRebufferMs: 5000,
          ),
        ),
      );

      if (withHeaders) {
        if (authState.authType == 'xtream') {
          headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
            'Accept': '*/*',
          };
        } else {
          final apiClient = ref.read(apiClientProvider);
          headers = {
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
            headers['MAC'] = mac;
            headers['X-User-MAC'] = mac;
          }
          if (apiClient.token != null) {
            headers['Authorization'] = 'Bearer ${apiClient.token!}';
            cookies['token'] = apiClient.token!;
          }
          headers['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
        }
      } else {
        headers = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
          'Accept': '*/*',
        };
      }

      // _player?.stop();
      // handled by init
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
    _betterPlayerController?.pause();
    setState(() => _isPlayingInline = false);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: '',
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
    final filteredChannels = _searchQuery.isEmpty
        ? _channels
        : _channels.where((c) => c.name.toLowerCase().contains(_searchQuery)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C0F),
                border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TV / ${widget.categoryName.toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 250,
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search channel...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Main Content
            Expanded(
              child: Row(
                children: [
                  // Left Pane: Channels List
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
                      ),
                      child: _isLoadingChannels
                          ? const Center(child: LoadingIndicator(message: 'Loading channels...'))
                          : _channelError != null
                              ? Center(child: Text(_channelError!, style: const TextStyle(color: AppColors.error)))
                              : filteredChannels.isEmpty
                                  ? const Center(child: Text('No channels found', style: TextStyle(color: Colors.white38)))
                                  : ListView.builder(
                                      controller: _channelScrollController,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      itemCount: filteredChannels.length,
                                      itemBuilder: (context, index) {
                                        final ch = filteredChannels[index];
                                        final isSelected = _selectedChannel?.id == ch.id;
                                        return _ChannelListTile(
                                          channel: ch,
                                          isSelected: isSelected,
                                          index: index + 1,
                                          onTap: () => _playChannelInline(ch),
                                        );
                                      },
                                    ),
                    ),
                  ),
                  
                  // Right Pane: Player and EPG
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Video Player Section
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            margin: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_isPlayingInline && _betterPlayerController != null)
                                    BetterPlayer(controller: _betterPlayerController!),
                                  if (_isLoadingStream)
                                    const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                                  if (_playError != null)
                                    Center(child: Text(_playError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                                  if (_isPlayingInline)
                                    Positioned(
                                      right: 16,
                                      bottom: 16,
                                      child: IconButton(
                                        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 32),
                                        onPressed: _playFullScreen,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        // Channel Info Below Player
                        if (_selectedChannel != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                if (_selectedChannel!.logo.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: _selectedChannel!.logo,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.contain,
                                      httpHeaders: ApiClient().getStalkerHeaders(),
                                      errorWidget: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38),
                                    ),
                                  ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedChannel!.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                      ),
                                      if (_selectedChannel!.currentProgram != null)
                                        Text(
                                          _selectedChannel!.currentProgram!.name,
                                          style: const TextStyle(color: AppColors.success, fontSize: 14, fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                            
                        // EPG Area
                        const Expanded(
                          child: Center(
                            child: Text('EPG information not available.', style: TextStyle(color: Colors.white12, fontSize: 14)),
                          ),
                        ),
                      ],
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

class _ChannelListTile extends StatefulWidget {
  final Channel channel;
  final bool isSelected;
  final int index;
  final VoidCallback onTap;

  const _ChannelListTile({
    required this.channel,
    required this.isSelected,
    required this.index,
    required this.onTap,
  });

  @override
  State<_ChannelListTile> createState() => _ChannelListTileState();
}

class _ChannelListTileState extends State<_ChannelListTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _isFocused;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected ? AppColors.primary : (_isFocused ? Colors.white10 : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                alignment: Alignment.centerRight,
                child: Text(
                  '${widget.index}',
                  style: TextStyle(color: active ? Colors.white : Colors.white24, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.channel.logo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: widget.channel.logo,
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                    httpHeaders: ApiClient().getStalkerHeaders(),
                    errorWidget: (_, __, ___) => const SizedBox(width: 36),
                  ),
                )
              else
                const Icon(Icons.tv_rounded, color: Colors.white24, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.channel.name,
                  style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                const Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
