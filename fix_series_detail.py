import re

def fix_series_detail():
    file_path = r'C:\Users\ks209\Documents\kawaki clients\iptv sflixtv\iptv last testing phase (2)\iptv last testing phase\lib\features\series\presentation\series_screen.dart'
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_ui = """
                  // Main Details Layout - Vertical for Mobile
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Center Poster
                            Container(
                              width: 160,
                              height: 240,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: widget.series.poster.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: widget.series.poster,
                                        httpHeaders: ApiClient().getStalkerHeaders(),
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64, color: Colors.white24),
                                      )
                                    : const Icon(Icons.movie, size: 64, color: Colors.white24),
                              ),
                            ),
                            if (widget.series.rating.isNotEmpty && widget.series.rating != '0' && widget.series.rating != '0.0' && widget.series.rating != 'null') ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.series.rating,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),
                            
                            // Title
                            Text(
                              widget.series.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),

                            // Horizontal Metadata row
                            if (metadataString.isNotEmpty) ...[
                              Text(
                                metadataString,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Compact Cast / Director details
                            if (widget.series.director.isNotEmpty && widget.series.director != 'null') ...[
                              Text(
                                'Director: ${widget.series.director}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (widget.series.actors.isNotEmpty && widget.series.actors != 'null') ...[
                              Text(
                                'Cast: ${widget.series.actors}',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Synopsis
                            if (widget.series.description.isNotEmpty && widget.series.description != 'null') ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'PLOT SUMMARY',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.series.description,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],

                            // Seasons and Episodes Bottom Section
                            seasonsAsync.when(
                              loading: () => const LoadingIndicator(message: 'Loading episodes...'),
                              error: (err, _) => Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
                                    const SizedBox(height: 12),
                                    Text('Failed to load season details: $err', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: () => ref.invalidate(seriesInfoProvider((seriesId: widget.series.id, seriesCmd: widget.series.cmd))),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                              data: (seasons) {
                                if (seasons.isEmpty) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 40),
                                      child: Text(
                                        'No seasons available',
                                        style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                                      ),
                                    ),
                                  );
                                }

                                final currentSeason = seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)];

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Season Selector Tabs Row
                                    if (seasons.length > 1)
                                      Container(
                                        height: 38,
                                        margin: const EdgeInsets.only(bottom: 16),
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: seasons.length,
                                          itemBuilder: (context, i) {
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 10),
                                              child: _SeasonTab(
                                                title: seasons[i].name.toUpperCase(),
                                                isSelected: i == _selectedSeasonIndex,
                                                onTap: () => setState(() => _selectedSeasonIndex = i),
                                              ),
                                            );
                                          },
                                        ),
                                      ),

                                    // Episode Cards List
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: currentSeason.episodes.length,
                                      itemBuilder: (context, i) {
                                        final ep = currentSeason.episodes[i];
                                        final isPlaying = _playingEpisodeId == ep.id;
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8.0),
                                          child: _EpisodeCard(
                                            episode: ep,
                                            isLoading: isPlaying,
                                            onTap: ep.isLocked ? null : () => _playEpisode(ep, currentSeason.episodes, i),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 40),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
"""

    # For series_screen.dart, we need to match the specific `// Side-by-side details layout` in `SeriesDetailScreen`
    match = re.search(r'// Side-by-side details layout \(Fits in single viewport!\).*?Expanded\s*\(.*?\n\s*\),\n\s*\],\n\s*\),', content, re.DOTALL)
    if not match:
        match = re.search(r'// Side-by-side details layout \(Fits in single viewport!\).*?(?=\n\s*\]\s*,\s*\n\s*\)\s*,\s*\n\s*\]\s*,\s*\n\s*\)\s*,\s*\n\s*\)\s*;\s*\n\s*\}\s*\n\})', content, re.DOTALL)

    if match:
        content = content[:match.start()] + new_ui + content[match.end():]
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Patched series detail UI")
    else:
        print("Could not find series detail layout to patch")

fix_series_detail()
