import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/config/app_config.dart';
import '../../auth/domain/providers.dart';
import 'technical_inspector_screen.dart';
import 'debug_dashboard.dart' as debug_dashboard;

class ProfileScreen extends ConsumerWidget {
  final VoidCallback? onLogout;
  const ProfileScreen({super.key, this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    int debugTaps = 0;
    DateTime? firstTap;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text(AppStrings.profile)),
      body: ListView(
        children: [
          // Profile header
          Container(
            margin: const EdgeInsets.all(AppDimensions.md),
            padding: const EdgeInsets.all(AppDimensions.lg),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  if (firstTap == null || now.difference(firstTap!).inSeconds > AppConfig.debugTapWindow.inSeconds) {
                    firstTap = now;
                    debugTaps = 1;
                  } else {
                    debugTaps++;
                  }
                  if (debugTaps >= AppConfig.debugTapCount) {
                    debugTaps = 0;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const debug_dashboard.DebugDashboard()));
                  }
                },
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 15)],
                  ),
                  child: const Center(child: Icon(Icons.person, color: Colors.white, size: 36)),
                ),
              ),
              const SizedBox(height: 12),
              Text(auth.profile?.name ?? 'User', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(auth.profile?.mac ?? '', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),

          // Account info
          _section(context, AppStrings.accountInfo, [
            _tile(context, 'Portal', auth.portalUrl ?? 'N/A', Icons.link),
            _tile(context, 'MAC', auth.macAddress ?? 'N/A', Icons.router),
            _tile(context, 'Status', auth.profile?.status == true ? 'Active' : 'Inactive', Icons.circle, color: auth.profile?.status == true ? AppColors.success : AppColors.error),
            if (auth.profile?.endDate.isNotEmpty == true) _tile(context, 'Expires', auth.profile!.endDate, Icons.calendar_today),
          ]),

          // Session info
          _section(context, AppStrings.sessionInfo, [
            _tile(context, 'Token', auth.token != null ? '${auth.token!.substring(0, 12)}...' : 'N/A', Icons.vpn_key),
            _tile(context, 'Server', auth.mainInfo?.serverName ?? 'N/A', Icons.dns),
          ]),

          // System Diagnostics
          _section(context, 'Support & Tools', [
            _actionTile(context, 'Problem Inspector', Icons.troubleshoot_rounded, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnicalInspectorScreen()));
            }, color: AppColors.primary),
            _actionTile(context, 'Developer Tools (MAG)', Icons.developer_mode_rounded, () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnicalInspectorScreen()));
            }, color: AppColors.textSecondary),
          ]),

          // Actions
          const SizedBox(height: AppDimensions.md),
          _actionTile(context, AppStrings.clearCache, Icons.delete_sweep, () async {
            final prefs = ref.read(preferencesProvider);
            await prefs.clearCacheOnly();
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
          }),
          _actionTile(context, AppStrings.appInfo, Icons.info_outline, () {
            showAboutDialog(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: 'v${AppConfig.appVersion}',
              applicationLegalese: '© 2026 SliX TV',
            );
          }),
          _actionTile(context, AppStrings.logout, Icons.logout, () async {
            await ref.read(authProvider.notifier).logout();
            onLogout?.call();
          }, color: AppColors.error),

          // Hidden debug tap zone
          StatefulBuilder(
            builder: (context, setState) => GestureDetector(
              onTap: () {
                final now = DateTime.now();
                if (firstTap == null || now.difference(firstTap!) > AppConfig.debugTapWindow) {
                  debugTaps = 1; firstTap = now;
                } else { debugTaps++; }
                if (debugTaps >= AppConfig.debugTapCount) {
                  debugTaps = 0; firstTap = null;
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugScreen()));
                }
              },
              child: Container(
                height: 60, alignment: Alignment.center,
                child: Text('v${AppConfig.appVersion}', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(AppDimensions.md, AppDimensions.lg, AppDimensions.md, AppDimensions.sm), child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      ...children,
    ]);
  }

  Widget _tile(BuildContext context, String label, String value, IconData icon, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textTertiary, size: 20),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      trailing: Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
    );
  }

  Widget _actionTile(BuildContext context, String label, IconData icon, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary, size: 22),
      title: Text(label, style: TextStyle(color: color ?? AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
      onTap: onTap,
    );
  }
}

// ─── Debug Screen ──────────────────────────────────────────
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = ref.watch(loggerProvider);
    final auth = ref.watch(authProvider);
    final logs = logger.logBuffer;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundLight,
          title: const Text('Technical Logs'),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            tabs: [Tab(text: 'AUTH'), Tab(text: 'NETWORK'), Tab(text: 'MAG FLOW'), Tab(text: 'PLAYER')],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy Debug Report',
              onPressed: () {
                final report = logger.exportLogs();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Debug report copied (${report.length} chars)')));
              },
            ),
          ],
        ),
        body: TabBarView(children: [
          // AUTH tab
          ListView(padding: const EdgeInsets.all(AppDimensions.md), children: [
            _debugItem('Portal', auth.portalUrl ?? 'N/A'),
            _debugItem('MAC', auth.macAddress ?? 'N/A'),
            _debugItem('Token', auth.token ?? 'N/A'),
            _debugItem('Status', auth.status.name),
            _debugItem('Profile ID', auth.profile?.id ?? 'N/A'),
            _debugItem('Server', auth.mainInfo?.serverName ?? 'N/A'),
          ]),
          // NETWORK tab
          ListView.builder(
            padding: const EdgeInsets.all(AppDimensions.sm),
            itemCount: logs.where((l) => l.tag == 'NETWORK').length,
            itemBuilder: (_, i) {
              final netLogs = logs.where((l) => l.tag == 'NETWORK').toList();
              if (i >= netLogs.length) return const SizedBox();
              final log = netLogs[i];
              return _logCard(log.message, log.timestamp.toIso8601String());
            },
          ),
          // MAG FLOW tab
          ListView.builder(
            padding: const EdgeInsets.all(AppDimensions.sm),
            itemCount: logs.where((l) => l.tag.startsWith('MAG')).length,
            itemBuilder: (_, i) {
              final magLogs = logs.where((l) => l.tag.startsWith('MAG')).toList();
              if (i >= magLogs.length) return const SizedBox();
              final log = magLogs[i];
              return _logCard('[${log.tag}] ${log.message}', log.timestamp.toIso8601String());
            },
          ),
          // PLAYER tab
          ListView.builder(
            padding: const EdgeInsets.all(AppDimensions.sm),
            itemCount: logs.where((l) => l.tag == 'PLAYER').length,
            itemBuilder: (_, i) {
              final pLogs = logs.where((l) => l.tag == 'PLAYER').toList();
              if (i >= pLogs.length) return const SizedBox();
              final log = pLogs[i];
              return _logCard(log.message, log.timestamp.toIso8601String(), isError: log.error != null);
            },
          ),
        ]),
      ),
    );
  }

  Widget _debugItem(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'))),
    ]));
  }

  Widget _logCard(String message, String time, {bool isError = false}) {
    return Card(
      color: isError ? AppColors.error.withValues(alpha: 0.1) : AppColors.surface,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(time, style: TextStyle(fontSize: 9, color: AppColors.textHint)),
        const SizedBox(height: 2),
        Text(message, style: TextStyle(fontSize: 11, color: isError ? AppColors.error : AppColors.textPrimary, fontFamily: 'monospace')),
      ])),
    );
  }
}
