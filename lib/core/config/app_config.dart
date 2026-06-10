/// Application configuration.
class AppConfig {
  AppConfig._();

  // ─── App Info ────────────────────────────────────────────
  static const String appName = 'SFLIXTV';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';

  // ─── Timeouts ────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration handshakeTimeout = Duration(seconds: 20);

  // ─── Cache ───────────────────────────────────────────────
  static const Duration epgCacheDuration = Duration(hours: 6);
  static const Duration categoryCacheDuration = Duration(hours: 12);
  static const Duration posterCacheDuration = Duration(days: 7);
  static const int maxCachedPosters = 500;

  // ─── Search ──────────────────────────────────────────────
  static const Duration searchDebounce = Duration(milliseconds: 400);
  static const int maxSearchResults = 50;

  // ─── Player ──────────────────────────────────────────────
  static const int defaultBufferMs = 10000;
  static const int maxBufferMs = 30000;
  static const int minBufferMs = 5000;
  static const int seekStepMs = 10000;
  static const int maxRetries = 3;

  // ─── Stalker API ─────────────────────────────────────────
  static const String stalkerHandshakeAction = 'handshake';
  static const String stalkerGetProfileAction = 'get_profile';
  static const String stalkerGetMainInfoAction = 'get_main_info';
  static const String stalkerGetGenresAction = 'get_genres';
  static const String stalkerGetOrderedListAction = 'get_ordered_list';
  static const String stalkerCreateLinkAction = 'create_link';
  static const String stalkerGetEpgAction = 'get_short_epg';
  static const String stalkerGetAllChannelsAction = 'get_all_channels';

  // ─── Remote Config ───────────────────────────────────────
  static const String remoteConfigUrl = 'https://slixtv-dashboard.vercel.app'; // Replace with your Vercel deployment URL

  // ─── Stalker API Types ──────────────────────────────────
  static const String typeItv = 'itv';
  static const String typeVod = 'vod';
  static const String typeSeries = 'series';
  static const String typeEpg = 'epg';
  static const String typeStb = 'stb';
  static const String typeWatchdog = 'watchdog';

  // ─── Debug ───────────────────────────────────────────────
  static const int debugTapCount = 5;
  static const Duration debugTapWindow = Duration(seconds: 3);
}
