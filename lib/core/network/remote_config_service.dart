import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// Configuration schema for dynamic notifications/announcements.
class NotificationConfig {
  final String id;
  final String title;
  final String message;
  final String type; // info, warning, promo
  final bool show;

  NotificationConfig({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.show,
  });

  factory NotificationConfig.fromJson(Map<String, dynamic> json) {
    return NotificationConfig(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      show: json['show'] == true,
    );
  }

  factory NotificationConfig.empty() {
    return NotificationConfig(id: '', title: '', message: '', type: 'info', show: false);
  }
}

/// Dynamic Remote Configuration parsed from local dashboard API.
class RemoteConfig {
  final String minVersion;
  final String latestVersion;
  final String updateUrl;
  final bool forceUpdate;
  final NotificationConfig notification;

  RemoteConfig({
    required this.minVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.forceUpdate,
    required this.notification,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      minVersion: json['minVersion']?.toString() ?? '1.0.0',
      latestVersion: json['latestVersion']?.toString() ?? '1.0.0',
      updateUrl: json['updateUrl']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] == true,
      notification: json['notification'] != null
          ? NotificationConfig.fromJson(json['notification'])
          : NotificationConfig.empty(),
    );
  }

  factory RemoteConfig.empty() {
    return RemoteConfig(
      minVersion: '1.0.0',
      latestVersion: '1.0.0',
      updateUrl: '',
      forceUpdate: false,
      notification: NotificationConfig.empty(),
    );
  }
}

/// Service that fetches dynamic configurations from our local Dashboard API.
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));
  
  final AppLogger _logger = AppLogger();

  RemoteConfigService._internal();

  /// Determine the dashboard API URL based on active platform type
  String get baseUrl {
    if (!kDebugMode) {
      // In production/release mode, query our remote serverless Vercel backend
      return AppConfig.remoteConfigUrl;
    }
    
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    try {
      if (Platform.isAndroid) {
        // Android emulators tunnel localhost to 10.0.2.2
        return 'http://10.0.2.2:3000';
      }
    } catch (_) {}
    return 'http://localhost:3000';
  }

  /// Query the config API endpoint. Fallback to empty configs on network timeout/failure.
  Future<RemoteConfig> fetchConfig() async {
    final endpoint = '$baseUrl/api/config';
    _logger.i('RemoteConfig', 'Fetching config from $endpoint');
    
    try {
      final response = await _dio.get(endpoint);
      if (response.statusCode == 200 && response.data != null) {
        final config = RemoteConfig.fromJson(response.data);
        _logger.i('RemoteConfig', 'Successfully loaded config. LatestVersion: ${config.latestVersion}, notification.show: ${config.notification.show}');
        return config;
      }
    } catch (e) {
      _logger.e('RemoteConfig', 'Error fetching remote config. Using empty local fallbacks.', error: e);
    }
    
    return RemoteConfig.empty();
  }
}
