import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../logging/app_logger.dart';

/// Dio HTTP client configured for MAG/Stalker middleware communication.
/// 
/// Single shared singleton — configured once at login, reused for all requests.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  late final CookieJar _cookieJar;
  final AppLogger _logger = AppLogger();

  String? _portalUrl;
  String? _macAddress;
  String? _token;
  String? _serialNumber;
  String? serverLoadPath;

  Dio get dio => _dio;
  CookieJar get cookieJar => _cookieJar;
  String? get portalUrl => _portalUrl;
  String? get macAddress => _macAddress;
  String? get token => _token;

  ApiClient._internal() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: true,
      maxRedirects: 5,
    ));

    _dio.interceptors.addAll([
      CookieManager(_cookieJar),
      _SequentialRequestInterceptor(), // Stagger initiation to prevent flood
      _StalkerHeaderInterceptor(this),
      _LoggingInterceptor(_logger),
    ]);
  }

  void configure({
    required String portalUrl,
    required String macAddress,
    String? serialNumber,
  }) {
    _portalUrl = _normalizePortalUrl(portalUrl);
    _macAddress = macAddress.toUpperCase();
    _serialNumber = serialNumber ?? _generateSerialNumber(macAddress);
    _logger.i('ApiClient', 'Configured: portal=$_portalUrl, mac=$_macAddress');
  }

  void setToken(String token) {
    _token = token;
    _logger.i('ApiClient', 'Token set: ${token.length > 8 ? token.substring(0, 8) : token}...');
  }

  void clearSession() {
    _token = null;
    serverLoadPath = null;
    _cookieJar.deleteAll();
    _logger.i('ApiClient', 'Session cleared');
  }

  /// Returns the portal base URL (scheme + host + optional port).
  /// Used to resolve relative URLs like screenshot_uri.
  String get portalBase {
    if (_portalUrl == null) return '';
    final uri = Uri.tryParse(_portalUrl!);
    if (uri == null) return _portalUrl!;
    return '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
  }

  /// Resolve a possibly-relative URL to absolute using portal base.
  /// e.g. /stalker_portal/screenshots/123.jpg → http://portal.com/stalker_portal/screenshots/123.jpg
  String resolveUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = portalBase;
    if (base.isEmpty) return url;
    if (url.startsWith('/')) return '$base$url';
    return '$base/$url';
  }

  String _normalizePortalUrl(String url) {
    url = url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  String _generateSerialNumber(String mac) {
    final cleanMac = mac.replaceAll(':', '');
    if (cleanMac.length >= 10) {
      return '12${cleanMac.substring(cleanMac.length - 10).toUpperCase()}';
    }
    return cleanMac.padRight(12, '0').substring(0, 12).toUpperCase();
  }



  String? get serialNumber => _serialNumber;
}

/// Interceptor that adds MAG/Stalker-specific headers to every request.
/// These headers exactly match what STB Emulator sends.
class _StalkerHeaderInterceptor extends Interceptor {
  final ApiClient _client;

  _StalkerHeaderInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.addAll({
      'User-Agent':
          'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'X-User-Agent': 'Model: MAG250; Link: Ethernet',
      'Accept': '*/*',
      'Accept-Language': 'en_US',
      'Accept-Encoding': 'gzip, deflate',
      'Referer': '${_client.portalBase}/c/',
    });

    final extraCookies = <String, String>{};
    if (_client._macAddress != null) {
      final mac = _client._macAddress!;
      // mac and sn must be raw (not URL-encoded) — portal matches against registered MAC
      extraCookies['mac'] = mac;
      extraCookies['stb_lang'] = 'en';
      extraCookies['timezone'] = 'Europe/Kyiv';
      if (_client.serialNumber != null) {
        extraCookies['sn'] = _client.serialNumber!;
      }
      
      // Inject MAC in headers as well, matching both standard Stalker and XC emulations
      options.headers['MAC'] = mac;
      options.headers['X-User-MAC'] = mac;
    }

    if (_client._token != null) {
      options.headers['Authorization'] = 'Bearer ${_client._token}';
      extraCookies['token'] = _client._token!;
    }

    if (extraCookies.isNotEmpty) {
      final existingCookie = options.headers['Cookie']?.toString() ?? '';
      options.headers['Cookie'] = _mergeCookies(existingCookie, extraCookies);
    }

    handler.next(options);
  }

  String _mergeCookies(String existing, Map<String, String> extra) {
    final cookies = <String, String>{};
    if (existing.isNotEmpty) {
      for (final pair in existing.split(';')) {
        final parts = pair.split('=');
        if (parts.length == 2) {
          cookies[parts[0].trim()] = parts[1].trim();
        }
      }
    }
    extra.forEach((key, value) {
      cookies[key] = value;
    });
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

/// Request/response logging interceptor — feeds the debug menu.
class _LoggingInterceptor extends Interceptor {
  final AppLogger _logger;

  _LoggingInterceptor(this._logger);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.network(options.method, options.uri.toString());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logger.network(
      response.requestOptions.method,
      response.requestOptions.uri.toString(),
      statusCode: response.statusCode,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.e(
      'NETWORK',
      '${err.requestOptions.method} ${err.requestOptions.uri} FAILED',
      error: err.message,
    );
    handler.next(err);
  }
}

/// Staggers request initiation to prevent the "parallel startup flood".
class _SequentialRequestInterceptor extends Interceptor {
  Future<void> _lastRequestFuture = Future.value();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Chain this request to the end of the previous one with a 150ms delay
    final currentFuture = _lastRequestFuture.then((_) async {
      await Future.delayed(const Duration(milliseconds: 150));
    });

    _lastRequestFuture = currentFuture;

    // Proceed when the previous delay is finished
    currentFuture.then((_) {
      handler.next(options);
    });
  }
}
