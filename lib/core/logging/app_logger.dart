import 'dart:convert';
import 'package:logger/logger.dart';

class DebugState {
  String portalUrl = '';
  String macAddress = '';
  String token = '';
  String cookies = '';
  
  // Diagnostic fields for playback resolution
  String selectedContent = ''; // e.g. "Live: HBO" or "Movie: Matrix"
  String requestPayload = ''; // The full query params / body
  String rawResponse = ''; // The full JSON response from server
  String cmd = ''; // Original command
  String cleanedCmd = ''; // Command after stripping ffrt, ffmpeg, auto
  String resolvedUrl = ''; // Final stream URL
  String redirects = ''; // Raw redirect trace
  String playerHeaders = ''; // Headers passed to the player
  String lastError = ''; // Last exception message
}

/// Detailed network transaction representation for the Network Inspector.
class NetworkRequestLog {
  final String id;
  final String url;
  final String method;
  final Map<String, dynamic> queryParams;
  final Map<String, dynamic> requestHeaders;
  final String requestCookies;
  final dynamic requestBody;
  final int? responseStatus;
  final Map<String, List<String>> responseHeaders;
  final String rawResponseBody;
  final Duration duration;
  final DateTime timestamp;
  final String? error;

  NetworkRequestLog({
    required this.id,
    required this.url,
    required this.method,
    required this.queryParams,
    required this.requestHeaders,
    required this.requestCookies,
    this.requestBody,
    this.responseStatus,
    required this.responseHeaders,
    required this.rawResponseBody,
    required this.duration,
    required this.timestamp,
    this.error,
  });

  @override
  String toString() {
    return 'NetworkRequestLog($method $url, status: $responseStatus, duration: ${duration.inMilliseconds}ms)';
  }
}

