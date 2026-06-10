import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/config/app_config.dart';
import '../../auth/domain/providers.dart';
import '../../../core/widgets/parental_pin_dialog.dart';
import 'technical_inspector_screen.dart';
import 'diagnostic_harness_layout.dart';
import 'debug_dashboard.dart' as debug_dashboard;

class ProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;
  const ProfileScreen({super.key, this.onLogout});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _activeCategoryIndex = 0;
  int debugTaps = 0;
  DateTime? firstTap;

  Widget _sidebarCategoryItem(int index, String label, IconData icon) {
    final isSelected = _activeCategoryIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeCategoryIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridTile(String label, String value, IconData icon, {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color ?? AppColors.textTertiary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(BuildContext context, String label, String subtitle, IconData icon, VoidCallback onTap, {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (color ?? AppColors.primary).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color ?? AppColors.primary, size: 22),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _buildActiveCategoryContent(BuildContext context, dynamic auth) {
    switch (_activeCategoryIndex) {
      case 0: // Account & Profile
        return ListView(
          padding: const EdgeInsets.all(AppDimensions.md),
          children: [
            // Profile Header Card
            Container(
              padding: const EdgeInsets.all(AppDimensions.lg),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
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
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                      ),
                      child: const Center(child: Icon(Icons.person, color: Colors.white, size: 28)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.profile?.name ?? 'User', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(auth.profile?.mac ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Account parameters grid
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 3.8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _gridTile('Portal Link', auth.portalUrl ?? 'N/A', Icons.link),
                _gridTile('MAC Address', auth.macAddress ?? 'N/A', Icons.router),
                _gridTile('Status', auth.profile?.status == true ? 'Active' : 'Inactive', Icons.circle, color: auth.profile?.status == true ? AppColors.success : AppColors.error),
                _gridTile('Expires', auth.profile?.endDate.isNotEmpty == true ? auth.profile!.endDate : 'Unlimited', Icons.calendar_today),
                _gridTile('Session Token', auth.token != null ? '${auth.token!.substring(0, 12)}...' : 'N/A', Icons.vpn_key),
                _gridTile('IPTV Server', auth.mainInfo?.serverName ?? 'N/A', Icons.dns),
              ],
            ),
          ],
        );

      case 1: // Security & Parental PIN
        return Consumer(
          builder: (context, ref, child) {
            return ListView(
              padding: const EdgeInsets.all(AppDimensions.md),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: const Icon(Icons.security_rounded, color: AppColors.primary, size: 24),
                        title: const Text('Parental Control Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text(
                          'Adult content is securely protected by PIN',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: const Icon(Icons.lock_rounded, color: AppColors.primary),
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.pin_rounded, color: AppColors.textPrimary, size: 22),
                          title: const Text('Change Parental PIN'),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                          onTap: () async {
                            // 1. Verify current PIN
                            final verified = await ParentalPinDialog.show(
                              context,
                              title: 'CURRENT PIN',
                              instruction: 'Enter your current 4-digit PIN code',
                            );
                            if (!verified) return;

                            if (!context.mounted) return;

                            // 2. Get new PIN
                            String? newPin;
                            await showGeneralDialog<void>(
                              context: context,
                              barrierDismissible: true,
                              barrierLabel: 'New PIN',
                              barrierColor: Colors.black87,
                              transitionDuration: const Duration(milliseconds: 300),
                              pageBuilder: (context, anim1, anim2) {
                                return ParentalPinDialog(
                                  title: 'NEW PIN',
                                  instruction: 'Enter your new 4-digit PIN code',
                                  onSubmit: (pin) {
                                    newPin = pin;
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                              transitionBuilder: (context, anim1, anim2, child) {
                                final curve = CurvedAnimation(parent: anim1, curve: Curves.easeInOutBack);
                                return ScaleTransition(
                                  scale: curve,
                                  child: FadeTransition(opacity: anim1, child: child),
                                );
                              },
                            );

                            if (newPin == null || !context.mounted) return;

                            // 3. Confirm new PIN
                            bool confirmed = false;
                            await showGeneralDialog<void>(
                              context: context,
                              barrierDismissible: true,
                              barrierLabel: 'Confirm PIN',
                              barrierColor: Colors.black87,
                              transitionDuration: const Duration(milliseconds: 300),
                              pageBuilder: (context, anim1, anim2) {
                                return ParentalPinDialog(
                                  title: 'CONFIRM PIN',
                                  instruction: 'Re-enter your new 4-digit PIN to confirm',
                                  expectedPin: newPin,
                                  onSubmit: (pin) {
                                    if (pin == newPin) {
                                      confirmed = true;
                                      Navigator.of(context).pop();
                                    }
                                  },
                                );
                              },
                              transitionBuilder: (context, anim1, anim2, child) {
                                final curve = CurvedAnimation(parent: anim1, curve: Curves.easeInOutBack);
                                return ScaleTransition(
                                  scale: curve,
                                  child: FadeTransition(opacity: anim1, child: child),
                                );
                              },
                            );

                            if (confirmed && context.mounted) {
                              // Update local state
                              await ref.read(parentalLockProvider.notifier).updatePin(newPin!);
                              
                              // Sync with server based on auth type
                              try {
                                final auth = ref.read(authProvider);
                                if (auth.authType == 'stalker') {
                                  await ref.read(stalkerApiProvider).setParentPassword(newPin!);
                                } else if (auth.authType == 'xtream') {
                                  await ref.read(xtreamApiProvider).setParentPassword(newPin!);
                                }

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Parental PIN updated successfully on device and server')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Note: PIN updated on device, but server rejected changes: ${e.toString().replaceAll('Exception: ', '')}'),
                                      backgroundColor: AppColors.error,
                                      duration: const Duration(seconds: 8),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );

      case 2: // Diagnostics & Support Tools
        return ListView(
          padding: const EdgeInsets.all(AppDimensions.md),
          children: [
            _actionCard(
              context,
              'Problem Inspector',
              'Diagnose stream connectivity, loading performance, and network latencies.',
              Icons.troubleshoot_rounded,
              () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TechnicalInspectorScreen()));
              },
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              'Developer tools (MAG)',
              'Advanced sandbox tools, payload emulators, and active cookie inspectors.',
              Icons.developer_mode_rounded,
              () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticHarnessLayout()));
              },
              color: AppColors.textSecondary,
            ),
          ],
        );

      case 3: // System Actions
      default:
        return ListView(
          padding: const EdgeInsets.all(AppDimensions.md),
          children: [
            _actionCard(
              context,
              AppStrings.clearCache,
              'Clear local database models, cached images, and temporary cache directories.',
              Icons.delete_sweep_rounded,
              () async {
                final prefs = ref.read(preferencesProvider);
                await prefs.clearCacheOnly();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
              },
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              AppStrings.appInfo,
              'Check application legal disclaimers, framework components, and built versions.',
              Icons.info_outline,
              () {
                showAboutDialog(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: 'v${AppConfig.appVersion}',
                  applicationLegalese: '© 2026 SFLIXTV',
                );
              },
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              AppStrings.logout,
              'Log out from the current portal session and clear auto-login preferences.',
              Icons.logout_rounded,
              () async {
                await ref.read(authProvider.notifier).logout();
                widget.onLogout?.call();
              },
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            // Hidden developer backdoor
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
                  height: 48,
                  alignment: Alignment.center,
                  child: Text('v${AppConfig.appVersion} — System Diagnosis', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(AppStrings.profile),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT PANEL: Sidebar Categories (TV-style layout)
          Container(
            width: 220,
            decoration: const BoxDecoration(
              color: AppColors.backgroundLight,
              border: Border(right: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _sidebarCategoryItem(0, 'Account & Profile', Icons.person_rounded),
                _sidebarCategoryItem(1, 'Security & PIN', Icons.security_rounded),
                _sidebarCategoryItem(2, 'Diagnostics & Tools', Icons.troubleshoot_rounded),
                _sidebarCategoryItem(3, 'System Actions', Icons.settings_rounded),
              ],
            ),
          ),

          // RIGHT PANEL: Content Area corresponding to active category
          Expanded(
            child: Container(
              color: AppColors.background,
              child: _buildActiveCategoryContent(context, auth),
            ),
          ),
        ],
      ),
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
