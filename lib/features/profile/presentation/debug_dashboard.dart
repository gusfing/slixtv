import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';

class DebugDashboard extends StatelessWidget {
  const DebugDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppLogger().debugState;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('DEBUG REPORT', style: TextStyle(fontFamily: 'monospace', color: AppColors.error)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: AppColors.error),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: AppColors.primary),
            tooltip: 'Copy Bug Export',
            onPressed: () {
              final report = _generateExport(state);
              Clipboard.setData(ClipboardData(text: report));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied bug report to clipboard!'), backgroundColor: AppColors.primary),
              );
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('SESSION', [
            _row('PORTAL', state.portalUrl),
            _row('MAC', state.macAddress),
            _row('TOKEN', state.token),
            _row('COOKIES', state.cookies),
          ]),
          const SizedBox(height: 16),
          _section('PLAYBACK DIAGNOSTICS', [
            _row('SELECTED', state.selectedContent),
            _row('ORIGINAL CMD', state.cmd),
            _row('CLEANED CMD', state.cleanedCmd),
            _row('CREATE_LINK REQ', state.requestPayload),
            _row('RAW RESPONSE', state.rawResponse),
            _row('RESOLVED URL', state.resolvedUrl),
            _row('PLAYER HEADERS', state.playerHeaders),
            _row('LAST ERROR', state.lastError),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 1.2)),
          const Divider(color: AppColors.border),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'NONE' : value,
              style: TextStyle(fontSize: 12, color: value.isEmpty ? AppColors.textHint : Colors.white, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  String _generateExport(DebugState state) {
    return '''APP VERSION: ${AppConfig.appVersion}
PORTAL: ${state.portalUrl}
MAC: ${state.macAddress}

AUTH:
TOKEN: ${state.token}
COOKIES: ${state.cookies}

PLAYBACK:
SELECTED: ${state.selectedContent}
ORIGINAL CMD: ${state.cmd}
CLEANED CMD: ${state.cleanedCmd}
CREATE_LINK REQUEST: ${state.requestPayload}
RAW RESPONSE: ${state.rawResponse}
RESOLVED URL: ${state.resolvedUrl}
PLAYER HEADERS: ${state.playerHeaders}
LAST ERROR: ${state.lastError}''';
  }
}
