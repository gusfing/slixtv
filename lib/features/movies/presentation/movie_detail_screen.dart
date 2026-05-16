import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../domain/models.dart' show VodItem;
import '../../auth/domain/providers.dart';
import '../../player/presentation/player_screen.dart';
import '../../../core/config/app_config.dart';

/// Movie detail screen: poster, synopsis, cast, play.
class MovieDetailScreen extends ConsumerStatefulWidget {
  final VodItem movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  bool _isLoadingStream = false;
  String? _streamError;

  Future<void> _playMovie(VodItem movie) async {
    if (_isLoadingStream) return;
    if (!movie.hasFiles) {
      setState(() => _streamError = 'This title is not yet available on the streaming server.');
      return;
    }
    if (movie.cmd.isEmpty) {
      setState(() => _streamError = 'No stream source found for this title.');
      return;
    }

    setState(() { _isLoadingStream = true; _streamError = null; });

    try {
      final stalkerApi = ref.read(stalkerApiProvider);
      final streamUrl = await stalkerApi.createLink(
        movie.cmd,
        AppConfig.typeVod,
      );

      if (!mounted) return;
      setState(() => _isLoadingStream = false);

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: streamUrl,
          title: movie.name,
          subtitle: movie.year.isNotEmpty ? movie.year : null,
          contentId: 'vod_${movie.id}',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('PortalException: ', '');
      setState(() { _isLoadingStream = false; _streamError = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Try to get richer info — fall back to passed-in data if not available or js=false
    final vodInfo = ref.watch(vodInfoProvider(widget.movie));
    final enriched = vodInfo.whenOrNull(data: (info) => info);
    final movie = enriched ?? widget.movie;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  movie.poster.isNotEmpty
                      ? Image.network(
                          movie.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterFallback(),
                        )
                      : _posterFallback(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.4, 1.0],
                        colors: [Colors.transparent, AppColors.background],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(AppDimensions.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Title
                Text(
                  movie.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),

                // Metadata badges
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (movie.year.isNotEmpty && movie.year != 'null')
                      _badge(movie.year),
                    if (movie.rating.isNotEmpty &&
                        movie.rating != 'null' &&
                        movie.rating != '0' &&
                        movie.rating != '0.0')
                      _badge('⭐ ${movie.rating}'),
                    if (movie.duration.isNotEmpty && movie.duration != 'null')
                      _badge('⏱ ${movie.duration} min'),
                    if (movie.genre.isNotEmpty && movie.genre != 'null')
                      _badge(movie.genre),
                    if (!movie.hasFiles)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                        ),
                        child: const Text('Unavailable',
                            style: TextStyle(fontSize: 12, color: AppColors.error)),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // Error message
                if (_streamError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _streamError!,
                            style: const TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Play button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: movie.cmd.isEmpty ? null : () => _playMovie(movie),
                    icon: _isLoadingStream
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(
                            movie.hasFiles
                                ? Icons.play_arrow_rounded
                                : Icons.play_disabled,
                            size: 26,
                          ),
                    label: Text(
                      _isLoadingStream
                          ? 'Resolving stream...'
                          : movie.hasFiles
                              ? 'Play Movie'
                              : 'Not Available',
                      style:
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: movie.hasFiles
                          ? AppColors.primary
                          : AppColors.surface,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Synopsis
                if (movie.description.isNotEmpty &&
                    movie.description != 'null') ...[
                  Text('Synopsis',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    movie.description,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                ],

                // Cast & Crew
                if (movie.director.isNotEmpty && movie.director != 'null')
                  _infoRow('Director', movie.director),
                if (movie.actors.isNotEmpty && movie.actors != 'null')
                  _infoRow('Cast', movie.actors),

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFallback() => Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(Icons.movie, color: AppColors.textTertiary, size: 64),
        ),
      );

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
}
