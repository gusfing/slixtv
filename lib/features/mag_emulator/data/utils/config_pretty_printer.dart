import 'dart:convert';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_logger.dart';

class ConfigPrettyPrinter {
  static String formatDeviceIdentity(DeviceIdentity identity) {
    return '''
========================================
           DEVICE IDENTITY
========================================
MAC Address   : ${identity.mac}
Serial Number : ${identity.serialNumber}
Device ID 1   : ${identity.deviceId}
Device ID 2   : ${identity.deviceId2}
Signature     : ${identity.signature}
HW Version    : ${identity.hwVersion}
Image Version : ${identity.imageVersion}
STB Type      : ${identity.stbType}
Model         : ${identity.model}
========================================''';
  }

  static String formatSessionManager(SessionManager session) {
    String tokenStr = 'None';
    if (session.bearerToken != null && session.bearerToken!.length > 16) {
      tokenStr = '${session.bearerToken!.substring(0, 16)}... (masked)';
    } else if (session.bearerToken != null) {
      tokenStr = session.bearerToken!;
    }

    return '''
========================================
           SESSION STATE
========================================
Is Authenticated : ${session.isAuthenticated}
Portal URL       : ${session.portalBaseUrl ?? 'None'}
Portal Endpoint  : ${session.portalEndpoint ?? 'None'}
Bearer Token     : $tokenStr
Profile ID       : ${session.profileId ?? 'None'}
Profile Name     : ${session.profileName ?? 'None'}
Server Name      : ${session.serverName ?? 'None'}
========================================''';
  }

  static Future<String> formatCookies(SessionManager session) async {
    if (session.portalBaseUrl == null) return 'No portal URL set, no cookies loaded.';
    
    try {
      final uri = Uri.parse(session.portalBaseUrl!);
      final cookies = await session.cookieJar.loadForRequest(uri);
      
      if (cookies.isEmpty) return 'No cookies stored for ${session.portalBaseUrl}.';

      final sb = StringBuffer();
      sb.writeln('========================================');
      sb.writeln('               COOKIES');
      sb.writeln('========================================');
      for (final cookie in cookies) {
        sb.writeln('${cookie.name}=${cookie.value} (expires: ${cookie.expires})');
      }
      sb.writeln('========================================');
      return sb.toString();
    } catch (e) {
      return 'Failed to load cookies: $e';
    }
  }

  static String formatJson(dynamic data) {
    if (data == null) return 'null';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
    }
  }

  static String truncateUrl(String url, {int maxLength = 80}) {
    if (url.length <= maxLength) return url;
    return '${url.substring(0, maxLength - 3)}...';
  }

  static String formatLogEntries(List<LogEntry> logs) {
    return logs.map((l) => l.toPlainText()).join('\n');
  }

  static String formatStackTrace(StackTrace trace) {
    // Return first 5 lines for brevity
    final lines = trace.toString().split('\n');
    return lines.take(5).join('\n');
  }
}
