import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show Channel, Category, EpgProgram, SubtitleInfo;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem;
import '../../player/presentation/player_screen.dart';
import '../../../core/widgets/parental_pin_dialog.dart';
import '../../../core/network/api_client.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../../core/config/app_config.dart';

import '../../live_tv/presentation/live_tv_screen.dart';
import '../../movies/presentation/movie_categories_screen.dart';
import '../../movies/presentation/movies_screen.dart';
import '../../series/presentation/series_categories_screen.dart';
import '../../series/presentation/series_screen.dart';
import '../../search/presentation/search_screen.dart';
import '../../profile/presentation/profile_screen.dart';

/// Smarters Pro-style Grid dashboard Home Screen.
class HomeScreen extends ConsumerStatefulWidget {
  final void Function(Channel channel)? onChannelTap;
  final void Function(VodItem movie)? onMovieTap;
  final void Function(SeriesItem series)? onSeriesTap;
  final void Function(int tabIndex)? onNavigateToTab;
  final VoidCallback? onLogout;

  const HomeScreen({
    super.key,
    this.onChannelTap,
    this.onMovieTap,
    this.onSeriesTap,
    this.onNavigateToTab,
    this.onLogout,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final AppLogger _logger = AppLogger();
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(continueWatchingProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String _getExpirationText(AuthState authState) {
    if (authState.authType == 'xtream') {
      final info = authState.xtreamUserInfo;
      if (info == null) return 'Loading...';
      final expDate = info['exp_date'];
      if (expDate == null ||
          expDate.toString().isEmpty ||
          expDate.toString() == 'null' ||
          expDate.toString() == '0') {
        return 'Unlimited';
      }
      try {
        final sec = int.tryParse(expDate.toString());
        if (sec == null) return expDate.toString();
        final date = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        return DateFormat("dd MMM, yyyy").format(date);
      } catch (_) {
        return 'Active';
      }
    } else {
      final profile = authState.profile;
      if (profile == null) return 'Loading...';
      final endDate = profile.endDate;
      if (endDate.isEmpty || endDate == 'null') return 'Unlimited';
      return endDate;
    }
  }

  String _getUserDisplay(AuthState authState) {
    if (authState.authType == 'xtream') {
      final info = authState.xtreamUserInfo;
      return info?['username']?.toString() ?? 'Xtream User';
    } else {
      final profile = authState.profile;
      return profile?.name ?? authState.macAddress ?? 'Stalker User';
    }
  }

  Future<void> _playCatchupProgram(BuildContext context, WidgetRef ref, Channel channel, EpgProgram program) async {
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

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final authState = ref.read(authProvider);
      final String streamUrl;
      final String startSecsStr;

      if (authState.authType == 'xtream') {
        final xtreamApi = ref.read(xtreamApiProvider);
        final startSecs = program.startTime;
        startSecsStr = (startSecs.millisecondsSinceEpoch ~/ 1000).toString();
        final durationMins = program.endTime.difference(program.startTime).inMinutes.toString();
        
        // Use the universally supported streaming/timeshift.php endpoint which takes UNIX timestamps
        streamUrl = '${xtreamApi.portalUrl}/streaming/timeshift.php?username=${xtreamApi.username}&password=${xtreamApi.password}&stream=${channel.id}&start=$startSecsStr&duration=$durationMins';
        
        _logger.i('CATCH_UP', 'Xtream Timeshift URL: $streamUrl');
      } else {
        final api = ref.read(stalkerApiProvider);
        final startSecs = (program.startTime.millisecondsSinceEpoch ~/ 1000).toString();
        startSecsStr = startSecs;
        final durationSecs = program.endTime.difference(program.startTime).inSeconds.toString();

        _logger.mag('CATCH_UP', 'Resolving archive link for ${channel.name} / ${program.name}');
        streamUrl = await api.createLink(
          channel.cmd,
          'itv',
          archiveStart: startSecs,
          archiveDuration: durationSecs,
        );
      }

      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading dialog
      // Safely dismiss all bottom sheets back to the root route
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Navigate to the player screen
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: channel.name,
          subtitle: program.name,
          contentId: 'archive_${channel.id}_$startSecsStr',
        ),
      ));
    } catch (e) {
      _logger.e('HOME_SCREEN', 'Catch-up playback failed', error: e);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play catch-up: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showCatchupGuideBottomSheet(BuildContext context, Channel channel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
                    child: Row(
                      children: [
                        if (channel.logo.isNotEmpty)
                          Container(
                            width: 48,
                            height: 36,
                            margin: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                color: AppColors.surface,
                                child: CachedNetworkImage(
                                  imageUrl: channel.logo,
                                  httpHeaders: ApiClient().getStalkerHeaders(),
                                  fit: BoxFit.contain,
                                  errorWidget: (context, url, error) => const Icon(
                                    Icons.tv,
                                    color: AppColors.textTertiary,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                channel.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Select catch-up program from schedule',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24, thickness: 0.5, color: AppColors.divider),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final epgAsync = ref.watch(simpleEpgProvider(channel.id));
                        return epgAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                          error: (err, _) => Center(
                            child: Text(
                              'Failed to load program guide: $err',
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                          data: (epgList) {
                            if (epgList.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No schedule available for this channel.',
                                  style: TextStyle(color: AppColors.textTertiary),
                                ),
                              );
                            }

                            final sortedList = List<EpgProgram>.from(epgList)
                              ..sort((a, b) => a.startTime.compareTo(b.startTime));

                            final now = DateTime.now();

                            return ListView.builder(
                              controller: scrollController,
                              itemCount: sortedList.length,
                              itemBuilder: (context, index) {
                                final program = sortedList[index];
                                final isPast = program.endTime.isBefore(now);
                                final isCurrent = program.startTime.isBefore(now) && program.endTime.isAfter(now);

                                Widget badge;
                                Widget action;
                                VoidCallback? onPlayTap;

                                if (isCurrent) {
                                  badge = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                  action = const Icon(Icons.play_circle_filled_rounded, color: AppColors.primary, size: 28);
                                  onPlayTap = () {
                                    Navigator.of(context).pop(); // dismiss sheet
                                    Navigator.of(context).pop(); // dismiss channel sheet
                                    widget.onChannelTap?.call(channel); // play live
                                  };
                                } else if (isPast) {
                                  badge = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ARCHIVE',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                  action = const Icon(Icons.play_circle_filled_rounded, color: AppColors.success, size: 28);
                                  onPlayTap = () => _playCatchupProgram(context, ref, channel, program);
                                } else {
                                  badge = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.border, width: 0.5),
                                    ),
                                    child: const Text(
                                      'UPCOMING',
                                      style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                  action = const Icon(Icons.lock_clock_rounded, color: AppColors.textTertiary, size: 24);
                                }

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
                                  title: Row(
                                    children: [
                                      Text(
                                        program.timeRange,
                                        style: TextStyle(
                                          color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      badge,
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        program.name,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: action,
                                  onTap: onPlayTap,
                                );
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
          },
        );
      },
    );
  }

  void _showCatchupChannelsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Catch-Up Archive',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24, thickness: 0.5, color: AppColors.border),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final channelsAsync = ref.watch(allChannelsProvider);
                        return channelsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                          error: (err, _) => Center(
                            child: Text(
                              'Failed to load channels: $err',
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                          data: (allChannels) {
                            final channels = allChannels.where((c) => c.hasArchive).toList();
                            
                            if (channels.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No catch-up channels available.',
                                  style: TextStyle(color: AppColors.textTertiary),
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: scrollController,
                              itemCount: channels.length,
                              itemBuilder: (context, index) {
                                final channel = channels[index];
                                return ListTile(
                                  leading: channel.logo.isNotEmpty
                                      ? Container(
                                          width: 44,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: channel.logo,
                                            httpHeaders: ApiClient().getStalkerHeaders(),
                                            fit: BoxFit.contain,
                                            errorWidget: (_, __, ___) => const Icon(
                                              Icons.tv_rounded,
                                              color: Colors.white24,
                                              size: 18,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.tv_rounded, color: Colors.white24),
                                  title: Text(
                                    channel.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.white30,
                                    size: 14,
                                  ),
                                  onTap: () {
                                    _showCatchupGuideBottomSheet(context, channel);
                                  },
                                );
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
          },
        );
      },
    );
  }

  Widget _buildContinueWatchingRow(BuildContext context) {
    final continueWatchingList = ref.watch(continueWatchingProvider);
    final items = continueWatchingList.take(12).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return FadeInUp(
      duration: const Duration(milliseconds: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'CONTINUE WATCHING',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final metadata = item['metadata'] as Map<String, dynamic>;
                final title = metadata['title']?.toString() ?? 'Unknown';
                final subtitle = metadata['subtitle']?.toString() ?? '';
                final poster = metadata['poster']?.toString() ?? '';
                final progress = item['progress'] as int? ?? 0;
                final duration = item['duration'] as int? ?? 0;
                final pct = duration > 0 ? (progress / duration).clamp(0.0, 1.0) : 0.0;
                final contentId = item['contentId']?.toString() ?? '';

                return _ContinueWatchingCard(
                  title: title,
                  subtitle: subtitle,
                  poster: poster,
                  progressPercent: pct,
                  onTap: () => _playContinueWatching(item),
                  onRemove: () async {
                    await ref.read(continueWatchingProvider.notifier).remove(contentId);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _playContinueWatching(Map<String, dynamic> item) async {
    final metadata = item['metadata'] as Map<String, dynamic>;
    final contentType = metadata['contentType']?.toString() ?? 'vod';
    final contentId = item['contentId']?.toString() ?? '';
    final title = metadata['title']?.toString() ?? '';
    final subtitle = metadata['subtitle']?.toString() ?? '';
    final poster = metadata['poster']?.toString() ?? '';
    final videoId = metadata['videoId']?.toString() ?? '';
    final originalCmd = metadata['originalCmd']?.toString() ?? '';
    final seriesId = metadata['seriesId']?.toString() ?? '';
    final currentEpisodeIndex = metadata['currentEpisodeIndex'] as int?;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      String streamUrl = '';
      List<SubtitleInfo> externalSubtitles = const [];

      if (contentType == 'vod') {
        final moviesService = ref.read(moviesServiceProvider);
        final movie = VodItem(
          id: videoId,
          name: title,
          cmd: originalCmd,
          poster: poster,
        );
        streamUrl = await moviesService.createVodLink(movie);
        externalSubtitles = moviesService.lastResolvedSubtitles;
      } else if (contentType == 'series') {
        final stalkerApi = ref.read(stalkerApiProvider);
        String cmd = originalCmd;
        String? directUrl;

        if (cmd.isNotEmpty && !cmd.startsWith('http') && !cmd.startsWith('rtsp') && !cmd.startsWith('/media/file_')) {
          final response = await stalkerApi.resolveEpisodeFileResponse(
            seriesId: videoId,
            episodeId: seriesId,
            seasonId: '',
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

        if (cmd.startsWith('http://') || cmd.startsWith('https://') || cmd.startsWith('rtsp://')) {
          streamUrl = cmd;
        } else {
          try {
            streamUrl = await stalkerApi.createLink(
              cmd,
              AppConfig.typeSeries,
              seriesId: seriesId,
              parentSeriesId: videoId,
            );
            externalSubtitles = stalkerApi.lastResolvedSubtitles;
          } catch (e) {
            if (directUrl != null && directUrl.isNotEmpty) {
              streamUrl = directUrl;
            } else {
              rethrow;
            }
          }
        }
      } else {
        streamUrl = metadata['streamUrl']?.toString() ?? '';
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: title,
          subtitle: subtitle.isNotEmpty ? subtitle : null,
          contentId: contentId,
          videoId: videoId,
          originalCmd: originalCmd,
          contentType: contentType,
          seriesId: seriesId.isNotEmpty ? seriesId : null,
          currentEpisodeIndex: currentEpisodeIndex,
          externalSubtitles: externalSubtitles,
          poster: poster,
        ),
      )).then((_) {
        if (mounted) {
          ref.read(continueWatchingProvider.notifier).refresh();
        }
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resume: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showFavoritesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return DefaultTabController(
              length: 3,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.star_rounded, color: Colors.amber, size: 26),
                          SizedBox(width: 12),
                          Text(
                            'My Favourites',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const TabBar(
                      indicatorColor: AppColors.primary,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      dividerColor: AppColors.border,
                      tabs: [
                        Tab(icon: Icon(Icons.live_tv_rounded), text: 'Live TV'),
                        Tab(icon: Icon(Icons.movie_rounded), text: 'Movies'),
                        Tab(icon: Icon(Icons.tv_rounded), text: 'Series'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFavTab<Channel>(
                            scrollController: scrollController,
                            type: 'channels',
                            emptyText: 'No favorite channels added yet.',
                            itemBuilder: (item) {
                              return ListTile(
                                leading: item.logo.isNotEmpty
                                    ? Container(
                                        width: 44,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: item.logo,
                                          httpHeaders: ApiClient().getStalkerHeaders(),
                                          fit: BoxFit.contain,
                                          errorWidget: (_, __, ___) => const Icon(
                                            Icons.tv_rounded,
                                            color: Colors.white24,
                                            size: 18,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.tv_rounded, color: Colors.white24),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onChannelTap?.call(item);
                                },
                              );
                            },
                          ),
                          _buildFavTab<VodItem>(
                            scrollController: scrollController,
                            type: 'movies',
                            emptyText: 'No favorite movies added yet.',
                            itemBuilder: (item) {
                              return ListTile(
                                leading: item.poster.isNotEmpty
                                    ? Container(
                                        width: 36,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: item.poster,
                                          httpHeaders: ApiClient().getStalkerHeaders(),
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => const Icon(
                                            Icons.movie_rounded,
                                            color: Colors.white24,
                                            size: 18,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.movie_rounded, color: Colors.white24),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  item.year,
                                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onMovieTap?.call(item);
                                },
                              );
                            },
                          ),
                          _buildFavTab<SeriesItem>(
                            scrollController: scrollController,
                            type: 'series',
                            emptyText: 'No favorite series added yet.',
                            itemBuilder: (item) {
                              return ListTile(
                                leading: item.poster.isNotEmpty
                                    ? Container(
                                        width: 36,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: CachedNetworkImage(
                                          imageUrl: item.poster,
                                          httpHeaders: ApiClient().getStalkerHeaders(),
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => const Icon(
                                            Icons.tv_rounded,
                                            color: Colors.white24,
                                            size: 18,
                                          ),
                                        ),
                                      )
                                    : const Icon(Icons.tv_rounded, color: Colors.white24),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  item.year,
                                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSeriesTap?.call(item);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFavTab<T>({
    required ScrollController scrollController,
    required String type,
    required String emptyText,
    required Widget Function(T item) itemBuilder,
  }) {
    return Consumer(
      builder: (context, ref, child) {
        final favorites = ref.watch(favoritesProvider);
        final favIds = favorites[type] ?? {};

        if (favIds.isEmpty) {
          return Center(
            child: Text(
              emptyText,
              style: const TextStyle(color: Colors.white30),
            ),
          );
        }

        if (type == 'channels') {
          final channels = ref.watch(allChannelsProvider).value ?? [];
          final favChannels = channels.where((c) => favIds.contains(c.id)).toList();
          return _buildFavList<Channel>(scrollController, favChannels, itemBuilder as Widget Function(Channel));
        } else if (type == 'movies') {
          final movies = ref.watch(moviesProvider(null)).value ?? [];
          final favMovies = movies.where((m) => favIds.contains(m.id)).toList();
          return _buildFavList<VodItem>(scrollController, favMovies, itemBuilder as Widget Function(VodItem));
        } else {
          final series = ref.watch(seriesProvider(null)).value ?? [];
          final favSeries = series.where((s) => favIds.contains(s.id)).toList();
          return _buildFavList<SeriesItem>(scrollController, favSeries, itemBuilder as Widget Function(SeriesItem));
        }
      },
    );
  }

  Widget _buildFavList<T>(ScrollController controller, List<T> items, Widget Function(T item) itemBuilder) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Favorites loading or unavailable.',
          style: TextStyle(color: Colors.white24),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) => itemBuilder(items[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Watching counts for indicators
    final channels = ref.watch(allChannelsProvider);
    final movies = ref.watch(moviesProvider(null));
    final series = ref.watch(seriesProvider(null));

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
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
        child: SafeArea(
          child: Column(
            children: [
              // ─── SFLIXTV Header / Top Bar ────────
              FadeInDown(
                duration: const Duration(milliseconds: 400),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    border: const Border(
                      bottom: BorderSide(color: AppColors.divider, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      // App logo & title
                      Image.asset(
                        'assets/images/icon.png',
                        width: 32,
                        height: 32,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        AppStrings.appName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          authState.authType.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Middle: Server details & time info (Only if not too compact)
                      if (!isCompact) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('MMM dd, yyyy').format(_now),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              DateFormat('hh:mm a').format(_now),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Container(width: 1, height: 28, color: AppColors.divider),
                        const SizedBox(width: 20),
                      ],

                      // Right: Expiry, Server & Settings Icon
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vpn_key_rounded, size: 12, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(
                                _getUserDisplay(authState),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Expiry: ${_getExpirationText(authState)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 18),
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ProfileScreen(onLogout: widget.onLogout),
                          ));
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Main Grid Contents (Landscape Responsive Row of 4 Flex Cards) ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      _buildContinueWatchingRow(context),
                      FadeInUp(
                        duration: const Duration(milliseconds: 500),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double cardHeight = isCompact ? 130 : 170;

                            final liveCard = DashboardCard(
                              title: 'LIVE TV',
                              subtitle: channels.when(
                                data: (list) => '${list.length} Channels',
                                loading: () => 'Loading...',
                                error: (_, __) => 'Manage Live TV',
                              ),
                              imageAsset: 'assets/images/live-stream.png',
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => LiveTvScreen(onChannelTap: widget.onChannelTap),
                                )).then((_) {
                                  if (mounted) {
                                    ref.read(continueWatchingProvider.notifier).refresh();
                                  }
                                });
                              },
                              height: cardHeight,
                              autoFocus: true,
                            );

                            final moviesCard = DashboardCard(
                              title: 'Movies',
                              subtitle: movies.when(
                                data: (list) => '${list.length} Movies',
                                loading: () => 'Loading...',
                                error: (_, __) => 'Watch Movies',
                              ),
                              imageAsset: 'assets/images/film-reel.png',
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => MoviesScreen(onMovieTap: widget.onMovieTap),
                                )).then((_) {
                                  if (mounted) {
                                    ref.read(continueWatchingProvider.notifier).refresh();
                                  }
                                });
                              },
                              height: cardHeight,
                            );

                            final seriesCard = DashboardCard(
                              title: 'Series',
                              subtitle: series.when(
                                data: (list) => '${list.length} Series',
                                loading: () => 'Loading...',
                                error: (_, __) => 'Watch Series',
                              ),
                              imageAsset: 'assets/images/clapperboard.png',
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => SeriesScreen(onSeriesTap: widget.onSeriesTap),
                                )).then((_) {
                                  if (mounted) {
                                    ref.read(continueWatchingProvider.notifier).refresh();
                                  }
                                });
                              },
                              height: cardHeight,
                            );

                            final settingsColumn = Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                DashboardSmallCard(
                                  title: 'EPG Guide',
                                  icon: Icons.calendar_view_day_rounded,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => LiveTvScreen(onChannelTap: widget.onChannelTap),
                                    ));
                                  },
                                ),
                                DashboardSmallCard(
                                  title: 'Favourites',
                                  icon: Icons.favorite_rounded,
                                  onTap: () => _showFavoritesBottomSheet(context),
                                ),
                                DashboardSmallCard(
                                  title: 'Catch Up',
                                  icon: Icons.history_rounded,
                                  onTap: () => _showCatchupChannelsBottomSheet(context),
                                ),
                                DashboardSmallCard(
                                  title: 'Search Content',
                                  icon: Icons.search_rounded,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => SearchScreen(
                                        onChannelTap: widget.onChannelTap,
                                        onMovieTap: widget.onMovieTap,
                                        onSeriesTap: widget.onSeriesTap,
                                      ),
                                    ));
                                  },
                                ),
                              ],
                            );

                            final settingsColumnCompact = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DashboardSmallCard(
                                  title: 'EPG Guide',
                                  icon: Icons.calendar_view_day_rounded,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => LiveTvScreen(onChannelTap: widget.onChannelTap),
                                    ));
                                  },
                                ),
                                const SizedBox(height: 8),
                                DashboardSmallCard(
                                  title: 'Favourites',
                                  icon: Icons.favorite_rounded,
                                  onTap: () => _showFavoritesBottomSheet(context),
                                ),
                                const SizedBox(height: 8),
                                DashboardSmallCard(
                                  title: 'Catch Up',
                                  icon: Icons.history_rounded,
                                  onTap: () => _showCatchupChannelsBottomSheet(context),
                                ),
                                const SizedBox(height: 8),
                                DashboardSmallCard(
                                  title: 'Search Content',
                                  icon: Icons.search_rounded,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => SearchScreen(
                                        onChannelTap: widget.onChannelTap,
                                        onMovieTap: widget.onMovieTap,
                                        onSeriesTap: widget.onSeriesTap,
                                      ),
                                    ));
                                  },
                                ),
                              ],
                            );

                            if (isCompact) {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: liveCard),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(child: moviesCard),
                                      const SizedBox(width: 16),
                                      Expanded(child: seriesCard),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  settingsColumnCompact,
                                ],
                              );
                            } else {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 2, child: liveCard),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 2, child: moviesCard),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 2, child: seriesCard),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: cardHeight,
                                      child: settingsColumn,
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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

/// A premium flat grid card for the SFLIXTV dashboard.
class DashboardCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String imageAsset;
  final VoidCallback onTap;
  final double height;
  final bool autoFocus;

