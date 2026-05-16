import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';

class AuthenticationException implements Exception {
  final String message;
  AuthenticationException(this.message);
  @override
  String toString() => 'AuthenticationException: $message';
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}

class MagAuthService {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;

  MagAuthService({
    required this.dio,
    required this.sessionManager,
    required this.deviceIdentity,
  });

  String get _url {
    if (sessionManager.portalBaseUrl == null || sessionManager.portalEndpoint == null) {
      throw AuthenticationException('Portal endpoint not discovered');
    }
    return '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
  }

  Map<String, String> get _headers {
    return MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );
  }

  Future<void> authenticate() async {
    try {
      // Step 1: Handshake
      final handshakeResponse = await _makeRequest({
        'type': 'stb',
        'action': 'handshake',
        'prehash': '0',
      });
      
      final token = _extractJsField(handshakeResponse, 'token');
      if (token == null) {
        throw AuthenticationException('No token received from handshake');
      }
      sessionManager.setBearerToken(token);

      // Step 2: Get Profile
      final profileResponse = await _makeRequest({
        'type': 'stb',
        'action': 'get_profile',
      });
      
      final profileId = _extractJsField(profileResponse, 'id');
      final profileName = _extractJsField(profileResponse, 'name');
      final profileIp = _extractJsField(profileResponse, 'ip');
      
      sessionManager.profileId = profileId?.toString();
      sessionManager.profileName = profileName?.toString();
      sessionManager.profileIp = profileIp?.toString();

      // Step 3: Get Main Info
      final mainInfoResponse = await _makeRequest({
        'type': 'stb',
        'action': 'get_main_info',
      });
      
      sessionManager.serverName = _extractJsField(mainInfoResponse, 'server_name')?.toString();

      // Step 4: Get Modules
      await _makeRequest({
        'type': 'stb',
        'action': 'get_modules',
      });

      // Step 5: Mark authenticated
      sessionManager.isAuthenticated = true;

    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        sessionManager.clearSession();
        throw AuthenticationException('Authentication failed: HTTP ${e.response?.statusCode}');
      }
      throw NetworkException('Network error during authentication: ${e.message}');
    } catch (e) {
      sessionManager.clearSession();
      if (e is AuthenticationException) rethrow;
      throw AuthenticationException('Unexpected error during authentication: $e');
    }
  }

  Future<dynamic> _makeRequest(Map<String, dynamic> queryParameters) async {
    final response = await dio.get(
      _url,
      queryParameters: queryParameters,
      options: Options(headers: _headers),
    );
    
    if (response.data is Map && response.data['js'] != null) {
      return response.data['js'];
    }
    
    if (response.data is String) {
      // Try naive parse if string contains "js"
      if (response.data.contains('"js"')) {
        // Since we don't have response_parser yet, we do a basic check
        // The robust parser will be implemented in Task 7
      }
    }
    
    return response.data;
  }

  dynamic _extractJsField(dynamic jsData, String field) {
    if (jsData is Map) {
      return jsData[field];
    }
    return null;
  }
}
