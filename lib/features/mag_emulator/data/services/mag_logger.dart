import 'dart:collection';
import 'dart:convert';
import 'package:uuid/uuid.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Map<String, dynamic>? requestData;
  final Map<String, dynamic>? responseData;
  final String? error;
  final int? responseTimeMs;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.requestData,
    this.responseData,
    this.error,
    this.responseTimeMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      if (requestData != null) 'requestData': requestData,
      if (responseData != null) 'responseData': responseData,
      if (error != null) 'error': error,
      if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
    };
  }

  String toPlainText() {
    final sb = StringBuffer();
    sb.writeln('[${timestamp.toIso8601String()}] [${level.name.toUpperCase()}] [$tag] $message');
    if (responseTimeMs != null) sb.writeln('  Duration: ${responseTimeMs}ms');
    if (requestData != null) {
      sb.writeln('  Request:');
      requestData!.forEach((k, v) => sb.writeln('    $k: $v'));
    }
    if (responseData != null) {
      sb.writeln('  Response:');
      responseData!.forEach((k, v) => sb.writeln('    $k: $v'));
    }
    if (error != null) sb.writeln('  Error: $error');
    return sb.toString();
  }
}

class MagLogger {
  static const int maxLogEntries = 500;
  final ListQueue<LogEntry> _logs = ListQueue<LogEntry>(maxLogEntries);
  final _uuid = const Uuid();

  List<LogEntry> get logs => _logs.toList();

  String logRequest({
    required String method,
    required String url,
    Map<String, dynamic>? queryParams,
    Map<String, dynamic>? headers,
    dynamic body,
    String? action,
  }) {
    final id = _uuid.v4();
    final tag = action != null ? 'MAG:$action' : 'NETWORK';
    
    final safeHeaders = _maskHeaders(headers);

    final reqData = {
      'method': method,
      'url': url,
      if (queryParams != null && queryParams.isNotEmpty) 'queryParams': queryParams,
      if (safeHeaders.isNotEmpty) 'headers': safeHeaders,
      if (body != null) 'body': body.toString(),
    };

    _addLog(LogEntry(
      id: id,
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: tag,
      message: 'Request: $method $url',
      requestData: reqData,
    ));

    return id;
  }

  void logResponse({
    required String requestId,
    required int? statusCode,
    required int durationMs,
    dynamic body,
    String? error,
  }) {
    // Find original request to get tag, this is a bit inefficient but fine for 500 entries
    final reqLog = _logs.cast<LogEntry?>().firstWhere(
      (log) => log?.id == requestId,
      orElse: () => null,
    );

    final tag = reqLog?.tag ?? 'NETWORK';
    
    String bodyPreview = '';
    if (body != null) {
      bodyPreview = body.toString();
      if (bodyPreview.length > 200) {
        bodyPreview = '${bodyPreview.substring(0, 200)}...';
      }
    }

    final resData = {
      if (statusCode != null) 'statusCode': statusCode,
      if (bodyPreview.isNotEmpty) 'bodyPreview': bodyPreview,
    };

    _addLog(LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      level: error != null ? LogLevel.error : (statusCode != null && statusCode >= 400 ? LogLevel.warning : LogLevel.info),
      tag: tag,
      message: error != null ? 'Request Failed' : 'Response: $statusCode',
      responseData: resData,
      responseTimeMs: durationMs,
      error: error,
    ));
  }

  void logGeneric(LogLevel level, String tag, String message, [String? error]) {
    _addLog(LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
    ));
  }

  void _addLog(LogEntry entry) {
    if (_logs.length >= maxLogEntries) {
      _logs.removeFirst();
    }
    _logs.addLast(entry);
    
    // Print to console for dev mode
    print(entry.toPlainText().trimRight());
  }

  Map<String, dynamic> _maskHeaders(Map<String, dynamic>? headers) {
    if (headers == null) return {};
    final masked = Map<String, dynamic>.from(headers);
    
    if (masked.containsKey('Authorization')) {
      final auth = masked['Authorization'].toString();
      if (auth.startsWith('Bearer ') && auth.length > 23) {
        masked['Authorization'] = 'Bearer ${auth.substring(7, 23)}...';
      }
    }
    return masked;
  }

  void clearLogs() {
    _logs.clear();
  }

  String exportPlainText() {
    return _logs.map((e) => e.toPlainText()).join('\n');
  }

  String exportJson() {
    return json.encode(_logs.map((e) => e.toJson()).toList());
  }
}
