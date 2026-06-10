import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show SubtitleInfo;
import '../../series/domain/models.dart' show Episode;
import '../../../core/network/opensubtitles_service.dart' show OpenSubtitleItem, OpenSubtitleFile;
import '../../../core/utils/stalker_parser.dart';
import '../../../core/config/app_config.dart';

/// Premium video player screen with subtitle, audio, quality selection,
/// volume/brightness gestures, playback speed, and lock mode.
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;
  final String? subtitle;
  final String? contentId;
  final String? videoId;
  final String? originalCmd;
  final String? contentType;
  final String? seriesId;
  final List<Episode>? episodes;
  final int? currentEpisodeIndex;
  final List<SubtitleInfo> externalSubtitles;
  final String? poster;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle,
    this.contentId,
    this.videoId,
    this.originalCmd,
    this.contentType,
    this.seriesId,
    this.episodes,
    this.currentEpisodeIndex,
    this.externalSubtitles = const [],
    this.poster,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  final _logger = AppLogger();

  // UI state
  bool _showControls = true;
  bool _isLocked = false;
  bool _isBuffering = true;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _hideTimer;
  Timer? _loadingTimeoutTimer;

  // Playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = false;
  bool _isCompleted = false;
  double _playbackSpeed = 1.0;

  // Tracks
  List<SubtitleTrack> _subtitleTracks = [];
  SubtitleTrack? _activeSubtitleTrack;
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _activeAudioTrack;
  List<VideoTrack> _videoTracks = [];
  VideoTrack? _activeVideoTrack;

  // Gesture state
  bool _isDraggingSeek = false;
  double _dragSeekValue = 0;
  bool _showVolumeSlider = false;
  bool _showBrightnessSlider = false;
  double _currentVolume = 100;
  double _currentBrightness = 0.5;
  Timer? _gestureHideTimer;

  // Fit mode
  BoxFit _videoFit = BoxFit.contain;

  // Scale / Zoom gesture states
  bool _scaleTriggered = false;
  bool _showFitToast = false;
  String _fitToastText = '';
  Timer? _fitToastTimer;

  // Double-tap animation
  bool _showRewindRipple = false;
  bool _showForwardRipple = false;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Mutable state variables from widget parameters
  late String _currentStreamUrl;
  late String _title;
  String? _subtitle;
  String? _contentId;
  String? _videoId;
  String? _originalCmd;
  int? _currentEpisodeIndex;
  List<SubtitleInfo> _externalSubtitles = [];
  String? _poster;

  // Aspect ratio state
  String _aspectRatioMode = 'Fit'; // 'Fit', '16:9', '4:3', 'Zoom'

  // Subtitle custom design states
  double _subtitleSize = 32.0;
  Color _subtitleColor = Colors.white;
  Color _subtitleBgColor = const Color(0x88000000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Initialize mutable states from widget properties
    _currentStreamUrl = widget.streamUrl;
    _title = widget.title;
    _subtitle = widget.subtitle;
    _contentId = widget.contentId;
    _videoId = widget.videoId;
    _originalCmd = widget.originalCmd;
    _currentEpisodeIndex = widget.currentEpisodeIndex;
    _externalSubtitles = widget.externalSubtitles;
    _poster = widget.poster;

    _initPlayer();
  }



  String _parsePlayerError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('403') || lower.contains('unauthorized')) {
      return 'Access denied (HTTP 403). Your subscription may have expired or does not support this stream.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Stream not found (HTTP 404). The channel or content may have been removed.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Connection timed out. The server took too long to respond.';
    }
    if (lower.contains('socket') || lower.contains('connection refused') || lower.contains('network')) {
      return 'Network error. Please check your internet connection or portal status.';
    }
    return 'Playback failed: $error';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _initPlayer({bool withHeaders = true}) async {
    _logger.player('Initializing media_kit player: $_currentStreamUrl');
    try {
      // Build MAG session headers (used for Stalker portal streams)
      Map<String, String> headers = {};
      if (withHeaders) {
        final apiClient = ref.read(apiClientProvider);
        headers = {
          'User-Agent':
              'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
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
        headers['Cookie'] =
            cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
        _logger.player('Using authenticated MAG session headers');
      } else {
        _logger.player('Retrying without custom headers (CDN fallback)');
      }

      // Create fresh player instance (safe for retry)
      final player = Player();
      final videoController = VideoController(player);
      _player = player;
      _videoController = videoController;

      // Start connection loading timeout
      _loadingTimeoutTimer?.cancel();
      _loadingTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && (_isBuffering || !_isPlaying) && !_hasError) {
          _logger.player('Playback initialization timed out after 15 seconds.');
          setState(() {
            _hasError = true;
            _errorMessage = 'Connection timed out. The stream may be offline or unstable.';
            _isBuffering = false;
          });
        }
      });

      // Subscribe to streams
      _subscriptions.add(player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (playing) {
              _isBuffering = false;
              _loadingTimeoutTimer?.cancel(); // Cancel timeout on play start
            }
            if (!playing) _showControls = true;
          });
          _startHideTimer();
        }
      }));
      _subscriptions.add(player.stream.position.listen((pos) {
        if (mounted && !_isDraggingSeek) setState(() => _position = pos);
        // Save watch progress periodically
        if (_contentId != null && _isPlaying) {
          final prefs = ref.read(preferencesProvider);
          prefs.saveWatchProgress(_contentId!, pos.inMilliseconds);
        }
      }));
      _subscriptions.add(player.stream.duration.listen((dur) {
        if (mounted) {
          setState(() => _duration = dur);
          if (_contentId != null && dur > Duration.zero) {
            final prefs = ref.read(preferencesProvider);
            prefs.saveWatchDuration(_contentId!, dur.inMilliseconds);
          }
        }
      }));
      _subscriptions.add(player.stream.buffer.listen((buf) {
        if (mounted) setState(() => _buffer = buf);
      }));
      _subscriptions.add(player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
            if (buffering) _showControls = true;
          });
          _startHideTimer();
        }
      }));
      _subscriptions.add(player.stream.completed.listen((completed) {
        if (mounted) setState(() => _isCompleted = completed);
      }));
      _subscriptions.add(player.stream.volume.listen((vol) {
        if (mounted) setState(() => _currentVolume = vol);
      }));
      _subscriptions.add(player.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          _logger.player('Playback error: $error');
          _loadingTimeoutTimer?.cancel(); // Cancel timeout on error
          // If first attempt with headers failed, auto-retry without headers
          if (withHeaders) {
            _logger.player('Header-based playback failed — retrying without custom headers...');
            _restartPlayer(withHeaders: false);
          } else {
            setState(() {
              _hasError = true;
              _errorMessage = _parsePlayerError(error);
            });
          }
        }
      }));

      // Track streams
      _subscriptions.add(player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _subtitleTracks = tracks.subtitle;
            _audioTracks = tracks.audio;
            _videoTracks = tracks.video;
          });
        }
      }));
      _subscriptions.add(player.stream.track.listen((track) {
        if (mounted) {
          setState(() {
            _activeSubtitleTrack = track.subtitle;
            _activeAudioTrack = track.audio;
            _activeVideoTrack = track.video;
          });
        }
      }));

      // Open media
      await player.open(
        Media(_currentStreamUrl, httpHeaders: headers.isEmpty ? null : headers),
      );

      if (mounted) {
        setState(() => _isBuffering = false);
      }

      _logger.player('Player initialized successfully');
      _startHideTimer();

      // Telemetry start
      if (_videoId != null && _originalCmd != null) {
        ref.read(stalkerApiProvider).logStartPlay(
              videoId: _videoId!,
              cmd: _originalCmd!,
              resolvedUrl: _currentStreamUrl,
            );
      }

      // Restore watch progress
      if (_contentId != null) {
        final prefs = ref.read(preferencesProvider);
        final progress = prefs.getWatchProgress(_contentId!);
        if (progress > 0) {
          player.seek(Duration(milliseconds: progress));
        }

        // Save watch progress metadata
        final metadata = {
          'contentId': _contentId,
          'title': _title,
          'subtitle': _subtitle,
          'poster': _poster ?? '',
          'contentType': widget.contentType ?? 'vod',
          'videoId': _videoId,
          'originalCmd': _originalCmd,
          'seriesId': widget.seriesId,
          'currentEpisodeIndex': _currentEpisodeIndex,
          'streamUrl': _currentStreamUrl,
        };
        try {
          prefs.saveWatchMetadata(_contentId!, jsonEncode(metadata));
        } catch (e) {
          _logger.player('Failed to save watch metadata: $e');
        }
      }
    } catch (e) {
      _logger.player('Player init failed', error: e);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _showControlsTemporary() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  Future<void> _playEpisodeAtIndex(int index) async {
    if (widget.episodes == null || index < 0 || index >= widget.episodes!.length) return;
    final ep = widget.episodes![index];
    
    setState(() {
      _isBuffering = true;
      _hasError = false;
      _errorMessage = null;
      _showControls = true;
    });

    try {
      _player?.stop();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _loadingTimeoutTimer?.cancel();

      final stalkerApi = ref.read(stalkerApiProvider);
      String cmd = ep.cmd;
      
      String? directUrl;
      if (!cmd.startsWith('http') && !cmd.startsWith('rtsp') && !cmd.startsWith('/media/file_')) {
        final parentId = _videoId ?? '';
        if (parentId.isNotEmpty) {
          final episodeId = ep.id;
          final seasonId = ep.rawJson?['season_id']?.toString() ?? '';
          final listRes = await stalkerApi.resolveEpisodeFileResponse(
            seriesId: parentId,
            episodeId: episodeId,
            seasonId: seasonId,
          );
          final listJs = listRes['js'];
          if (listJs != null && listJs != false) {
            final rawList = StalkerParser.extractList(listJs is Map ? listJs['data'] ?? listJs : listJs);
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
      }

      String streamUrl = '';
      List<SubtitleInfo> subtitles = [];

      if (cmd.startsWith('http://') || cmd.startsWith('https://') || cmd.startsWith('rtsp://')) {
        streamUrl = cmd;
      } else {
        try {
          streamUrl = await stalkerApi.createLink(
            cmd,
            AppConfig.typeSeries,
            seriesId: ep.seriesNumber.isNotEmpty ? ep.seriesNumber : ep.id,
            itemObject: ep.rawJson,
            parentSeriesId: _videoId,
          );
          subtitles = stalkerApi.lastResolvedSubtitles;
        } catch (e) {
          if (directUrl != null && directUrl.isNotEmpty) {
            _logger.player('createLink failed. Falling back to direct URL: $directUrl');
            streamUrl = directUrl;
          } else {
            rethrow;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _currentEpisodeIndex = index;
        _currentStreamUrl = streamUrl;
        _subtitle = ep.name;
        _contentId = 'ep_${ep.id}';
        _originalCmd = cmd;
        _externalSubtitles = subtitles;
      });

      _initPlayer();
    } catch (e) {
      if (!mounted) return;
      _logger.player('Failed to play episode', error: e);
      setState(() {
        _hasError = true;
        _errorMessage = _parsePlayerError(e.toString());
        _isBuffering = false;
      });
    }
  }

  /// Safely disposes the current player + subscriptions, then re-initializes.
  void _restartPlayer({bool withHeaders = true}) {
    if (!mounted) return;
    // Cancel all existing stream subscriptions first
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    // Stop + dispose old player
    try {
      _player?.stop();
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _videoController = null;
    // Reset state then reinitialize
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
      _isPlaying = false;
      _isCompleted = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffer = Duration.zero;
    });
    _initPlayer(withHeaders: withHeaders);
  }

  /// Called by every exit path (back button, hardware back, gesture).
  /// Stops the player SYNCHRONOUSLY before the route is popped so that
  /// media_kit's native engine is shut down before Dart GC runs.
  void _closePlayer() {
    // Kill audio immediately — don't wait for dispose()
    try {
      _player?.stop();
    } catch (_) {}
    // Cancel subscriptions so no more state updates fire after pop
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _loadingTimeoutTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isPlaying || _isBuffering || _isDraggingSeek) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_isDraggingSeek && !_isBuffering) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      if (_showControls) _startHideTimer();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _seek(int seconds) {
    final pos = _position + Duration(seconds: seconds);
    _player?.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  void _togglePlayPause() {
    _player?.playOrPause();
    if (!_isPlaying) _startHideTimer();
  }

  void _setPlaybackSpeed(double speed) {
    _player?.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  void _cycleVideoFit({required bool isZoomIn}) {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = isZoomIn ? BoxFit.cover : BoxFit.fill;
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = isZoomIn ? BoxFit.fill : BoxFit.contain;
      } else {
        _videoFit = isZoomIn ? BoxFit.contain : BoxFit.cover;
      }
    });
    _triggerFitToast();
  }

  void _triggerFitToast() {
    _fitToastTimer?.cancel();
    String modeName = 'Fit to Screen';
    if (_videoFit == BoxFit.cover) {
      modeName = 'Fill Screen';
    } else if (_videoFit == BoxFit.fill) {
      modeName = 'Stretch Screen';
    }
    setState(() {
      _fitToastText = modeName;
      _showFitToast = true;
    });
    _fitToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showFitToast = false);
      }
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleTriggered = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isLocked || _scaleTriggered) return;
    if (details.scale > 1.35) {
      _scaleTriggered = true;
      _cycleVideoFit(isZoomIn: true);
    } else if (details.scale < 0.65) {
      _scaleTriggered = true;
      _cycleVideoFit(isZoomIn: false);
    }
  }

  // ─── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fullPlayer = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is KeyDownEvent) {
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.arrowLeft) {
                _seek(-10);
                _showControlsTemporary();
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.arrowRight) {
                _seek(10);
                _showControlsTemporary();
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space) {
                _togglePlayPause();
                _showControlsTemporary();
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.arrowDown) {
                _showControlsTemporary();
                return KeyEventResult.handled;
              } else if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.backspace) {
                _closePlayer();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: _toggleControls,
            onDoubleTapDown: _isLocked ? null : _onDoubleTap,
            onVerticalDragStart: _isLocked ? null : _onVerticalDragStart,
            onVerticalDragUpdate: _isLocked ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: _isLocked ? null : _onVerticalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
              // ─── Video ───
              _hasError
                  ? _buildErrorView()
                  : GestureDetector(
                      onScaleStart: _isLocked ? null : _onScaleStart,
                      onScaleUpdate: _isLocked ? null : _onScaleUpdate,
                      child: _buildVideoView(),
                    ),

              // ─── Buffering indicator ───
              if (_isBuffering && !_hasError)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),

              // ─── Controls ───
              if (_showControls && !_hasError) ...[
                if (_isLocked) _buildLockedOverlay() else ...[
                  _buildTopBar(),
                  _buildCenterControls(),
                  _buildBottomBar(),
                ],
              ],

              // ─── Volume/Brightness indicators ───
              if (_showVolumeSlider) _buildVerticalIndicator(
                icon: _currentVolume == 0
                    ? Icons.volume_off_rounded
                    : _currentVolume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                value: _currentVolume / 100,
                label: '${_currentVolume.round()}%',
                isLeft: true,
              ),
              if (_showBrightnessSlider) _buildVerticalIndicator(
                icon: Icons.brightness_6_rounded,
                value: _currentBrightness,
                label: '${(_currentBrightness * 100).round()}%',
                isLeft: false,
              ),

              // ─── Double-tap ripples ───
              if (_showRewindRipple) _buildDoubleTapRipple(isLeft: true),
              if (_showForwardRipple) _buildDoubleTapRipple(isLeft: false),

              // ─── Fit Mode Toast ───
              if (_showFitToast)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.aspect_ratio_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _fitToastText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );

    return fullPlayer;
  }

  // ─── Video View ──────────────────────────────────────

  Widget _buildVideoView() {
    final vc = _videoController;
    if (vc == null) return const SizedBox.shrink();

    BoxFit fit = BoxFit.contain;
    if (_aspectRatioMode == 'Zoom') {
      fit = BoxFit.cover;
    } else if (_aspectRatioMode == '16:9' || _aspectRatioMode == '4:3') {
      fit = BoxFit.fill;
    }

    Widget videoWidget = Video(
      controller: vc,
      fit: fit,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        style: TextStyle(
          fontSize: _subtitleSize,
          color: _subtitleColor,
          backgroundColor: _subtitleBgColor,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.only(bottom: 80),
      ),
      controls: NoVideoControls,
    );

    if (_aspectRatioMode == '16:9') {
      videoWidget = AspectRatio(
        aspectRatio: 16 / 9,
        child: videoWidget,
      );
    } else if (_aspectRatioMode == '4:3') {
      videoWidget = AspectRatio(
        aspectRatio: 4 / 3,
        child: videoWidget,
      );
    }

    return Center(child: videoWidget);
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('Playback Failed',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _errorMessage ?? 'Unknown error',
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 13),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPillButton(Icons.arrow_back_rounded, 'Go Back', () {
                Navigator.of(context).pop();
              }),
              const SizedBox(width: 12),
              _buildPillButton(Icons.refresh_rounded, 'Retry', () {
                _restartPlayer(withHeaders: true);
              }, isPrimary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton(IconData icon, String label, VoidCallback onTap,
      {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : AppColors.glassBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isPrimary ? AppColors.primary : AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ─── Top Bar ────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              4, MediaQuery.of(context).padding.top + 4, 4, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xDD000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 24),
                onPressed: _closePlayer,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_subtitle != null)
                      Text(
                        _subtitle!,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                  ],
                ),
              ),
              // Fit toggle
              IconButton(
                icon: Icon(
                  _videoFit == BoxFit.contain
                      ? Icons.fit_screen_rounded
                      : Icons.crop_free_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _videoFit = _videoFit == BoxFit.contain
                        ? BoxFit.cover
                        : BoxFit.contain;
                  });
                },
                tooltip:
                    _videoFit == BoxFit.contain ? 'Fill Screen' : 'Fit Screen',
              ),
              // Lock
              IconButton(
                icon: const Icon(Icons.lock_outline_rounded,
                    color: Colors.white70, size: 22),
                onPressed: () {
                  setState(() => _isLocked = true);
                  _startHideTimer();
                },
                tooltip: 'Lock Controls',
              ),
              // Settings
              IconButton(
                icon: const Icon(Icons.settings_rounded,
                    color: Colors.white70, size: 22),
                onPressed: _showSettingsSheet,
                tooltip: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Center Controls ───────────────────────────────

  Widget _buildCenterControls() {
    return Center(
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rewind
            _buildControlButton(
              Icons.replay_10_rounded,
              () => _seek(-10),
              size: 40,
            ),
            const SizedBox(width: 32),
            // Play/Pause
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    _isCompleted
                        ? Icons.replay_rounded
                        : _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                    key: ValueKey(_isPlaying),
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Forward
            _buildControlButton(
              Icons.forward_10_rounded,
              () => _seek(10),
              size: 40,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap,
      {double size = 32}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }

  // ─── Bottom Bar ─────────────────────────────────────

  Widget _buildBottomBar() {
    final posMs = _position.inMilliseconds.toDouble();
    final durMs = _duration.inMilliseconds.toDouble();
    final bufMs = _buffer.inMilliseconds.toDouble();
    final seekVal = _isDraggingSeek ? _dragSeekValue : posMs;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xDD000000), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: Colors.white12,
                  secondaryActiveTrackColor: Colors.white24,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: seekVal.clamp(0.0, durMs > 0 ? durMs : 1.0),
                  secondaryTrackValue:
                      bufMs.clamp(0.0, durMs > 0 ? durMs : 1.0),
                  min: 0,
                  max: durMs > 0 ? durMs : 1.0,
                  onChangeStart: (_) {
                    setState(() => _isDraggingSeek = true);
                    _hideTimer?.cancel();
                  },
                  onChanged: (val) {
                    setState(() => _dragSeekValue = val);
                  },
                  onChangeEnd: (val) {
                    _player?.seek(Duration(milliseconds: val.round()));
                    setState(() => _isDraggingSeek = false);
                    _startHideTimer();
                  },
                ),
              ),
              // Time + speed
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(
                      _isDraggingSeek
                          ? _formatDuration(
                              Duration(milliseconds: _dragSeekValue.round()))
                          : _formatDuration(_position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const Text(' / ',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    // Select Episodes button (if episodes is not empty)
                    if (widget.episodes != null && widget.episodes!.isNotEmpty) ...[
                      GestureDetector(
                        onTap: _showEpisodesDrawer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.glassBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Episodes',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Next Episode button
                    if (widget.episodes != null && _currentEpisodeIndex != null && _currentEpisodeIndex! + 1 < widget.episodes!.length) ...[
                      GestureDetector(
                        onTap: () => _playEpisodeAtIndex(_currentEpisodeIndex! + 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.glassBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.skip_next_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Next Ep',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Aspect Ratio Button
                    GestureDetector(
                      onTap: _cycleAspectRatio,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.glassBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _aspectRatioMode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Playback speed
                    GestureDetector(
                      onTap: _showSpeedSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.glassBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Locked Overlay ─────────────────────────────────

  Widget _buildLockedOverlay() {
    return Center(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isLocked = false;
            _showControls = true;
          });
          _startHideTimer();
        },
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xAA000000),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Tap to Unlock',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Volume / Brightness Indicator ──────────────────

  Widget _buildVerticalIndicator({
    required IconData icon,
    required double value,
    required String label,
    required bool isLeft,
  }) {
    return Positioned(
      left: isLeft ? 24 : null,
      right: isLeft ? null : 24,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          width: 44,
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xCC111111),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 8),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Double Tap Ripple ──────────────────────────────

  Widget _buildDoubleTapRipple({required bool isLeft}) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: MediaQuery.of(context).size.width / 3,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: isLeft
                ? Alignment.centerLeft
                : Alignment.centerRight,
            radius: 0.8,
            colors: [
              Colors.white.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLeft
                    ? Icons.fast_rewind_rounded
                    : Icons.fast_forward_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 4),
              Text(
                isLeft ? '−10s' : '+10s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Gestures ───────────────────────────────────────

  void _onDoubleTap(TapDownDetails details) {
    final w = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < w / 3) {
      _seek(-10);
      setState(() => _showRewindRipple = true);
      Future.delayed(const Duration(milliseconds: 600),
          () => mounted ? setState(() => _showRewindRipple = false) : null);
    } else if (details.globalPosition.dx > w * 2 / 3) {
      _seek(10);
      setState(() => _showForwardRipple = true);
      Future.delayed(const Duration(milliseconds: 600),
          () => mounted ? setState(() => _showForwardRipple = false) : null);
    }
  }

  double? _dragStartY;
  bool? _isDragLeft;

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    final w = MediaQuery.of(context).size.width;
    _isDragLeft = details.globalPosition.dx < w / 2;
    _gestureHideTimer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dragStartY == null || _isDragLeft == null) return;
    final delta = (_dragStartY! - details.globalPosition.dy) / 300;

    if (_isDragLeft!) {
      // Volume
      final newVol = (_currentVolume + delta * 100).clamp(0.0, 100.0);
      _player?.setVolume(newVol);
      setState(() {
        _currentVolume = newVol;
        _showVolumeSlider = true;
      });
    } else {
      // Brightness
      final newBright = (_currentBrightness + delta).clamp(0.0, 1.0);
      setState(() {
        _currentBrightness = newBright;
        _showBrightnessSlider = true;
      });
    }
    _dragStartY = details.globalPosition.dy;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _gestureHideTimer?.cancel();
    _gestureHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showVolumeSlider = false;
          _showBrightnessSlider = false;
        });
      }
    });
  }

  // ─── Aspect Ratio Cycling ───────────────────────────

  void _cycleAspectRatio() {
    final modes = ['Fit', '16:9', '4:3', 'Zoom'];
    final idx = modes.indexOf(_aspectRatioMode);
    final nextIdx = (idx + 1) % modes.length;
    setState(() {
      _aspectRatioMode = modes[nextIdx];
    });
    _triggerAspectRatioToast();
  }

  void _triggerAspectRatioToast() {
    _fitToastTimer?.cancel();
    setState(() {
      _fitToastText = 'Aspect Ratio: $_aspectRatioMode';
      _showFitToast = true;
    });
    _fitToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showFitToast = false);
      }
    });
  }

  // ─── Episode Selection Drawer ───────────────────────

  void _showEpisodesDrawer() {
    _hideTimer?.cancel();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episodes',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 320,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xF0111118),
              border: Border(left: BorderSide(color: Colors.white10)),
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.format_list_bulleted_rounded, color: AppColors.primary),
                          const SizedBox(width: 10),
                          const Text(
                            'Select Episode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: widget.episodes!.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final ep = widget.episodes![index];
                          final isCurrent = index == _currentEpisodeIndex;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isCurrent ? AppColors.primary.withOpacity(0.2) : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isCurrent ? AppColors.primary : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              ep.name,
                              style: TextStyle(
                                color: isCurrent ? AppColors.primary : Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: ep.duration.isNotEmpty
                                ? Text(
                                    ep.duration,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              _playEpisodeAtIndex(index);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(anim1),
          child: child,
        );
      },
    ).then((_) => _startHideTimer());
  }

  // ─── Settings Bottom Sheet ──────────────────────────

  String? _getSeasonNumber() {
    if (widget.episodes == null || _currentEpisodeIndex == null) return null;
    final ep = widget.episodes![_currentEpisodeIndex!];
    final json = ep.rawJson;
    if (json == null) return null;
    final candidates = [
      json['season_num'],
      json['s_num'],
      json['season'],
      json['series_season'],
    ];
    for (final c in candidates) {
      if (c != null) return c.toString();
    }
    return '1';
  }

  String? _getEpisodeNumber() {
    if (widget.episodes == null || _currentEpisodeIndex == null) return null;
    final ep = widget.episodes![_currentEpisodeIndex!];
    return ep.episodeNumber.toString();
  }

  void _showSettingsSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(
        subtitleTracks: _subtitleTracks,
        activeSubtitleTrack: _activeSubtitleTrack,
        audioTracks: _audioTracks,
        activeAudioTrack: _activeAudioTrack,
        videoTracks: _videoTracks,
        activeVideoTrack: _activeVideoTrack,
        externalSubtitles: _externalSubtitles,
        activeSubtitleSize: _subtitleSize,
        activeSubtitleColor: _subtitleColor,
        activeSubtitleBgColor: _subtitleBgColor,
        onSubtitleSizeChanged: (size) {
          setState(() => _subtitleSize = size);
        },
        onSubtitleColorChanged: (color) {
          setState(() => _subtitleColor = color);
        },
        onSubtitleBgColorChanged: (bgColor) {
          setState(() => _subtitleBgColor = bgColor);
        },
        onSubtitleSelected: (track) {
          _player?.setSubtitleTrack(track);
          Navigator.pop(context);
        },
        onSubtitleOff: () {
          _player?.setSubtitleTrack(SubtitleTrack.no());
          Navigator.pop(context);
        },
        onAudioSelected: (track) {
          _player?.setAudioTrack(track);
          Navigator.pop(context);
        },
        onVideoSelected: (track) {
          _player?.setVideoTrack(track);
          Navigator.pop(context);
        },
        onVideoAuto: () {
          _player?.setVideoTrack(VideoTrack.auto());
          Navigator.pop(context);
        },
        videoTitle: _title,
        seasonNumber: _getSeasonNumber(),
        episodeNumber: _getEpisodeNumber(),
        onExternalSubtitleDownloaded: (track) {
          setState(() {
            _externalSubtitles.add(SubtitleInfo(label: track.title!, url: track.id));
          });
          _player?.setSubtitleTrack(track);
        },
      ),
    ).then((_) => _startHideTimer());
  }

  // ─── Speed Bottom Sheet ─────────────────────────────

  void _showSpeedSheet() {
    _hideTimer?.cancel();
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xF0111118),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: AppColors.primary, size: 22),
                  SizedBox(width: 10),
                  Text('Playback Speed',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ...speeds.map((s) {
              final isActive = _playbackSpeed == s;
              return ListTile(
                dense: true,
                leading: Icon(
                  isActive
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isActive ? AppColors.primary : Colors.white38,
                  size: 20,
                ),
                title: Text(
                  s == 1.0 ? 'Normal' : '${s}x',
                  style: TextStyle(
                    color: isActive ? AppColors.primary : Colors.white,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  _setPlaybackSpeed(s);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  // ─── Helpers ────────────────────────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void deactivate() {
    // deactivate() fires before dispose() when the widget is removed
    // from the tree. Stopping here ensures the native audio engine
    // is silenced immediately, even if dispose() is delayed by GC.
    try {
      _player?.stop();
    } catch (_) {}
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _gestureHideTimer?.cancel();
    _fitToastTimer?.cancel();
    _loadingTimeoutTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }

    // Telemetry stop
    if (_videoId != null && _originalCmd != null) {
      final posSeconds = _position.inSeconds;
      ref.read(stalkerApiProvider).logStopPlay(
            videoId: _videoId!,
            cmd: _originalCmd!,
            resolvedUrl: _currentStreamUrl,
            positionSeconds: posSeconds,
            seriesId: widget.seriesId,
          );
    }

    // Final cleanup — stop() already called in deactivate() / _closePlayer()
    try {
      _player?.dispose();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════
//  Settings Sheet Widget
// ══════════════════════════════════════════════════════

class _SettingsSheet extends ConsumerStatefulWidget {
  final List<SubtitleTrack> subtitleTracks;
  final SubtitleTrack? activeSubtitleTrack;
  final List<AudioTrack> audioTracks;
  final AudioTrack? activeAudioTrack;
  final List<VideoTrack> videoTracks;
  final VideoTrack? activeVideoTrack;
  final List<SubtitleInfo> externalSubtitles;
  final double activeSubtitleSize;
  final Color activeSubtitleColor;
  final Color activeSubtitleBgColor;
  final ValueChanged<double> onSubtitleSizeChanged;
  final ValueChanged<Color> onSubtitleColorChanged;
  final ValueChanged<Color> onSubtitleBgColorChanged;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;
  final VoidCallback onSubtitleOff;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<VideoTrack> onVideoSelected;
  final VoidCallback onVideoAuto;

  // New fields
  final String videoTitle;
  final String? seasonNumber;
  final String? episodeNumber;
  final ValueChanged<SubtitleTrack> onExternalSubtitleDownloaded;

  const _SettingsSheet({
    required this.subtitleTracks,
    this.activeSubtitleTrack,
    required this.audioTracks,
    this.activeAudioTrack,
    required this.videoTracks,
    this.activeVideoTrack,
    required this.externalSubtitles,
    required this.activeSubtitleSize,
    required this.activeSubtitleColor,
    required this.activeSubtitleBgColor,
    required this.onSubtitleSizeChanged,
    required this.onSubtitleColorChanged,
    required this.onSubtitleBgColorChanged,
    required this.onSubtitleSelected,
    required this.onSubtitleOff,
    required this.onAudioSelected,
    required this.onVideoSelected,
    required this.onVideoAuto,
    required this.videoTitle,
    this.seasonNumber,
    this.episodeNumber,
    required this.onExternalSubtitleDownloaded,
  });

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Online search state
  bool _showOnlineSearch = false;
  bool _isSearching = false;
  bool _isDownloading = false;
  String? _searchError;
  List<OpenSubtitleItem> _searchResults = [];
  final TextEditingController _searchQueryController = TextEditingController();
  
  // Custom credentials state
  bool _showCredentialsInput = false;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Selected language
  String _selectedLanguage = 'en';

  final List<Map<String, String>> _languagesList = [
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'Spanish (Español)'},
    {'code': 'fr', 'name': 'French (Français)'},
    {'code': 'ar', 'name': 'Arabic (العربية)'},
    {'code': 'hi', 'name': 'Hindi (हिन्दी)'},
    {'code': 'pt', 'name': 'Portuguese (Português)'},
    {'code': 'tr', 'name': 'Turkish (Türkçe)'},
    {'code': 'de', 'name': 'German (Deutsch)'},
    {'code': 'it', 'name': 'Italian (Italiano)'},
    {'code': 'ru', 'name': 'Russian (Русский)'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchQueryController.text = widget.videoTitle;
    
    // Load custom credentials if any
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = ref.read(preferencesProvider);
        final savedUser = prefs.prefs.getString('opensubtitles_username') ?? '';
        final savedPass = prefs.prefs.getString('opensubtitles_password') ?? '';
        if (mounted) {
          setState(() {
            _usernameController.text = savedUser;
            _passwordController.text = savedPass;
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchQueryController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _performSearch() async {
    if (_searchQueryController.text.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResults = [];
    });
    
    try {
      final service = ref.read(opensubtitlesServiceProvider);
      final results = await service.search(
        query: _searchQueryController.text.trim(),
        languages: _selectedLanguage,
        seasonNumber: widget.seasonNumber,
        episodeNumber: widget.episodeNumber,
      );
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = results;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = e.toString();
        });
      }
    }
  }

  Future<void> _downloadSubtitle(OpenSubtitleFile file, String releaseName) async {
    setState(() {
      _isDownloading = true;
      _searchError = null;
    });

    try {
      final service = ref.read(opensubtitlesServiceProvider);
      
      // Save credentials first if user edited them
      final prefs = ref.read(preferencesProvider);
      final user = _usernameController.text.trim();
      final pass = _passwordController.text.trim();
      await prefs.prefs.setString('opensubtitles_username', user);
      await prefs.prefs.setString('opensubtitles_password', pass);

      final localPath = await service.download(
        file.fileId,
        username: user.isEmpty ? null : user,
        password: pass.isEmpty ? null : pass,
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        
        // Pass the new SubtitleTrack back to player screen
        final label = '$releaseName (${_selectedLanguage.toUpperCase()})';
        final track = SubtitleTrack.uri('file://$localPath', title: label);
        widget.onExternalSubtitleDownloaded(track);
        Navigator.pop(context); // close modal settings sheet
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _searchError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75, // slightly expanded to accommodate downloader
      ),
      decoration: BoxDecoration(
        color: const Color(0xF0111118),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.white54,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.subtitles_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Subtitles'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.palette_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Style'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.audiotrack_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Audio'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hd_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Quality'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab views
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSubtitleList(),
                _buildStyleTab(),
                _buildAudioList(),
                _buildQualityList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleList() {
    if (_showOnlineSearch) {
      return _buildOnlineSearchPane();
    }

    final tracks = widget.subtitleTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final isOff = widget.activeSubtitleTrack == null ||
        widget.activeSubtitleTrack!.id == 'no' ||
        widget.activeSubtitleTrack!.id == 'auto';

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _buildTrackTile(
          title: 'Off',
          subtitle: 'Disable subtitles',
          isActive: isOff,
          icon: Icons.subtitles_off_rounded,
          onTap: widget.onSubtitleOff,
        ),
        // ONLINE SEARCH TRIGGER BUTTON
        ListTile(
          dense: true,
          leading: const Icon(
            Icons.search_rounded,
            color: AppColors.primary,
            size: 22,
          ),
          title: const Text(
            'Search Online (OpenSubtitles)',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: const Text(
            'Find and download subtitles online',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
          onTap: () {
            setState(() {
              _showOnlineSearch = true;
            });
            _performSearch(); // auto search first
          },
        ),
        const Divider(color: Colors.white10, height: 1),
        ...tracks.map((track) {
          final isActive = widget.activeSubtitleTrack?.id == track.id;
          return _buildTrackTile(
            title: track.title ?? track.language ?? 'Track ${track.id}',
            subtitle: track.language != null && track.title != null
                ? track.language!
                : null,
            isActive: isActive,
            icon: Icons.subtitles_rounded,
            onTap: () => widget.onSubtitleSelected(track),
          );
        }),
        ...widget.externalSubtitles.map((sub) {
          final isActive = widget.activeSubtitleTrack?.title == sub.label ||
              widget.activeSubtitleTrack?.id == sub.url;
          return _buildTrackTile(
            title: '${sub.label} (External)',
            subtitle: 'Online Subtitle',
            isActive: isActive,
            icon: Icons.closed_caption_rounded,
            onTap: () => widget.onSubtitleSelected(
              SubtitleTrack.uri(sub.url, title: sub.label),
            ),
          );
        }),
        if (tracks.isEmpty && widget.externalSubtitles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No subtitle tracks available',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOnlineSearchPane() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Back button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _showOnlineSearch = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'Search Online Subtitles',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Collapsible Settings Gear for Credentials
              IconButton(
                icon: Icon(
                  _showCredentialsInput ? Icons.settings_rounded : Icons.settings_outlined,
                  color: _showCredentialsInput ? AppColors.primary : Colors.white70,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _showCredentialsInput = !_showCredentialsInput;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Custom credentials input (collapsible)
          if (_showCredentialsInput) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Optional: Your OpenSubtitles.com Account',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 36,
                          child: TextField(
                            controller: _usernameController,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Username',
                              hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                              border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 36,
                          child: TextField(
                            controller: _passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Password',
                              hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                              border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Leave empty to use the default app account.',
                    style: TextStyle(color: Colors.white30, fontSize: 9),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Search query input and Language selector row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: _searchQueryController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      hintText: 'Search movie/show...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 16),
                        onPressed: () => _searchQueryController.clear(),
                      ),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Language Selector Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    dropdownColor: const Color(0xFF111118),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                    items: _languagesList.map((lang) {
                      return DropdownMenuItem<String>(
                        value: lang['code'],
                        child: Text(lang['name']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedLanguage = val;
                        });
                        _performSearch(); // auto search on language change
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Search Submit Button
              GestureDetector(
                onTap: _performSearch,
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.search_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Error and Helpful DNS/ISP Guide Panel
          if (_searchError != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Connection Error',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _searchError!.replaceAll('Exception: ', '').replaceAll('HttpException: ', ''),
                    style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Results / Search status
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _isDownloading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 12),
                            Text(
                              'Downloading subtitle file...',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Text(
                              _searchError != null
                                  ? 'Search failed.'
                                  : 'No online subtitles found.',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final item = _searchResults[index];
                              if (item.files.isEmpty) return const SizedBox.shrink();
                              final file = item.files.first;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: Colors.white.withOpacity(0.02),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Colors.white10),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.closed_caption_rounded, color: Colors.white54, size: 18),
                                  title: Text(
                                    item.release.isNotEmpty ? item.release : file.fileName,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'File: ${file.fileName}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.download_rounded, color: AppColors.primary, size: 18),
                                  onTap: () => _downloadSubtitle(file, item.release.isNotEmpty ? item.release : 'Online Sub'),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleTab() {
    final sizes = {
      20.0: 'Small',
      32.0: 'Medium',
      44.0: 'Large',
    };

    final colors = {
      Colors.white: 'White',
      Colors.yellow: 'Yellow',
      Colors.cyan: 'Cyan',
      Colors.green: 'Green',
    };

    final bgColors = {
      Colors.transparent: 'None',
      const Color(0x88000000): 'Translucent',
      Colors.black: 'Solid Black',
    };

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Font Size',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        Row(
          children: sizes.entries.map((e) {
            final isSelected = widget.activeSubtitleSize == e.key;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onSubtitleSizeChanged(e.key),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Text Color',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        Row(
          children: colors.entries.map((e) {
            final isSelected = widget.activeSubtitleColor == e.key;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onSubtitleColorChanged(e.key),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Background',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        Row(
          children: bgColors.entries.map((e) {
            final isSelected = widget.activeSubtitleBgColor == e.key;
            return Expanded(
              child: GestureDetector(
                onTap: () => widget.onSubtitleBgColorChanged(e.key),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildAudioList() {
    final tracks = widget.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        ...tracks.map((track) {
          final isActive = widget.activeAudioTrack?.id == track.id;
          return _buildTrackTile(
            title: track.title ?? track.language ?? 'Track ${track.id}',
            subtitle: track.language != null && track.title != null
                ? track.language!
                : null,
            isActive: isActive,
            icon: Icons.audiotrack_rounded,
            onTap: () => widget.onAudioSelected(track),
          );
        }),
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No audio tracks available',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQualityList() {
    final tracks = widget.videoTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final isAuto = widget.activeVideoTrack == null ||
        widget.activeVideoTrack!.id == 'auto';

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _buildTrackTile(
          title: 'Auto',
          subtitle: 'Adaptive quality',
          isActive: isAuto,
          icon: Icons.auto_awesome_rounded,
          onTap: widget.onVideoAuto,
        ),
        ...tracks.map((track) {
          final isActive = widget.activeVideoTrack?.id == track.id;
          String label;
          if (track.h != null && track.h! > 0) {
            label = '${track.h}p';
          } else if (track.w != null && track.w! > 0) {
            label = '${track.w}w';
          } else {
            label = track.title ?? 'Track ${track.id}';
          }
          return _buildTrackTile(
            title: label,
            subtitle: track.title,
            isActive: isActive,
            icon: Icons.hd_rounded,
            onTap: () => widget.onVideoSelected(track),
          );
        }),
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No quality options available',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTrackTile({
    required String title,
    String? subtitle,
    required bool isActive,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        isActive ? Icons.check_circle_rounded : icon,
        color: isActive ? AppColors.primary : Colors.white38,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isActive ? AppColors.primary : Colors.white,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11))
          : null,
      trailing: isActive
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Active',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            )
          : null,
      onTap: onTap,
    );
  }
}