/// Structured logging service that also captures logs for the debug menu.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  final DebugState debugState = DebugState();

  late final Logger _logger;
  final List<LogEntry> _logBuffer = [];
  final List<NetworkRequestLog> _networkRequests = [];
  
  static const int _maxBufferSize = 1000;
  static const int _maxNetworkBufferSize = 200;
  
  /// The absolute latest critical problem for quick diagnosis.
  LogEntry? _lastCriticalProblem;
  LogEntry? get lastCriticalProblem => _lastCriticalProblem;

  AppLogger._internal() {
    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 80,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
  }

  List<LogEntry> get logBuffer => List<LogEntry>.from(_logBuffer);
  List<NetworkRequestLog> get networkRequests => List<NetworkRequestLog>.from(_networkRequests);

  void _addToBuffer(LogLevel level, String tag, String message, {dynamic error}) {
    _logBuffer.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag.toUpperCase(),
      message: message,
      error: error?.toString(),
    ));
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxBufferSize);
    }
  }

  void addNetworkRequest(NetworkRequestLog requestLog) {
    _networkRequests.add(requestLog);
    if (_networkRequests.length > _maxNetworkBufferSize) {
      _networkRequests.removeRange(0, _networkRequests.length - _maxNetworkBufferSize);
    }
  }

  void clearNetworkRequests() {
    _networkRequests.clear();
  }

  // Generic logging methods
  void d(String tag, String message) {
    _logger.d('[$tag] $message');
    _addToBuffer(LogLevel.debug, tag, message);
  }

  void i(String tag, String message) {
    _logger.i('[$tag] $message');
    _addToBuffer(LogLevel.info, tag, message);
  }

  void w(String tag, String message) {
    _logger.w('[$tag] $message');
    _addToBuffer(LogLevel.warning, tag, message);
  }

  void e(String tag, String message, {dynamic error}) {
    _logger.e('[$tag] $message', error: error);
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      tag: tag.toUpperCase(),
      message: message,
      error: error?.toString(),
    );
    _logBuffer.add(entry);
    _lastCriticalProblem = entry;
    
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }
  }

  // Module-specific shortcuts
  void auth(String message) => i('AUTH', message);
  void cookies(String message) => i('COOKIES', message);
  void webview(String message) => i('WEBVIEW', message);
  void player(String message, {dynamic error}) {
    if (error != null) {
      e('PLAYER', message, error: error);
    } else {
      d('PLAYER', message);
    }
  }
  void portal(String message) => i('PORTAL', message);
  void bridge(String message) => i('BRIDGE', message);
  void live(String message) => i('LIVE', message);
  void movies(String message) => i('MOVIES', message);
  void series(String message) => i('SERIES', message);

  /// Get a human-readable diagnosis of the last problem.
  String get diagnosis {
    final prob = _lastCriticalProblem;
    if (prob == null) return "The app is taking a long time to load. This usually means the portal server is slow or your internet connection is weak.";
    
    final msg = prob.message.toLowerCase();
    final err = prob.error?.toLowerCase() ?? "";
    final tag = prob.tag.toUpperCase();

    if (tag == "HANDSHAKE") return "Portal handshake failed. This usually means the Portal URL or MAC address is incorrect, or the portal is blocking the app.";
    if (msg.contains("nothing_to_play")) return "The provider hasn't assigned a file to this movie yet. Try another title.";
    if (msg.contains("timeout")) return "Connection timed out. The portal server might be slow or your internet is unstable.";
    if (msg.contains("401") || msg.contains("unauthorized")) return "Authentication failed. Your subscription might have expired or the MAC is not active.";
    if (msg.contains("404")) return "The portal endpoint was not found. Double check the Portal URL.";
    if (tag == "PLAYER") return "Video player failed to start the stream. This happens if the link is invalid or requires a specific codec.";
    
    return "Problem in $tag: ${prob.message}${prob.error != null ? ' ($err)' : ''}";
  }

  void network(String method, String url, {int? statusCode, String? body}) {
    final msg = '$method $url → ${statusCode ?? 'pending'}';
    _logger.d('[NET] $msg');
    _addToBuffer(LogLevel.debug, 'DIO', msg);
  }

  void mag(String step, String message) {
    _logger.i('[MAG:$step] $message');
    _addToBuffer(LogLevel.info, 'BRIDGE', '[$step] $message');
  }

  void clearBuffer() {
    _logBuffer.clear();
    _networkRequests.clear();
  }

  String exportLogs() {
    final snapshot = <LogEntry>[];
    final currentLength = _logBuffer.length;
    for (var i = 0; i < currentLength; i++) {
      if (i < _logBuffer.length) {
        snapshot.add(_logBuffer[i]);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('=== SFLIXTV Diagnostic Report ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${snapshot.length}');
    buffer.writeln('');
    for (final entry in snapshot) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }

  String exportConversationLogs() {
    final events = <_TimelineEvent>[];
    
    // Add all standard log entries
    final logSnapshot = logBuffer;
    for (final entry in logSnapshot) {
      events.add(_TimelineEvent(entry.timestamp, entry.toString()));
    }
    
    // Add all network requests
    final netSnapshot = networkRequests;
    for (final req in netSnapshot) {
      final reqTime = req.timestamp.subtract(req.duration);
      final reqTimeStr = '${reqTime.hour.toString().padLeft(2, '0')}:${reqTime.minute.toString().padLeft(2, '0')}:${reqTime.second.toString().padLeft(2, '0')}.${reqTime.millisecond.toString().padLeft(3, '0')}';
      
      final buf = StringBuffer();
      buf.writeln('--------------------------------------------------');
      buf.writeln('[$reqTimeStr] NET TRANSACTION [ID: ${req.id}]');
      buf.writeln('---> REQUEST: ${req.method} ${req.url}');
      if (req.queryParams.isNotEmpty) {
        buf.writeln('     Query Params: ${jsonEncode(req.queryParams)}');
      }
      if (req.requestHeaders.isNotEmpty) {
        buf.writeln('     Headers: ${jsonEncode(req.requestHeaders)}');
      }
      if (req.requestCookies.isNotEmpty) {
        buf.writeln('     Cookies: ${req.requestCookies}');
      }
      if (req.requestBody != null) {
        buf.writeln('     Body/Payload: ${req.requestBody}');
      }
      
      final respTime = req.timestamp;
      final respTimeStr = '${respTime.hour.toString().padLeft(2, '0')}:${respTime.minute.toString().padLeft(2, '0')}:${respTime.second.toString().padLeft(2, '0')}.${respTime.millisecond.toString().padLeft(3, '0')}';
      buf.writeln('[$respTimeStr] <--- RESPONSE: status=${req.responseStatus ?? 'FAILED'} (duration: ${req.duration.inMilliseconds}ms)');
      if (req.error != null) {
        buf.writeln('     Error: ${req.error}');
      }
      if (req.responseHeaders.isNotEmpty) {
        buf.writeln('     Response Headers: ${jsonEncode(req.responseHeaders)}');
      }
      if (req.rawResponseBody.isNotEmpty) {
        buf.writeln('     Response Body:');
        buf.writeln(_prettyJson(req.rawResponseBody));
      }
      buf.writeln('--------------------------------------------------');
      
      // Sort by request initiation time
      events.add(_TimelineEvent(reqTime, buf.toString()));
    }
    
    // Sort chronologically
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    final output = StringBuffer();
    output.writeln('=== SFLIXTV Full Conversation Debug Log ===');
    output.writeln('Generated: ${DateTime.now().toIso8601String()}');
    output.writeln('Total events: ${events.length}');
    output.writeln('===========================================');
    output.writeln('');
    
    for (final ev in events) {
      output.writeln(ev.text);
    }
    
    return output.toString();
  }

  String _prettyJson(dynamic body) {
    if (body == null) return '';
    if (body is String) {
      if (body.isEmpty) return '';
      try {
        final decoded = jsonDecode(body);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return body;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      return body.toString();
    }
  }
}

class _TimelineEvent {
  final DateTime timestamp;
  final String text;
  
  _TimelineEvent(this.timestamp, this.text);
}

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
  });

  @override
  String toString() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final levelStr = level.name.toUpperCase().padRight(7);
    final errStr = error != null ? '\n  ERROR: $error' : '';
    return '[$time] $levelStr [$tag] $message$errStr';
  }
}
