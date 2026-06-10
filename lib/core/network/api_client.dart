import 'dart:math';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  String? _deviceId;
  String? _deviceId2;
  String? _signature;

  // Custom Debug Configuration variables
  String _stbModel = 'MAG250';
  String _connectionType = 'Ethernet';
  String _timezone = 'Asia/Kolkata';
  bool _urlEncodeMac = true;
  Map<String, String> _customHeaders = {};
  Map<String, String> _customCookies = {};

  Dio get dio => _dio;
  CookieJar get cookieJar => _cookieJar;
  String? get portalUrl => _portalUrl;
  String? get macAddress => _macAddress;
  String? get token => _token;
  String? get serialNumber => _serialNumber;

  // Getters for configuration
  String get stbModel => _stbModel;
  String get connectionType => _connectionType;
  String get timezone => _timezone;
  bool get urlEncodeMac => _urlEncodeMac;
  Map<String, String> get customHeaders => _customHeaders;
  Map<String, String> get customCookies => _customCookies;

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
      DiagnosticsInterceptor(),
    ]);
    if (kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          error: true,
          compact: true,
        ),
      );
    }
  }

  void configure({
    required String portalUrl,
    required String macAddress,
    String? serialNumber,
  }) {
    _portalUrl = _normalizePortalUrl(portalUrl);
    _macAddress = macAddress.toUpperCase();
    _serialNumber = (serialNumber == null || serialNumber.trim().isEmpty)
        ? _generateSerialNumber(_macAddress)
        : serialNumber.trim();
    _logger.i('ApiClient', 'Configured: portal=$_portalUrl, mac=$_macAddress, sn=$_serialNumber');
  }

  /// Update diagnostic configs on the fly (for hot-reload/sandbox testing).
  void updateConfig({
    String? portalUrl,
    String? macAddress,
    String? serialNumber,
    String? stbModel,
    String? connectionType,
    String? timezone,
    bool? urlEncodeMac,
    Map<String, String>? customHeaders,
    Map<String, String>? customCookies,
  }) {
    if (portalUrl != null) _portalUrl = _normalizePortalUrl(portalUrl);
    if (macAddress != null) {
      _macAddress = macAddress.toUpperCase();
      if (serialNumber == null || serialNumber.trim().isEmpty) {
        _serialNumber = _generateSerialNumber(_macAddress);
      }
    }
    if (serialNumber != null && serialNumber.trim().isNotEmpty) {
      _serialNumber = serialNumber.trim();
    }
    if (stbModel != null) _stbModel = stbModel;
    if (connectionType != null) _connectionType = connectionType;
    if (timezone != null) _timezone = timezone;
    if (urlEncodeMac != null) _urlEncodeMac = urlEncodeMac;
    if (customHeaders != null) _customHeaders = customHeaders;
    if (customCookies != null) _customCookies = customCookies;
    
    _logger.i('ApiClient', 'Diagnostic config updated: model=$_stbModel, urlEncodeMac=$_urlEncodeMac, sn=$_serialNumber');
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

  Future<void> loadDeviceIdentity() async {
    const storage = FlutterSecureStorage();
    final currentMac = _macAddress?.toUpperCase() ?? '';
    
    try {
      final storedJson = await storage.read(key: 'mag_device_identity');
      if (storedJson != null) {
        final Map<String, dynamic> map = json.decode(storedJson);
        final storedMac = map['mac']?.toString().toUpperCase() ?? '';
        
        if (storedMac == currentMac && currentMac.isNotEmpty) {
          _deviceId = map['device_id'] ?? '';
          _deviceId2 = map['device_id2'] ?? '';
          _signature = map['signature'] ?? '';
          _logger.i('ApiClient', 'Loaded device identity from storage for MAC $currentMac: deviceId=$_deviceId');
          return;
        }
      }
    } catch (e) {
      _logger.e('ApiClient', 'Failed to load device identity', error: e);
    }

    final random = Random(currentMac.isNotEmpty ? currentMac.hashCode : null);
    const chars = '0123456789abcdef';
    String genHex(int len) => List.generate(len, (index) => chars[random.nextInt(chars.length)]).join();

    final genMac = currentMac.isNotEmpty ? currentMac : (() {
      final macParts = [
        '00', '1A', '79',
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ];
      return macParts.join(':').toUpperCase();
    })();
    
    final macClean = genMac.replaceAll(':', '').toUpperCase();
    final genSn = _serialNumber ?? _generateSerialNumber(genMac);
    final genId = generateDeterministicHex(macClean, 'device_id', 32);
    final genId2 = generateDeterministicHex(macClean, 'device_id2', 32);
    final genSig = generateDeterministicHex(macClean, 'signature', 32);

    final map = {
      'mac': genMac,
      'serial_number': genSn,
      'device_id': genId,
      'device_id2': genId2,
      'signature': genSig,
      'hw_version': '2.6.0',
      'image_version': '218',
      'stb_type': 'MAG250',
      'model': _stbModel,
    };

    try {
      if (genMac.isNotEmpty) {
        await storage.write(key: 'mag_device_identity', value: json.encode(map));
      }
      _deviceId = genId;
      _deviceId2 = genId2;
      _signature = genSig;
      _logger.i('ApiClient', 'Generated and stored deterministic device identity for MAC $genMac: deviceId=$_deviceId');
    } catch (e) {
      _logger.e('ApiClient', 'Failed to save generated device identity', error: e);
      _deviceId = genId;
      _deviceId2 = genId2;
      _signature = genSig;
    }
  }

  /// Returns the portal base URL (scheme + host + optional port).
  String get portalBase {
    if (_portalUrl == null) return '';
    final uri = Uri.tryParse(_portalUrl!);
    if (uri == null) return _portalUrl!;
    return '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
  }

  /// Resolve a possibly-relative URL to absolute using portal base.
  String resolveUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = portalBase;
    if (base.isEmpty) return url;
    if (url.startsWith('/')) return '$base$url';
    return '$base/$url';
  }

  /// Generate Stalker session headers for loading secure images.
  Map<String, String> getStalkerHeaders() {
    String userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';
    if (_stbModel == 'MAG254') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 254 Safari/533.3';
    } else if (_stbModel == 'MAG322') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 322 Safari/533.3';
    } else if (_stbModel == 'MAG420') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 420 Safari/533.3';
    }

    final headers = <String, String>{
      'User-Agent': userAgent,
      'X-User-Agent': 'Model: $_stbModel; Link: $_connectionType',
      'Accept': '*/*',
      'Accept-Language': 'en_US',
      'Referer': '$portalBase/c/',
    };

    final cookies = <String, String>{};
    if (_macAddress != null) {
      final mac = _macAddress!;
      final encodedMac = _urlEncodeMac ? Uri.encodeComponent(mac) : mac;
      cookies['mac'] = encodedMac;
      cookies['stb_lang'] = 'en';
      cookies['timezone'] = _timezone;
      if (_serialNumber != null) {
        cookies['sn'] = _serialNumber!;
      }

      final macClean = mac.replaceAll(':', '').toUpperCase();
      final deviceId = _deviceId ?? generateDeterministicHex(macClean, 'device_id', 32);
      final deviceId2 = _deviceId2 ?? generateDeterministicHex(macClean, 'device_id2', 32);
      final signature = _signature ?? generateDeterministicHex(macClean, 'signature', 32);

      cookies['device_id'] = deviceId;
      cookies['device_id2'] = deviceId2;
      cookies['signature'] = signature;

      headers['device_id'] = deviceId;
      headers['device_id2'] = deviceId2;
      headers['signature'] = signature;

      headers['MAC'] = mac;
      headers['X-User-MAC'] = mac;
    }

    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      cookies['token'] = _token!;
    }

    if (customCookies.isNotEmpty) {
      cookies.addAll(customCookies);
    }

    if (cookies.isNotEmpty) {
      headers['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    if (customHeaders.isNotEmpty) {
      headers.addAll(customHeaders);
    }

    return headers;
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

  String generateDeterministicHex(String mac, String salt, int length) {
    final seed = (mac + salt).hashCode;
    final random = Random(seed);
    const chars = '0123456789abcdef';
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }
}

