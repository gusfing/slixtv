import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();

  factory SessionManager() {
    return _instance;
  }

  SessionManager._internal();

  String? bearerToken;
  String? portalBaseUrl;
  String? portalEndpoint;
  String? macAddress;
  
  // Profile data
  String? profileId;
  String? profileName;
  String? profileIp;
  String? serverName;
  bool isAuthenticated = false;

  late PersistCookieJar cookieJar;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String appDocPath = appDocDir.path;
    
    // Setup persistent cookie jar
    cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage("$appDocPath/.cookies/"),
    );
    
    _isInitialized = true;
  }

  void setBearerToken(String token) {
    bearerToken = token;
  }

  String? getBearerToken() {
    return bearerToken;
  }

  void setPortalInfo(String baseUrl, String endpoint) {
    portalBaseUrl = baseUrl;
    portalEndpoint = endpoint;
  }
  
  void setMacAddress(String mac) {
    macAddress = mac;
  }

  Future<void> clearSession() async {
    bearerToken = null;
    profileId = null;
    profileName = null;
    profileIp = null;
    serverName = null;
    isAuthenticated = false;
    if (_isInitialized) {
      await cookieJar.deleteAll();
    }
  }

  bool hasValidSession() {
    return bearerToken != null && bearerToken!.isNotEmpty;
  }
}
