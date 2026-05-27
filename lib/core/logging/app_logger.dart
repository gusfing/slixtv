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

/// Structured logging service that also captures logs for the debug menu.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  final DebugState debugState = DebugState();

  late final Logger _logger;
  final List<LogEntry> _logBuffer = [];
  static const int _maxBufferSize = 500;
  
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

  void _addToBuffer(LogLevel level, String tag, String message, {dynamic error}) {
    _logBuffer.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error?.toString(),
    ));
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxBufferSize);
    }
  }

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
      tag: tag,
      message: message,
      error: error?.toString(),
    );
    _logBuffer.add(entry);
    _lastCriticalProblem = entry;
    
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }
  }

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
    _addToBuffer(LogLevel.debug, 'NETWORK', msg);
  }

  void mag(String step, String message) {
    _logger.i('[MAG:$step] $message');
    _addToBuffer(LogLevel.info, 'MAG:$step', message);
  }

  void player(String message, {dynamic error}) {
    if (error != null) {
      _logger.e('[PLAYER] $message', error: error);
      _addToBuffer(LogLevel.error, 'PLAYER', message, error: error);
    } else {
      _logger.d('[PLAYER] $message');
      _addToBuffer(LogLevel.debug, 'PLAYER', message);
    }
  }

  void clearBuffer() => _logBuffer.clear();

  String exportLogs() {
    // Copy safely via index loop to prevent ConcurrentModificationError if logs append simultaneously
    final snapshot = <LogEntry>[];
    final currentLength = _logBuffer.length;
    for (var i = 0; i < currentLength; i++) {
      if (i < _logBuffer.length) {
        snapshot.add(_logBuffer[i]);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('=== SliX TV Debug Report ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${snapshot.length}');
    buffer.writeln('');
    for (final entry in snapshot) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }
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
