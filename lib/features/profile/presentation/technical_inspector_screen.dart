import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/domain/providers.dart';

class TechnicalInspectorScreen extends ConsumerStatefulWidget {
  const TechnicalInspectorScreen({super.key});

  @override
  ConsumerState<TechnicalInspectorScreen> createState() => _TechnicalInspectorScreenState();
}

class _TechnicalInspectorScreenState extends ConsumerState<TechnicalInspectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _expandedLogIndices = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _safeCopyToClipboard(String text, String successMessage) {
    try {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(successMessage)),
            ],
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy to clipboard: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger();
    final logs = logger.logBuffer.reversed.toList(); // Newest first
    final auth = ref.watch(authProvider);

    // Apply search filter if active
    final filteredLogs = logs.where((log) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return log.message.toLowerCase().contains(query) ||
          log.tag.toLowerCase().contains(query) ||
          (log.error?.toLowerCase().contains(query) ?? false);
    }).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            'SYSTEM & LOG INSPECTOR',
            style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            tabs: [
              Tab(icon: Icon(Icons.health_and_safety_outlined, size: 18), text: 'HEALTH & STATS'),
              Tab(icon: Icon(Icons.swap_horiz_rounded, size: 18), text: 'NETWORK & APIS'),
              Tab(icon: Icon(Icons.code_rounded, size: 18), text: 'HYBRID FLOW'),
              Tab(icon: Icon(Icons.bug_report_outlined, size: 18), text: 'SYSTEM LOGS'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all_rounded, color: AppColors.primary),
              tooltip: 'Export Technical Report',
              onPressed: () {
                final report = logger.exportLogs();
                _safeCopyToClipboard(report, 'Complete diagnostic report exported! (${report.length} chars)');
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error),
              tooltip: 'Clear Log Buffer',
              onPressed: () {
                setState(() {
                  logger.clearBuffer();
                  _expandedLogIndices.clear();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log buffer successfully cleared.')),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Search Input Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: AppDimensions.sm),
              color: AppColors.backgroundLight,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Search or filter logs...',
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.black,
                  isDense: true,
                  contentPadding: const EdgeInsets.all(AppDimensions.sm),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
            
            // Tab contents
            Expanded(
              child: TabBarView(
                children: [
                  // TAB 1: HEALTH & STATS
                  _buildHealthTab(context, auth, logger),

                  // TAB 2: NETWORK & APIS
                  _buildLogsList(
                    filteredLogs.where((l) => l.tag == 'NETWORK' || l.tag.contains('WEB_REQUEST') || l.tag.contains('WEB_RESPONSE')).toList(),
                    'No network requests captured yet.',
                  ),

                  // TAB 3: HYBRID FLOW
                  _buildLogsList(
                    filteredLogs.where((l) => l.tag.startsWith('MAG') && !l.tag.contains('WEB_REQUEST') && !l.tag.contains('WEB_RESPONSE')).toList(),
                    'No Stalker bridge transactions recorded yet.',
                  ),

                  // TAB 4: SYSTEM LOGS
                  _buildLogsList(
                    filteredLogs.where((l) => l.tag == 'PLAYER' || l.tag == 'ENGINE' || l.level == LogLevel.error).toList(),
                    'No diagnostic system warnings or logs registered.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTab(BuildContext context, dynamic auth, AppLogger logger) {
    final lastProb = logger.lastCriticalProblem;
    final diagnosis = logger.diagnosis;

    return ListView(
      padding: const EdgeInsets.all(AppDimensions.md),
      children: [
        // System Diagnosis Badge
        Container(
          padding: const EdgeInsets.all(AppDimensions.lg),
          decoration: BoxDecoration(
            color: lastProb != null 
                ? AppColors.error.withValues(alpha: 0.1) 
                : AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(
              color: lastProb != null ? AppColors.error : AppColors.success,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    lastProb != null ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                    color: lastProb != null ? AppColors.error : AppColors.success,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    lastProb != null ? 'System Alert Active' : 'System Operational',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'monospace',
                      color: lastProb != null ? AppColors.error : AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                diagnosis,
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Session variables
        _sectionHeader('ACTIVE STB SESSION METRICS'),
        _buildMetricRow('STB MODEL', 'MAG250 (Infomir Emulation)'),
        _buildMetricRow('PORTAL URL', auth.portalUrl ?? 'N/A', enableCopy: true),
        _buildMetricRow('MAC ADDRESS', auth.macAddress ?? 'N/A', enableCopy: true),
        _buildMetricRow('SESSION TOKEN', auth.token ?? 'N/A', enableCopy: true),
        _buildMetricRow('COOKIES', logger.debugState.cookies.isNotEmpty ? logger.debugState.cookies : 'N/A', enableCopy: true),

        const SizedBox(height: 16),

        // Playback stats
        _sectionHeader('LAST RESOLVED PLAYBACK FLOW'),
        _buildMetricRow('SELECTED MEDIA', logger.debugState.selectedContent),
        _buildMetricRow('STALKER COMMAND', logger.debugState.cmd, enableCopy: true),
        _buildMetricRow('FILTERED COMMAND', logger.debugState.cleanedCmd),
        _buildMetricRow('RESOLVED URL', logger.debugState.resolvedUrl, enableCopy: true),
        _buildMetricRow('PLAYER HEADERS', logger.debugState.playerHeaders),
        _buildMetricRow('LAST ENGINE ERROR', logger.debugState.lastError),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          fontFamily: 'monospace',
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {bool enableCopy = false}) {
    final displayVal = value.trim().isEmpty ? 'NONE' : value;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              if (enableCopy && value.trim().isNotEmpty && value != 'N/A')
                InkWell(
                  onTap: () => _safeCopyToClipboard(value, '$label copied successfully!'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, color: AppColors.primary, size: 12),
                        SizedBox(width: 4),
                        Text('COPY', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            displayVal,
            style: TextStyle(
              fontSize: 12, 
              color: displayVal == 'NONE' || displayVal == 'N/A' ? AppColors.textHint : Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(List<LogEntry> logEntries, String emptyText) {
    if (logEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.textHint, size: 36),
              const SizedBox(height: 8),
              Text(
                emptyText,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDimensions.sm),
      itemCount: logEntries.length,
      itemBuilder: (context, index) {
        final log = logEntries[index];
        final hash = log.hashCode;
        final isExpanded = _expandedLogIndices.contains(hash);
        final isErr = log.level == LogLevel.error || log.tag.contains('ERROR');
        
        final timeStr = '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

        // Check if log contains request/response payload details that should make it interactive
        final bool hasPayload = log.message.contains('\n') || log.message.length > 150 || log.error != null;

        return Card(
          color: isErr ? AppColors.error.withValues(alpha: 0.1) : AppColors.surface,
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            side: BorderSide(
              color: isErr 
                  ? AppColors.error.withValues(alpha: 0.5) 
                  : (isExpanded ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: hasPayload
                ? () {
                    setState(() {
                      if (isExpanded) {
                        _expandedLogIndices.remove(hash);
                      } else {
                        _expandedLogIndices.add(hash);
                      }
                    });
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Log Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isErr ? AppColors.error : AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.tag,
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: const TextStyle(fontSize: 10, color: AppColors.textHint, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      if (hasPayload)
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 6),

                  // Log content
                  if (!isExpanded && hasPayload)
                    // Truncated preview text
                    Text(
                      log.message.split('\n').first,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isErr ? AppColors.error : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    // Full selectable message text
                    SelectableText(
                      log.message,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isErr ? AppColors.error : AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),

                  // Optional details error payload
                  if (log.error != null && isExpanded) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        'ERROR DETAIL:\n${log.error}',
                        style: const TextStyle(fontSize: 10, color: AppColors.error, fontFamily: 'monospace'),
                      ),
                    ),
                  ],

                  // Copy card logs button if expanded
                  if (isExpanded) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            final fullExport = '${log.toString()}${log.error != null ? '\nERROR: ${log.error}' : ''}';
                            _safeCopyToClipboard(fullExport, 'Single log block copied to clipboard!');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 12, color: AppColors.primary),
                          label: const Text('COPY LOG BLOCK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
