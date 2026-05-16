import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/domain/providers.dart';
import '../../mag_emulator/mag_emulator_provider.dart';

/// Premium video player screen with gesture controls and quality selection.
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;
  final String? subtitle;
  final String? contentId;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle,
    this.contentId,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _hasError = false;
  String? _errorMessage;
  final _logger = AppLogger();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight, DeviceOrientation.portraitUp]);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _logger.player('Initializing player: ${widget.streamUrl}');
    try {
      // Fetch authenticated headers directly from the active API session
      final apiClient = ref.read(apiClientProvider);
      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG250 stbapp ver: 4 rev: 231 Safari/533.3',
        'X-User-Agent': 'Model: MAG250; Link: WiFi',
        'Accept': '*/*',
        'Accept-Language': 'en_US',
        'Referer': '${apiClient.portalBase}/c/',
      };
      
      if (apiClient.macAddress != null) {
        final mac = apiClient.macAddress!;
        headers['Cookie'] = 'mac=$mac; stb_lang=en; timezone=UTC';
        headers['MAC'] = mac;
        headers['X-User-MAC'] = mac;
      }
      
      if (apiClient.token != null) {
        headers['Authorization'] = 'Bearer ${apiClient.token!}';
      }

      _logger.debugState.playerHeaders = headers.toString();
      _logger.player('Using authenticated MAG session headers for playback');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.streamUrl),
        httpHeaders: headers,
      );
      await _controller!.initialize();
      _controller!.play();
      _controller!.addListener(_onPlayerUpdate);
      if (mounted) setState(() => _isInitialized = true);
      _logger.player('Player initialized successfully');

      // Restore watch progress if available
      if (widget.contentId != null) {
        final prefs = ref.read(preferencesProvider);
        final progress = prefs.getWatchProgress(widget.contentId!);
        if (progress > 0) {
          _controller!.seekTo(Duration(milliseconds: progress));
        }
      }
    } catch (e) {
      _logger.player('Player init failed', error: e);
      if (mounted) setState(() { _hasError = true; _errorMessage = e.toString(); });
    }
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    // Save watch progress periodically
    if (widget.contentId != null && _controller!.value.isPlaying) {
      final prefs = ref.read(preferencesProvider);
      prefs.saveWatchProgress(widget.contentId!, _controller!.value.position.inMilliseconds);
    }
    if (_controller!.value.hasError && !_hasError) {
      setState(() { _hasError = true; _errorMessage = _controller!.value.errorDescription; });
      _logger.player('Playback error', error: _controller!.value.errorDescription);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
  }

  void _seek(int seconds) {
    if (_controller == null) return;
    final pos = _controller!.value.position + Duration(seconds: seconds);
    _controller!.seekTo(pos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w / 3) _seek(-10);
          else if (details.globalPosition.dx > w * 2 / 3) _seek(10);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_hasError)
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text('Playback Failed', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: AppColors.textTertiary, fontSize: 13), textAlign: TextAlign.center)),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () { setState(() { _hasError = false; _errorMessage = null; }); _initPlayer(); }, child: const Text('Retry')),
              ]))
            else
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),

            // Controls overlay
            if (_showControls && _isInitialized && !_isLocked) ...[
              // Top bar
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 8),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (widget.subtitle != null) Text(widget.subtitle!, style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                    IconButton(icon: Icon(_isLocked ? Icons.lock : Icons.lock_open, color: Colors.white, size: 20), onPressed: () => setState(() => _isLocked = !_isLocked)),
                  ]),
                ),
              ),

              // Center controls
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.replay_10, color: Colors.white, size: 36), onPressed: () => _seek(-10)),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: () { _controller!.value.isPlaying ? _controller!.pause() : _controller!.play(); setState(() {}); },
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.9), shape: BoxShape.circle),
                      child: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(icon: const Icon(Icons.forward_10, color: Colors.white, size: 36), onPressed: () => _seek(10)),
                ]),
              ),

              // Bottom bar
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Seek bar
                    VideoProgressIndicator(_controller!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.primary, bufferedColor: Colors.white24, backgroundColor: Colors.white10)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(_formatDuration(_controller!.value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      Text(_formatDuration(_controller!.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ]),
                ),
              ),
            ],

            // Lock indicator
            if (_isLocked)
              Center(child: IconButton(
                icon: const Icon(Icons.lock, color: Colors.white54, size: 32),
                onPressed: () => setState(() => _isLocked = false),
              )),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
