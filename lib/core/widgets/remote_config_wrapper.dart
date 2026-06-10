import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import '../config/app_config.dart';
import '../constants/app_colors.dart';
import '../network/remote_config_service.dart';

/// Global Wrapper that injects Remote Config announcements and mandatory soft/hard updates.
class RemoteConfigWrapper extends StatefulWidget {
  final Widget child;

  const RemoteConfigWrapper({super.key, required this.child});

  @override
  State<RemoteConfigWrapper> createState() => _RemoteConfigWrapperState();
}

class _RemoteConfigWrapperState extends State<RemoteConfigWrapper> with SingleTickerProviderStateMixin {
  final RemoteConfigService _configService = RemoteConfigService();
  RemoteConfig _config = RemoteConfig.empty();
  Timer? _pollingTimer;

  // Notification close state
  String _closedNotificationId = '';
  bool _dismissedSoftUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkConfig();
    
    // Periodically poll remote config every 15 minutes to save battery and bandwidth!
    _pollingTimer = Timer.periodic(const Duration(minutes: 15), (_) => _checkConfig());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    final fetched = await _configService.fetchConfig();
    if (mounted) {
      setState(() {
        _config = fetched;
      });
    }
  }

  /// Utility to compare version strings (e.g. "1.0.0" vs "1.0.1")
  bool _isOutdated(String current, String target) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final targetParts = target.split('.').map(int.parse).toList();

      for (var i = 0; i < targetParts.length; i++) {
        final currentPart = i < currentParts.length ? currentParts[i] : 0;
        final targetPart = targetParts[i];

        if (targetPart > currentPart) return true;
        if (currentPart > targetPart) return false;
      }
    } catch (_) {}
    return false;
  }

  void _triggerUpdate(String url) async {
    if (url.isEmpty) return;
    try {
      await webview.InAppBrowser.openWithSystemBrowser(url: webview.WebUri(url));
    } catch (e) {
      debugPrint('Failed to launch system browser: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentVersion = AppConfig.appVersion;
    
    // 1. Mandatory Force Update check (minRequiredVersion > currentVersion)
    final needsForceUpdate = _config.forceUpdate && _isOutdated(currentVersion, _config.minVersion);
    
    // 2. Soft Update check (latestVersion > currentVersion)
    final needsSoftUpdate = !_dismissedSoftUpdate && 
                           !needsForceUpdate && 
                           _isOutdated(currentVersion, _config.latestVersion);

    // 3. Push Announcement Banner check
    final showAnnouncement = _config.notification.show && 
                             _config.notification.id != _closedNotificationId &&
                             _config.notification.title.isNotEmpty;

    return Stack(
      children: [
        // The core application shell
        widget.child,

        // Push Announcement Overlay Banner (top of the screen)
        if (showAnnouncement && !needsForceUpdate)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: _buildAnnouncementBanner(context),
            ),
          ),

        // Soft Update Dialog Overlay
        if (needsSoftUpdate)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: _buildSoftUpdateDialog(context),
              ),
            ),
          ),

        // Hard Force Update Blocking Overlay (covers everything, non-dismissible)
        if (needsForceUpdate)
          Positioned.fill(
            child: PopScope(
              canPop: false, // Prevent back navigation exit
              child: Material(
                color: Colors.black,
                child: _buildForceUpdateBlockingScreen(context),
              ),
            ),
          ),
      ],
    );
  }

  /// Builds a stunning premium glassmorphic banner for dynamic alerts.
  Widget _buildAnnouncementBanner(BuildContext context) {
    Color typeColor = AppColors.info;
    IconData typeIcon = Icons.info_outline;

    if (_config.notification.type == 'warning') {
      typeColor = AppColors.warning;
      typeIcon = Icons.warning_amber_rounded;
    } else if (_config.notification.type == 'promo') {
      typeColor = AppColors.primary;
      typeIcon = Icons.star_border_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: typeColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: typeColor.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge with specific color
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: typeColor.withValues(alpha: 0.2)),
            ),
            child: Icon(typeIcon, color: typeColor, size: 24),
          ),
          const SizedBox(width: 16),
          
          // Header + Message
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _config.notification.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _config.notification.message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          
          // Close button
          GestureDetector(
            onTap: () {
              setState(() {
                _closedNotificationId = _config.notification.id;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a sleek soft update dialog that can be ignored or snoozed.
  Widget _buildSoftUpdateDialog(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      constraints: const BoxConstraints(maxHeight: 340),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo/Update Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 20),
          
          // Title
          const Text(
            'New Version Available!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          
          // Desc
          Text(
            'A premium new version (${_config.latestVersion}) is available. Get the latest optimizations and features.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          
          // Buttons
          Row(
            children: [
              // Later button
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _dismissedSoftUpdate = true;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Later', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 16),
              
              // Update button
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _triggerUpdate(_config.updateUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Update Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// Builds a complete full-screen non-dismissible blocker when a force update is requested.
  Widget _buildForceUpdateBlockingScreen(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            Colors.black,
          ],
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo/Update Badge
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 5,
                )
              ]
            ),
            child: const Icon(Icons.security_update_warning_rounded, color: AppColors.primary, size: 54),
          ),
          const SizedBox(height: 32),
          
          // Main Title
          const Text(
            'UPDATE REQUIRED',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          
          // Body Message
          Text(
            'This version of ${AppConfig.appName} is no longer supported. Please install the latest release to continue enjoying streaming.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          
          // Action Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () => _triggerUpdate(_config.updateUrl),
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              label: const Text(
                'DOWNLOAD AND INSTALL NOW',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 10,
                shadowColor: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