/// Interceptor that adds MAG/Stalker-specific headers to every request.
/// Emulates different MAG STB devices dynamically based on config.
class _StalkerHeaderInterceptor extends Interceptor {
  final ApiClient _client;

  _StalkerHeaderInterceptor(this._client);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Resolve User-Agent based on selected model emulation
    String userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';
    
    if (_client.stbModel == 'MAG254') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 254 Safari/533.3';
    } else if (_client.stbModel == 'MAG322') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 322 Safari/533.3';
    } else if (_client.stbModel == 'MAG420') {
      userAgent = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 420 Safari/533.3';
    }

    options.headers.addAll({
      'User-Agent': userAgent,
      'X-User-Agent': 'Model: ${_client.stbModel}; Link: ${_client.connectionType}',
      'Accept': '*/*',
      'Accept-Language': 'en_US',
      'Accept-Encoding': 'gzip, deflate',
      'Referer': '${_client.portalBase}/c/',
    });

    final extraCookies = <String, String>{};
    if (_client._macAddress != null) {
      final mac = _client._macAddress!;
      
      // MAC encoding toggle — URL encode colons vs raw
      final encodedMac = _client.urlEncodeMac ? Uri.encodeComponent(mac) : mac;
      
      extraCookies['mac'] = encodedMac;
      extraCookies['stb_lang'] = 'en';
      extraCookies['timezone'] = _client.timezone;
      if (_client.serialNumber != null) {
        final sn = _client.serialNumber!;
        final encodedSn = _client.urlEncodeMac ? Uri.encodeComponent(sn) : sn;
        extraCookies['sn'] = encodedSn;
      }

      final macClean = mac.replaceAll(':', '').toUpperCase();
      final deviceId = _client._deviceId ?? _client.generateDeterministicHex(macClean, 'device_id', 32);
      final deviceId2 = _client._deviceId2 ?? _client.generateDeterministicHex(macClean, 'device_id2', 32);
      final signature = _client._signature ?? _client.generateDeterministicHex(macClean, 'signature', 32);

      extraCookies['device_id'] = deviceId;
      extraCookies['device_id2'] = deviceId2;
      extraCookies['signature'] = signature;

      options.headers['device_id'] = deviceId;
      options.headers['device_id2'] = deviceId2;
      options.headers['signature'] = signature;
      
      // Inject MAC in headers, matching both Stalker and XC
      options.headers['MAC'] = mac;
      options.headers['X-User-MAC'] = mac;
    }

    if (_client._token != null) {
      options.headers['Authorization'] = 'Bearer ${_client._token}';
      extraCookies['token'] = _client._token!;
    }

    // Merge custom cookies override
    if (_client.customCookies.isNotEmpty) {
      extraCookies.addAll(_client.customCookies);
    }

    if (extraCookies.isNotEmpty) {
      final existingCookie = options.headers['Cookie']?.toString() ?? '';
      options.headers['Cookie'] = _mergeCookies(existingCookie, extraCookies);
    }

    // Merge custom headers override
    if (_client.customHeaders.isNotEmpty) {
      options.headers.addAll(_client.customHeaders);
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

/// Request/response diagnostics interceptor — feeds the network inspector buffer.
class DiagnosticsInterceptor extends Interceptor {
  final AppLogger _logger = AppLogger();
  final Map<String, DateTime> _startTimes = {};

  DiagnosticsInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    options.extra['requestId'] = requestId;
    _startTimes[requestId] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final requestId = response.requestOptions.extra['requestId'] as String?;
    final startTime = requestId != null ? _startTimes.remove(requestId) : null;
    final duration = startTime != null ? DateTime.now().difference(startTime) : Duration.zero;

    final String cookiesSent = response.requestOptions.headers['Cookie']?.toString() ?? '';
    dynamic responseData = response.data;
    String rawResponseBody = '';
    
    if (responseData != null) {
      if (responseData is String) {
        rawResponseBody = responseData;
      } else {
        try {
          rawResponseBody = responseData.toString();
        } catch (_) {}
      }
    }

    final requestHeadersMap = Map<String, dynamic>.from(response.requestOptions.headers);
    final responseHeadersMap = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeadersMap[name] = values;
    });

    final log = NetworkRequestLog(
      id: requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      url: response.requestOptions.uri.toString(),
      method: response.requestOptions.method,
      queryParams: response.requestOptions.queryParameters,
      requestHeaders: requestHeadersMap,
      requestCookies: cookiesSent,
      requestBody: response.requestOptions.data,
      responseStatus: response.statusCode,
      responseHeaders: responseHeadersMap,
      rawResponseBody: rawResponseBody,
      duration: duration,
      timestamp: DateTime.now(),
    );

    _logger.addNetworkRequest(log);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final requestId = err.requestOptions.extra['requestId'] as String?;
    final startTime = requestId != null ? _startTimes.remove(requestId) : null;
    final duration = startTime != null ? DateTime.now().difference(startTime) : Duration.zero;

    final String cookiesSent = err.requestOptions.headers['Cookie']?.toString() ?? '';
    final String rawResponseBody = err.response?.data?.toString() ?? '';

    final requestHeadersMap = Map<String, dynamic>.from(err.requestOptions.headers);
    final responseHeadersMap = <String, List<String>>{};
    err.response?.headers.forEach((name, values) {
      responseHeadersMap[name] = values;
    });

    final log = NetworkRequestLog(
      id: requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      url: err.requestOptions.uri.toString(),
      method: err.requestOptions.method,
      queryParams: err.requestOptions.queryParameters,
      requestHeaders: requestHeadersMap,
      requestCookies: cookiesSent,
      requestBody: err.requestOptions.data,
      responseStatus: err.response?.statusCode,
      responseHeaders: responseHeadersMap,
      rawResponseBody: rawResponseBody,
      duration: duration,
      timestamp: DateTime.now(),
      error: err.message,
    );

    _logger.addNetworkRequest(log);
    handler.next(err);
  }
}

/// Staggers request initiation to prevent the "parallel startup flood".
class _SequentialRequestInterceptor extends Interceptor {
  Future<void> _lastRequestFuture = Future.value();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Chain this request to the end of the previous one with a 20ms delay
    final currentFuture = _lastRequestFuture.then((_) async {
      await Future.delayed(const Duration(milliseconds: 20));
    });

    _lastRequestFuture = currentFuture;

    // Proceed when the previous delay is finished
    currentFuture.then((_) {
      handler.next(options);
    });
  }
}
