import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/domain/providers.dart';
import '../../auth/data/models.dart' show SubtitleInfo;
import '../../series/domain/models.dart' show Episode;
import '../../../core/config/app_config.dart';

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

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  final _logger = AppLogger();

  late String _currentStreamUrl;
  late String _title;
  int? _currentEpisodeIndex;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _currentStreamUrl = widget.streamUrl;
    _title = widget.title;
    _currentEpisodeIndex = widget.currentEpisodeIndex;

    _initPlayer();
  }

  void _initPlayer() {
    final authState = ref.read(authProvider);
    Map<String, String>? headers;

    if (authState.authType != 'xtream') {
      final apiClient = ref.read(apiClientProvider);
      headers = {
        'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: Ethernet',
        'Accept': '*/*',
        'Referer': '/c/',
      };
      final Map<String, String> cookies = {'stb_lang': 'en', 'timezone': 'Europe/Kyiv'};
      if (apiClient.macAddress != null) {
        cookies['mac'] = apiClient.macAddress!;
        headers['MAC'] = apiClient.macAddress!;
      }
      if (apiClient.token != null) {
        headers['Authorization'] = 'Bearer ';
        cookies['token'] = apiClient.token!;
      }
      headers['Cookie'] = cookies.entries.map((e) => '=').join('; ');
    } else {
      headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
      };
    }

    _player = Player();
    _player?.setVolume(100.0);
    _videoController = VideoController(_player!);

    _player!.open(Media(
      _currentStreamUrl,
      httpHeaders: headers,
    ));

    _player!.stream.playing.listen((playing) {
      if (playing) {
        if (widget.videoId != null && widget.originalCmd != null) {
          ref.read(stalkerApiProvider).logStartPlay(
            videoId: widget.videoId!,
            cmd: widget.originalCmd!,
            resolvedUrl: _currentStreamUrl,
          );
        }
      }
    });

    _startProgressTracking();
  }

  void _startProgressTracking() {
    if (widget.contentId != null) {
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        final position = _player?.state.position;
        final duration = _player?.state.duration;
        if (position != null && position.inMilliseconds > 0) {
          final prefs = ref.read(preferencesProvider);
          prefs.saveWatchProgress(widget.contentId!, position.inMilliseconds);
          if (duration != null && duration.inMilliseconds > 0) {
            prefs.saveWatchDuration(widget.contentId!, duration.inMilliseconds);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_videoController != null)
            Video(
              controller: _videoController!,
              controls: MaterialVideoControls,
            )
          else
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          
          Positioned(
            top: 24,
            left: 60,
            child: SafeArea(
              child: Text(
                _title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
