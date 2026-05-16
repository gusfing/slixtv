/// App-wide string constants.
class AppStrings {
  AppStrings._();

  static const String appName = 'SliX TV';
  static const String appTagline = 'Premium Streaming Experience';
  static const String appVersion = '1.0.0';

  // ─── Auth ────────────────────────────────────────────────
  static const String loginTitle = 'Connect to Portal';
  static const String loginSubtitle = 'Enter your MAG portal details to start streaming';
  static const String portalUrl = 'Portal URL';
  static const String portalUrlHint = 'http://example.com/c/';
  static const String macAddress = 'MAC Address';
  static const String macAddressHint = '00:1A:79:AA:BB:CC';
  static const String connect = 'Connect';
  static const String rememberMe = 'Remember me';
  static const String connecting = 'Connecting...';
  static const String logout = 'Logout';

  // ─── Validation ──────────────────────────────────────────
  static const String invalidPortal = 'Please enter a valid portal URL';
  static const String invalidMac = 'Please enter a valid MAC address';
  static const String unreachableServer = 'Server is unreachable. Check your connection.';
  static const String authFailed = 'Authentication failed. Check credentials.';
  static const String tokenExpired = 'Session expired. Re-authenticating...';
  static const String handshakeFailed = 'Handshake with portal failed';
  static const String streamUnavailable = 'Stream is currently unavailable';
  static const String playbackFailed = 'Playback failed. Please try again.';

  // ─── Navigation ──────────────────────────────────────────
  static const String home = 'Home';
  static const String liveTV = 'Live TV';
  static const String movies = 'Movies';
  static const String search = 'Search';
  static const String profile = 'Profile';

  // ─── Home ────────────────────────────────────────────────
  static const String continueWatching = 'Continue Watching';
  static const String trendingMovies = 'Trending Movies';
  static const String series = 'Series';
  static const String recentlyAdded = 'Recently Added';
  static const String favorites = 'Favorites';
  static const String recommended = 'Recommended';

  // ─── Player ──────────────────────────────────────────────
  static const String quality = 'Quality';
  static const String subtitles = 'Subtitles';
  static const String audioTrack = 'Audio Track';
  static const String aspectRatio = 'Aspect Ratio';
  static const String nextEpisode = 'Next Episode';

  // ─── Profile ─────────────────────────────────────────────
  static const String accountInfo = 'Account Info';
  static const String portalInfo = 'Portal';
  static const String sessionInfo = 'Session Info';
  static const String clearCache = 'Clear Cache';
  static const String appInfo = 'App Info';
  static const String debugMenu = 'Debug Menu';

  // ─── Search ──────────────────────────────────────────────
  static const String searchHint = 'Search channels, movies, series...';
  static const String noResults = 'No results found';

  // ─── EPG ─────────────────────────────────────────────────
  static const String tvGuide = 'TV Guide';
  static const String now = 'Now';
  static const String noEpg = 'No EPG data available';

  // ─── General ─────────────────────────────────────────────
  static const String retry = 'Retry';
  static const String cancel = 'Cancel';
  static const String ok = 'OK';
  static const String loading = 'Loading...';
  static const String error = 'Error';
  static const String noConnection = 'No internet connection';
}