  const DashboardCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.onTap,
    this.height = 170,
    this.autoFocus = false,
  });

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = _isFocused || _isHovered;
    return Focus(
      autofocus: widget.autoFocus,
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: isSelected ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: widget.height,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                ],
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.06),
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: Opacity(
                      opacity: 0.05,
                      child: Image.asset(
                        widget.imageAsset,
                        width: widget.height * 0.7,
                        height: widget.height * 0.7,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Center(
                          child: Image.asset(
                            widget.imageAsset,
                            width: widget.height * 0.35,
                            height: widget.height * 0.35,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '◍ ',
                              style: TextStyle(color: AppColors.primary, fontSize: 10),
                            ),
                            Text(
                              widget.subtitle,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small vertical settings card for the SFLIXTV dashboard.
class DashboardSmallCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const DashboardSmallCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  State<DashboardSmallCard> createState() => _DashboardSmallCardState();
}

class _DashboardSmallCardState extends State<DashboardSmallCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = _isFocused || _isHovered;
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: isSelected ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.04) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const RadialGradient(
                        colors: [
                          AppColors.surfaceLight,
                          AppColors.surface,
                        ],
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 6,
                          ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 14,
                        color: isSelected ? AppColors.primary : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String poster;
  final double progressPercent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ContinueWatchingCard({
    required this.title,
    required this.subtitle,
    required this.poster,
    required this.progressPercent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 105,
            margin: const EdgeInsets.only(right: 14, bottom: 6, top: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? AppColors.primary : Colors.white10,
                width: 1.5,
              ),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(7),
                          topRight: Radius.circular(7),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            widget.poster.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: widget.poster,
                                    httpHeaders: ApiClient().getStalkerHeaders(),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Center(
                                      child: Icon(Icons.movie_outlined, color: Colors.white24, size: 24),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.movie_outlined, color: Colors.white24, size: 24),
                                  ),
                            if (isActive)
                              Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    LinearProgressIndicator(
                      value: widget.progressPercent,
                      backgroundColor: Colors.white10,
                      color: AppColors.primary,
                      minHeight: 3,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle.isNotEmpty ? widget.subtitle : 'Resume Playback',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
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
