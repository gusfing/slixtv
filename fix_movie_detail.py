import re

def fix_movie_detail():
    file_path = r'C:\Users\ks209\Documents\kawaki clients\iptv sflixtv\iptv last testing phase (2)\iptv last testing phase\lib\features\movies\presentation\movie_detail_screen.dart'
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
                                child: movie.poster.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: movie.poster,
                                        httpHeaders: ApiClient().getStalkerHeaders(),
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64, color: Colors.white24),
                                      )
                                    : const Icon(Icons.movie, size: 64, color: Colors.white24),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // Title
                            Text(
                              movie.name,
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
                              const SizedBox(height: 16),
                            ],

                            // Action Watch Now Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: movie.hasFiles ? AppColors.primary : Colors.grey,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _isLoadingStream
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.play_arrow_rounded, size: 24),
                                label: Text(
                                  _isLoadingStream
                                      ? 'RESOLVING STREAM...'
                                      : movie.hasFiles
                                          ? 'WATCH NOW'
                                          : 'UNAVAILABLE',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                                ),
                                onPressed: movie.cmd.isEmpty || !movie.hasFiles ? null : () => _playMovie(movie),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Error message if any
                            if (_streamError != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.error.withOpacity(0.5)),
                                ),
                                child: Text(
                                  _streamError!,
                                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Compact Cast / Director details
                            if (movie.director.isNotEmpty && movie.director != 'null') ...[
                              Text(
                                'Director: ${movie.director}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (movie.actors.isNotEmpty && movie.actors != 'null') ...[
                              Text(
                                'Cast: ${movie.actors}',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Synopsis
                            if (movie.description.isNotEmpty && movie.description != 'null') ...[
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
                                  movie.description,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
"""

    start_token = "// Main Horizontal side-by-side details layout"
    end_token = "], // End of Safe Area Column"
    
    # We will just replace everything from start_token to the end of the Expanded widget.
    # The Expanded widget ends before `], // End of Safe Area Column` or similar.
    # Let's use regex to find the Expanded widget.
    
    match = re.search(r'// Main Horizontal side-by-side details layout.*?Expanded\s*\(.*?\n\s*\),\n\s*\],\n\s*\),', content, re.DOTALL)
    if not match:
        # fallback regex
        match = re.search(r'// Main Horizontal side-by-side details layout.*?(?=\n\s*\]\s*,\s*\n\s*\)\s*,\s*\n\s*\]\s*,\s*\n\s*\)\s*,\s*\n\s*\)\s*;\s*\n\s*\})', content, re.DOTALL)

    if match:
        content = content[:match.start()] + new_ui + content[match.end():]
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Patched movie detail UI")
    else:
        print("Could not find movie detail layout to patch")

fix_movie_detail()
