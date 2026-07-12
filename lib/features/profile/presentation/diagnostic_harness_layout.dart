import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:better_player/better_player.dart';


import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/errors/exceptions.dart';
import '../../auth/data/stalker_api_service.dart';
import '../../movies/data/movies_service.dart';
import '../../movies/domain/models.dart' show VodItem;
import '../../auth/data/models.dart' show Category;
import '../../series/data/series_service.dart';
import '../../series/domain/models.dart' show SeriesItem, Season, Episode;
import '../../../core/utils/stalker_parser.dart';

enum DiagnosticScreen {
  portalConfig,
  sessionDashboard,
  cookieInspector,
  rawRequest,
  rawResponse,
  magAuth,
  liveTv,
  vodTester,
  seriesTester,
  headerDiff,
  webViewTester,
  playbackTester,
}

/// A comprehensive, debug-first developer console and IPTV diagnostic harness app layout.
class DiagnosticHarnessLayout extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;
  const DiagnosticHarnessLayout({super.key, this.onLogout});

  @override
  ConsumerState<DiagnosticHarnessLayout> createState() => _DiagnosticHarnessLayoutState();
}

class _DiagnosticHarnessLayoutState extends ConsumerState<DiagnosticHarnessLayout> with SingleTickerProviderStateMixin {
  DiagnosticScreen _currentScreen = DiagnosticScreen.portalConfig;
  bool _showBottomConsole = true;
  double _bottomConsoleHeight = 300.0;
  int _consoleTab = 0; // 0 = Logs, 1 = Network Inspector
  
  // Services
  late final StalkerApiService _stalkerService;
  late final MoviesService _moviesService;
  late final SeriesService _seriesService;
  final ApiClient _apiClient = ApiClient();
  final AppLogger _appLogger = AppLogger();

  // Active Network Log for inspection
  NetworkRequestLog? _inspectedRequest;

  @override
  void initState() {
    super.initState();
    _stalkerService = StalkerApiService();
    _moviesService = MoviesService(_apiClient);
    _seriesService = SeriesService(_apiClient);
    
    // Automatically pre-populate default debugging config if empty
    if (_apiClient.portalUrl == null || _apiClient.portalUrl!.isEmpty) {
      _apiClient.configure(
        portalUrl: 'http://tv.stream4k.cc',
        macAddress: '00:1E:99:2C:D2:08',
      );
    }
  }

  void _switchScreen(DiagnosticScreen screen) {
    setState(() {
      _currentScreen = screen;
    });
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            _buildTopBar(),
            
            // Middle Body Panel
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left-hand sidebar navigation
                  _buildSidebar(),
                  
                  // Vertical divider
                  Container(width: 1, color: AppColors.border),
                  
                  // Main dynamic screen container
                  Expanded(
                    child: Container(
                      color: AppColors.background,
                      child: _buildActiveScreen(),
                    ),
                  ),
                ],
              ),
            ),
            
            // Toggleable console panel boundary
            if (_showBottomConsole) ...[
              Container(height: 1, color: AppColors.border),
              _buildBottomConsole(),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Shell Core Layout Components ──────────────────────────────────────────

  Widget _buildTopBar() {
    final bool isCompact = MediaQuery.of(context).size.width < 700;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.developer_board, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isCompact ? 'SLIX HARNESS' : 'SLIX IPTV DIAGNOSTIC HARNESS',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (!isCompact)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'DEBUG ONLY',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showBottomConsole ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  color: AppColors.primary,
                ),
                tooltip: _showBottomConsole ? 'Collapse Inspector' : 'Expand Inspector',
                onPressed: () {
                  setState(() {
                    _showBottomConsole = !_showBottomConsole;
                  });
                },
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  _stalkerService.logout();
                  widget.onLogout?.call();
                },
                icon: const Icon(Icons.logout, size: 14),
                label: Text(isCompact ? 'EXIT' : 'EXIT HARNESS', style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final bool isCompact = MediaQuery.of(context).size.width < 700;
    return SizedBox(
      width: isCompact ? 50 : 240,
      child: Container(
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _sidebarCategory('CONFIGURATION & STATE'),
            _sidebarItem(DiagnosticScreen.portalConfig, '1. Portal Config', Icons.settings),
            _sidebarItem(DiagnosticScreen.sessionDashboard, '2. Session Dashboard', Icons.dashboard),
            _sidebarItem(DiagnosticScreen.cookieInspector, '3. Cookie Inspector', Icons.cookie),
            
            _sidebarCategory('RAW PACKET GENERATOR'),
            _sidebarItem(DiagnosticScreen.rawRequest, '4. Request Builder', Icons.send),
            _sidebarItem(DiagnosticScreen.rawResponse, '5. Response Inspector', Icons.find_in_page),
            
            _sidebarCategory('PROTOCOL ORCHESTRATION'),
            _sidebarItem(DiagnosticScreen.magAuth, '6. MAG Auth Tester', Icons.security),
            _sidebarItem(DiagnosticScreen.liveTv, '7. Live TV Tester', Icons.live_tv),
            _sidebarItem(DiagnosticScreen.vodTester, '8. VOD Tester', Icons.movie),
            _sidebarItem(DiagnosticScreen.seriesTester, '9. Series Tester', Icons.tv),
            
            _sidebarCategory('HYBRID TOOLS'),
            _sidebarItem(DiagnosticScreen.headerDiff, '10. Header Diff Tool', Icons.difference),
            _sidebarItem(DiagnosticScreen.webViewTester, '11. WebView Session', Icons.web),
            _sidebarItem(DiagnosticScreen.playbackTester, '12. Playback Tester', Icons.play_circle),
          ],
        ),
      ),
    );
  }

  Widget _sidebarCategory(String title) {
    final bool isCompact = MediaQuery.of(context).size.width < 700;
    if (isCompact) {
      return const Divider(height: 16, color: AppColors.border, thickness: 0.5);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _sidebarItem(DiagnosticScreen screen, String label, IconData icon) {
    final bool isCompact = MediaQuery.of(context).size.width < 700;
    final isSelected = _currentScreen == screen;
    
    if (isCompact) {
      return Tooltip(
        message: label,
        preferBelow: false,
        child: InkWell(
          onTap: () => _switchScreen(screen),
          child: Container(
            color: isSelected ? AppColors.surface : Colors.transparent,
            height: 48,
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                if (isSelected)
                  Positioned(
                    left: 0,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 3,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _switchScreen(screen),
      child: Container(
        color: isSelected ? AppColors.surface : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
            if (isSelected)
              Container(
                width: 4,
                height: 14,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomConsole() {
    return Container(
      height: _bottomConsoleHeight,
      color: Colors.black,
      child: Column(
        children: [
          // Console header controls
          Container(
            height: 36,
            color: AppColors.surface,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isConsoleCompact = constraints.maxWidth < 850;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _consoleTabButton(0, isConsoleCompact ? 'LOGS' : 'LIVE MEMORY LOGS', Icons.bug_report),
                        _consoleTabButton(1, isConsoleCompact ? 'NET (${_appLogger.networkRequests.length})' : 'NETWORK INSPECTOR (${_appLogger.networkRequests.length})', Icons.swap_horiz),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.clear_all, size: 16, color: AppColors.textSecondary),
                          tooltip: 'Clear Console',
                          onPressed: () {
                            setState(() {
                              if (_consoleTab == 0) {
                                _appLogger.clearBuffer();
                              } else {
                                _appLogger.clearNetworkRequests();
                                _inspectedRequest = null;
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_all, size: 16, color: AppColors.textSecondary),
                          tooltip: 'Copy Simple Console Logs',
                          onPressed: () {
                            final logs = _appLogger.exportLogs();
                            Clipboard.setData(ClipboardData(text: logs));
                            _toast('Logs exported to clipboard!');
                          },
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton.icon(
                          onPressed: () {
                            final conversation = _appLogger.exportConversationLogs();
                            Clipboard.setData(ClipboardData(text: conversation));
                            _toast('Full conversation logs copied!');
                          },
                          icon: const Icon(Icons.chat_bubble_outline, size: 14),
                          label: Text(
                            isConsoleCompact ? 'CONV' : 'COPY CONVERSATION',
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onVerticalDragUpdate: (details) {
                            setState(() {
                              _bottomConsoleHeight = (_bottomConsoleHeight - details.delta.dy).clamp(150.0, 600.0);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: Colors.transparent,
                            child: const Icon(Icons.drag_handle, size: 18, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Console body
          Expanded(
            child: _consoleTab == 0 ? _buildLogsView() : _buildNetworkInspectorView(),
          ),
        ],
      ),
    );
  }

  Widget _consoleTabButton(int index, String label, IconData icon) {
    final active = _consoleTab == index;
    return InkWell(
      onTap: () => setState(() => _consoleTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: active ? AppColors.primary : AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: active ? Colors.white : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Console Tab Views ─────────────────────────────────────────────────────

  bool _logsAutoScroll = true;
  String _logsFilter = '';

  Widget _buildLogsView() {
    var logs = _appLogger.logBuffer;
    if (_logsFilter.isNotEmpty) {
      final f = _logsFilter.toLowerCase();
      logs = logs.where((e) => e.message.toLowerCase().contains(f) || e.tag.toLowerCase().contains(f)).toList();
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black,
      child: Column(
        children: [
          // Filter Toolbar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    onChanged: (val) => setState(() => _logsFilter = val),
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: 'Filter log output...',
                      hintStyle: TextStyle(color: AppColors.textHint, fontSize: 11),
                      prefixIcon: Icon(Icons.search, size: 12, color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  const Text('AUTO-SCROLL: ', style: TextStyle(color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace')),
                  Switch(
                    value: _logsAutoScroll,
                    onChanged: (val) => setState(() => _logsAutoScroll = val),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Log List
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              controller: _logsAutoScroll ? ScrollController() : null,
              itemBuilder: (context, index) {
                final log = logs[index];
                Color entryColor = Colors.white;
                if (log.level == LogLevel.error) {
                  entryColor = AppColors.error;
                } else if (log.level == LogLevel.warning) {
                  entryColor = Colors.amber;
                } else if (log.tag == 'AUTH') {
                  entryColor = AppColors.primary;
                } else if (log.tag == 'COOKIES') {
                  entryColor = Colors.purpleAccent;
                } else if (log.tag == 'PLAYER') {
                  entryColor = Colors.cyanAccent;
                }
                
                final time = '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.0),
                  child: SelectableText(
                    '[$time] [${log.tag}] ${log.message}',
                    style: TextStyle(
                      color: entryColor,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkInspectorView() {
    final requests = _appLogger.networkRequests.reversed.toList();
    if (requests.isEmpty) {
      return const Center(
        child: Text(
          'No HTTP Requests Captured Yet.',
          style: TextStyle(color: AppColors.textTertiary, fontFamily: 'monospace'),
        ),
      );
    }
    
    return Row(
      children: [
        // Left side requests list
        SizedBox(
          width: 320,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: ListView.builder(
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final log = requests[index];
                final isSelected = _inspectedRequest?.id == log.id;
                final isErr = log.error != null || (log.responseStatus != null && log.responseStatus! >= 400);
                
                return InkWell(
                  onTap: () => setState(() => _inspectedRequest = log),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: isSelected ? AppColors.surface : Colors.transparent,
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              color: log.method == 'POST' ? Colors.blue : Colors.green,
                              child: Text(
                                log.method,
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
                              ),
                            ),
                            Text(
                              '${log.responseStatus ?? 'ERR'}',
                              style: TextStyle(
                                color: isErr ? AppColors.error : AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              '${log.duration.inMilliseconds}ms',
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          log.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        // Right side details view
        Expanded(
          child: _inspectedRequest == null 
              ? const Center(
                  child: Text(
                    'Select a request to inspect.',
                    style: TextStyle(color: AppColors.textTertiary, fontFamily: 'monospace'),
                  ),
                )
              : _buildNetworkRequestDetails(_inspectedRequest!),
        ),
      ],
    );
  }

  Widget _buildNetworkRequestDetails(NetworkRequestLog log) {
    final cleanUrl = Uri.parse(log.url);
    final isErr = log.error != null;
    
    return Container(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GENERAL', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
              ElevatedButton.icon(
                onPressed: () {
                  final curl = _generateCurl(log);
                  Clipboard.setData(ClipboardData(text: curl));
                  _toast('cURL Command Copied!');
                },
                icon: const Icon(Icons.copy, size: 12),
                label: const Text('COPY CURL', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.border),
          _detailRow('URL', log.url),
          _detailRow('METHOD', log.method),
          _detailRow('STATUS', '${log.responseStatus ?? 'FAILED'}'),
          _detailRow('TIME', '${log.timestamp}'),
          if (isErr) _detailRow('ERROR', log.error!, color: AppColors.error),
          
          const SizedBox(height: 12),
          const Text('QUERY PARAMETERS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          if (log.queryParams.isEmpty)
            const Text('NONE', style: TextStyle(color: AppColors.textHint, fontSize: 10, fontFamily: 'monospace'))
          else
            ...log.queryParams.entries.map((e) => _detailRow(e.key, '${e.value}')),

          const SizedBox(height: 12),
          const Text('REQUEST HEADERS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          ...log.requestHeaders.entries.map((e) => _detailRow(e.key, '${e.value}')),

          const SizedBox(height: 12),
          const Text('REQUEST COOKIES', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          Text(
            log.requestCookies.isEmpty ? 'NONE' : log.requestCookies,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
          ),

          const SizedBox(height: 12),
          const Text('REQUEST BODY', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          Text(
            log.requestBody == null ? 'EMPTY' : '${log.requestBody}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
          ),

          const SizedBox(height: 12),
          const Text('RESPONSE HEADERS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          ...log.responseHeaders.entries.map((e) => _detailRow(e.key, '${e.value}')),

          const SizedBox(height: 12),
          const Text('RESPONSE BODY', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          _buildPrettyResponseBody(log.rawResponseBody),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: color ?? Colors.white, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrettyResponseBody(String body) {
    if (body.isEmpty) {
      return const Text('EMPTY', style: TextStyle(color: AppColors.textHint, fontSize: 10, fontFamily: 'monospace'));
    }
    
    try {
      final decoded = jsonDecode(body);
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black,
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(decoded),
          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
        ),
      );
    } catch (_) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black,
        child: SelectableText(
          body,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
        ),
      );
    }
  }

  String _generateCurl(NetworkRequestLog log) {
    final buffer = StringBuffer();
    buffer.write('curl "${log.url}"');
    buffer.write(' -X ${log.method}');
    log.requestHeaders.forEach((key, val) {
      if (key.toLowerCase() != 'cookie') {
        buffer.write(' -H "$key: $val"');
      }
    });
    if (log.requestCookies.isNotEmpty) {
      buffer.write(' -H "Cookie: ${log.requestCookies}"');
    }
    if (log.requestBody != null) {
      buffer.write(' --data "${log.requestBody.toString().replaceAll('"', '\\"')}"');
    }
    return buffer.toString();
  }

  // ─── Active Screen Router ──────────────────────────────────────────────────

  Widget _buildActiveScreen() {
    switch (_currentScreen) {
      case DiagnosticScreen.portalConfig:
        return _buildPortalConfigScreen();
      case DiagnosticScreen.sessionDashboard:
        return _buildSessionDashboardScreen();
      case DiagnosticScreen.cookieInspector:
        return _buildCookieInspectorScreen();
      case DiagnosticScreen.rawRequest:
        return _buildRawRequestScreen();
      case DiagnosticScreen.rawResponse:
        return _buildRawResponseScreen();
      case DiagnosticScreen.magAuth:
        return _buildMagAuthScreen();
      case DiagnosticScreen.liveTv:
        return _buildLiveTvScreen();
      case DiagnosticScreen.vodTester:
        return _buildVodTesterScreen();
      case DiagnosticScreen.seriesTester:
        return _buildSeriesTesterScreen();
      case DiagnosticScreen.headerDiff:
        return _buildHeaderDiffScreen();
      case DiagnosticScreen.webViewTester:
        return _buildWebViewTesterScreen();
      case DiagnosticScreen.playbackTester:
        return _buildPlaybackTesterScreen();
    }
  }

  // ─── 1. Portal Config Screen ───────────────────────────────────────────────

  final _portalUrlController = TextEditingController(text: 'http://tv.stream4k.cc');
  final _macController = TextEditingController(text: '00:1E:99:2C:D2:08');
  final _timezoneController = TextEditingController(text: 'Asia/Kolkata');
  String _selectedStbModel = 'MAG250';
  String _selectedConnection = 'Ethernet';
  bool _urlEncodeMac = false;

  final Map<String, TextEditingController> _customHeaderKeys = {};
  final Map<String, TextEditingController> _customHeaderValues = {};
  final List<String> _headerRowIds = [];

  final Map<String, TextEditingController> _customCookieKeys = {};
  final Map<String, TextEditingController> _customCookieValues = {};
  final List<String> _cookieRowIds = [];

  Widget _buildPortalConfigScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('1. Portal Configuration', 'Initialize portal endpoints, MAC addresses, and emulation specs.'),
        
        _sectionTitleWidget('PRIMARY TARGET PARAMETERS'),
        _buildTextField('Portal URL', _portalUrlController, 'e.g. http://tv.stream4k.cc'),
        _buildTextField('MAC Address', _macController, 'e.g. 00:1E:99:2C:D2:08'),
        
        Row(
          children: [
            Expanded(
              child: _buildDropdownField('STB Emulation Model', _selectedStbModel, ['MAG250', 'MAG254', 'MAG322', 'MAG420'], (val) {
                if (val != null) setState(() => _selectedStbModel = val);
              }),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField('Network Link', _selectedConnection, ['Ethernet', 'WiFi'], (val) {
                if (val != null) setState(() => _selectedConnection = val);
              }),
            ),
          ],
        ),
        
        Row(
          children: [
            Expanded(
              child: _buildTextField('Timezone Identifier', _timezoneController, 'e.g. Asia/Kolkata'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('URL Encode MAC Colons', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('Replaces : with %3A', style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                      ],
                    ),
                    Switch(
                      value: _urlEncodeMac,
                      onChanged: (val) => setState(() => _urlEncodeMac = val),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        
        // Buttons
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _savePortalConfig,
              icon: const Icon(Icons.save),
              label: const Text('SAVE CONFIG', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _loadPreset,
              icon: const Icon(Icons.download),
              label: const Text('LOAD PRESET'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _portalUrlController.text = '';
                  _macController.text = '';
                  _timezoneController.text = 'Asia/Kolkata';
                  _selectedStbModel = 'MAG250';
                  _selectedConnection = 'Ethernet';
                  _urlEncodeMac = false;
                });
                _apiClient.clearSession();
                _toast('Configuration reset');
              },
              child: const Text('RESET', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ],
    );
  }

  void _savePortalConfig() {
    final url = _portalUrlController.text.trim();
    final mac = _macController.text.trim();
    
    if (url.isEmpty || mac.isEmpty) {
      _toast('URL and MAC address are required!', isError: true);
      return;
    }

    _apiClient.configure(portalUrl: url, macAddress: mac);
    
    // Save overrides
    _apiClient.updateConfig(
      stbModel: _selectedStbModel,
      connectionType: _selectedConnection,
      timezone: _timezoneController.text.trim(),
      urlEncodeMac: _urlEncodeMac,
    );

    _toast('Configuration committed successfully!');
  }

  void _loadPreset() {
    setState(() {
      _portalUrlController.text = 'http://tv.stream4k.cc';
      _macController.text = '00:1E:99:2C:D2:08';
      _timezoneController.text = 'Asia/Kolkata';
      _selectedStbModel = 'MAG250';
      _selectedConnection = 'Ethernet';
      _urlEncodeMac = false;
    });
    
    _apiClient.configure(
      portalUrl: 'http://tv.stream4k.cc',
      macAddress: '00:1E:99:2C:D2:08',
    );
    
    _apiClient.updateConfig(
      stbModel: 'MAG250',
      connectionType: 'Ethernet',
      timezone: 'Asia/Kolkata',
      urlEncodeMac: false,
    );

    _toast('Preset for Stream4K loaded!');
  }

  // ─── 2. Session Debug Dashboard ────────────────────────────────────────────

  Widget _buildSessionDashboardScreen() {
    final cookiesCount = _apiClient.token != null ? 3 : 1; // simulation
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('2. Session Dashboard', 'Live diagnostics, session ages, and token tracking.'),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildDashboardCard('SESSION INTEGRITY STATUS', [
                _dashboardField('API Endpoint Base', _apiClient.portalUrl ?? 'N/A'),
                _dashboardField('Emulated MAC', _apiClient.macAddress ?? 'N/A'),
                _dashboardField('Active Stalker Token', _apiClient.token ?? 'UNAUTHENTICATED (No Token)'),
                _dashboardField('Authentication status', _apiClient.token != null ? 'AUTHORIZED' : 'NOT AUTHORIZED', color: _apiClient.token != null ? AppColors.success : AppColors.error),
                _dashboardField('Current Dio Client Hash', 'identityHashCode: ${identityHashCode(_apiClient.dio)}'),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDashboardCard('STATE TELEMETRY', [
                _dashboardField('Cloudflare passed?', _apiClient.token != null ? 'YES (Bypassed)' : 'UNKNOWN', color: _apiClient.token != null ? AppColors.success : Colors.orange),
                _dashboardField('WebView loaded state', 'INACTIVE (WebView Tester)', color: AppColors.textTertiary),
                _dashboardField('Bridge connection ready?', _apiClient.token != null ? 'READY' : 'NOT READY', color: _apiClient.token != null ? AppColors.success : AppColors.error),
                _dashboardField('Target Model Presets', 'Model: ${_apiClient.stbModel} | Net: ${_apiClient.connectionType}'),
                _dashboardField('Timezone Cookie Value', _apiClient.timezone),
              ]),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('REFRESH telemetry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: Colors.white),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildDashboardCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12, fontFamily: 'monospace')),
          const Divider(color: AppColors.border),
          ...children,
        ],
      ),
    );
  }

  Widget _dashboardField(String label, String val, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(height: 2),
          SelectableText(
            val,
            style: TextStyle(color: color ?? Colors.white, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ─── 3. Cookie Inspector Screen ────────────────────────────────────────────

  List<Cookie> _cookieInspectorList = [];

  Widget _buildCookieInspectorScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('3. Cookie Inspector', 'Interactive inspector for current storage jar and portal cookies.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _refreshCookies,
              icon: const Icon(Icons.refresh),
              label: const Text('REFRESH COOKIES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _clearCookies,
              icon: const Icon(Icons.delete),
              label: const Text('CLEAR ALL COOKIES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _exportCookies,
              icon: const Icon(Icons.copy),
              label: const Text('EXPORT COOKIES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: Colors.white),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('NAME', style: TextStyle(color: AppColors.primary, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text('VALUE', style: TextStyle(color: AppColors.primary, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('DOMAIN', style: TextStyle(color: AppColors.primary, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                    Expanded(flex: 1, child: Text('PATH', style: TextStyle(color: AppColors.primary, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _cookieInspectorList.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'No active cookies in CookieJar. Trigger a handshake or WebView load first!',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cookieInspectorList.length,
                      itemBuilder: (context, index) {
                        final c = _cookieInspectorList[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border)),
                          ),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: SelectableText(c.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                              Expanded(flex: 3, child: SelectableText(c.value, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'))),
                              Expanded(flex: 2, child: SelectableText(c.domain ?? 'N/A', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace'))),
                              Expanded(flex: 1, child: SelectableText(c.path ?? '/', style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontFamily: 'monospace'))),
                            ],
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ],
    );
  }

  void _refreshCookies() async {
    final url = _apiClient.portalUrl;
    if (url == null || url.isEmpty) {
      _toast('Configure a Portal URL first!', isError: true);
      return;
    }
    
    try {
      final cookies = await _apiClient.cookieJar.loadForRequest(Uri.parse(url));
      setState(() {
        _cookieInspectorList = cookies;
      });
      _toast('Loaded ${cookies.length} cookies!');
    } catch (e) {
      _toast('Error loading cookies: $e', isError: true);
    }
  }

  void _clearCookies() async {
    await _apiClient.cookieJar.deleteAll();
    setState(() {
      _cookieInspectorList = [];
    });
    _toast('Cookie Jar Empty!');
  }

  void _exportCookies() {
    if (_cookieInspectorList.isEmpty) {
      _toast('No cookies to export!', isError: true);
      return;
    }
    
    final map = {
      for (final c in _cookieInspectorList) c.name: c.value,
    };
    final jsonStr = jsonEncode(map);
    Clipboard.setData(ClipboardData(text: jsonStr));
    _toast('Cookies exported as simple JSON object to clipboard!');
  }

  // ─── 4. Raw Request Console ────────────────────────────────────────────────

  String _requestMethod = 'GET';
  final _requestEndpointController = TextEditingController(text: '/stalker_portal/server/load.php');
  final List<MapEntry<String, String>> _requestQueryParams = [
    const MapEntry('type', 'stb'),
    const MapEntry('action', 'handshake'),
    const MapEntry('prehash', '0'),
    const MapEntry('JsHttpRequest', '1-xml'),
  ];
  final List<MapEntry<String, String>> _requestHeaders = [];
  final _requestBodyController = TextEditingController();

  Widget _buildRawRequestScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('4. Interactive Request Builder', 'Generate specific Stalker middleware packets directly.'),
        
        Row(
          children: [
            SizedBox(
              width: 100,
              child: _buildDropdownField('METHOD', _requestMethod, ['GET', 'POST'], (val) {
                if (val != null) setState(() => _requestMethod = val);
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField('RELATIVE ENDPOINT URL', _requestEndpointController, 'e.g. /stalker_portal/server/load.php'),
            ),
          ],
        ),
        
        _sectionTitleWidget('QUERY PARAMETERS'),
        _buildKeyValueEditor(_requestQueryParams),
        
        _sectionTitleWidget('ADDITIONAL SPECIFIC HEADERS OVERRIDE'),
        _buildKeyValueEditor(_requestHeaders),
        
        if (_requestMethod == 'POST') ...[
          _sectionTitleWidget('POST BODY DATA'),
          _buildTextField('BODY PAYLOAD', _requestBodyController, 'e.g. key=val&foo=bar'),
        ],
        
        const SizedBox(height: 16),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _sendRawRequest,
              icon: const Icon(Icons.send),
              label: const Text('SEND RAW DIOPACKET'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _copyRawAsCurl,
              icon: const Icon(Icons.code),
              label: const Text('COPY AS CURL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyValueEditor(List<MapEntry<String, String>> list) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          ...List.generate(list.length, (idx) {
            final entry = list[idx];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: TextEditingController(text: entry.key),
                        onChanged: (k) => list[idx] = MapEntry(k, entry.value),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: 'key',
                          filled: true,
                          fillColor: Colors.black,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: TextEditingController(text: entry.value),
                        onChanged: (v) => list[idx] = MapEntry(entry.key, v),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: 'value',
                          filled: true,
                          fillColor: Colors.black,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppColors.error, size: 18),
                    onPressed: () => setState(() => list.removeAt(idx)),
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => list.add(const MapEntry('', ''))),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('ADD ROW', style: TextStyle(fontSize: 10, fontFamily: 'monospace')),
            ),
          )
        ],
      ),
    );
  }

  void _sendRawRequest() async {
    final base = _apiClient.portalBase;
    if (base.isEmpty) {
      _toast('Configure Portal URL first!', isError: true);
      return;
    }
    
    final fullUrl = _apiClient.resolveUrl(_requestEndpointController.text.trim());
    
    final qParams = <String, String>{
      for (final e in _requestQueryParams)
        if (e.key.isNotEmpty) e.key: e.value,
    };
    
    final headers = <String, String>{
      for (final e in _requestHeaders)
        if (e.key.isNotEmpty) e.key: e.value,
    };

    _toast('Sending Request...');
    
    try {
      Response response;
      if (_requestMethod == 'POST') {
        response = await _apiClient.dio.post(
          fullUrl,
          queryParameters: qParams,
          data: _requestBodyController.text,
          options: Options(headers: headers, validateStatus: (s) => s != null && s < 600),
        );
      } else {
        response = await _apiClient.dio.get(
          fullUrl,
          queryParameters: qParams,
          options: Options(headers: headers, validateStatus: (s) => s != null && s < 600),
        );
      }
      
      _toast('Request Completed! Status: ${response.statusCode}');
      setState(() {
        _currentScreen = DiagnosticScreen.rawResponse;
      });
    } catch (e) {
      _toast('Request Failed: $e', isError: true);
    }
  }

  void _copyRawAsCurl() {
    final fullUrl = _apiClient.resolveUrl(_requestEndpointController.text.trim());
    final qParams = <String, String>{
      for (final e in _requestQueryParams)
        if (e.key.isNotEmpty) e.key: e.value,
    };
    
    final uri = Uri.parse(fullUrl).replace(queryParameters: qParams);
    
    final buffer = StringBuffer();
    buffer.write('curl "${uri.toString()}"');
    buffer.write(' -X $_requestMethod');
    
    for (final e in _requestHeaders) {
      if (e.key.isNotEmpty) {
        buffer.write(' -H "${e.key}: ${e.value}"');
      }
    }
    
    if (_requestMethod == 'POST' && _requestBodyController.text.isNotEmpty) {
      buffer.write(' --data "${_requestBodyController.text.replaceAll('"', '\\"')}"');
    }
    
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _toast('cURL copied to clipboard!');
  }

  // ─── 5. Raw Response Inspector Screen ──────────────────────────────────────

  Widget _buildRawResponseScreen() {
    final netLogs = _appLogger.networkRequests;
    if (netLogs.isEmpty) {
      return const Center(
        child: Text(
          'No Transactions Sent Yet.',
          style: TextStyle(color: AppColors.textTertiary, fontFamily: 'monospace'),
        ),
      );
    }
    
    final lastLog = netLogs.last;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('5. Raw Response Inspector', 'Response details of the absolute last executed request.'),
        
        _buildDashboardCard('RESPONSE GENERAL', [
          _dashboardField('Request Target URL', lastLog.url),
          _dashboardField('Method Used', lastLog.method),
          _dashboardField('Status Code', '${lastLog.responseStatus ?? 'N/A'}'),
          _dashboardField('Execution Duration', '${lastLog.duration.inMilliseconds}ms'),
        ]),
        
        const SizedBox(height: 12),
        const Text('RESPONSE HEADERS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
        const Divider(color: AppColors.border),
        ...lastLog.responseHeaders.entries.map((e) => _detailRow(e.key, '${e.value}')),
        
        const SizedBox(height: 12),
        const Text('RESPONSE BODY CONTENT', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
        const Divider(color: AppColors.border),
        _buildPrettyResponseBody(lastLog.rawResponseBody),
      ],
    );
  }

  // ─── 6. MAG Auth Tester Screen ─────────────────────────────────────────────

  String _magAuthLogs = '';
  
  Widget _buildMagAuthScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('6. MAG Handshake & Auth Suite', 'Manually coordinate steps of portal authentication pipeline.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _magAuthStep1Handshake,
              icon: const Icon(Icons.handshake),
              label: const Text('STEP 1: HANDSHAKE'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _magAuthStep2GetProfile,
              icon: const Icon(Icons.person),
              label: const Text('STEP 2: GET PROFILE'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _magAuthStep3GetMainInfo,
              icon: const Icon(Icons.dns),
              label: const Text('STEP 3: GET MAIN INFO'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        Container(
          height: 350,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('AUTH TEST LOGS', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => setState(() => _magAuthLogs = ''),
                    child: const Text('CLEAR', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                  ),
                ],
              ),
              const Divider(color: AppColors.border),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _magAuthLogs.isEmpty ? 'No events recorded. Click buttons above to start Stalker Auth sequence.' : _magAuthLogs,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _logMagAuth(String msg) {
    setState(() {
      _magAuthLogs += '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg\n';
    });
  }

  void _magAuthStep1Handshake() async {
    final url = _apiClient.portalUrl;
    final mac = _apiClient.macAddress;
    
    if (url == null || url.isEmpty || mac == null || mac.isEmpty) {
      _toast('Configure Config Screen First!', isError: true);
      return;
    }
    
    _logMagAuth('>>> Step 1: Handshake initiation for url=$url mac=$mac');
    try {
      final token = await _stalkerService.handshake(url, mac);
      _logMagAuth('<<< SUCCESS! Token retrieved: $token');
      _toast('Handshake succeeded!');
    } catch (e) {
      _logMagAuth('!!! ERROR: $e');
      _toast('Handshake Failed!', isError: true);
    }
  }

  void _magAuthStep2GetProfile() async {
    if (_apiClient.token == null) {
      _toast('Run Handshake First!', isError: true);
      return;
    }
    
    _logMagAuth('>>> Step 2: Requesting profile details via get_profile');
    try {
      final profile = await _stalkerService.getProfile();
      _logMagAuth('<<< SUCCESS! Name: ${profile.name} | Status: ${profile.status} | IP: ${profile.ip}');
      _toast('Profile Succeeded!');
    } catch (e) {
      _logMagAuth('!!! ERROR: $e');
      _toast('Profile Failed!', isError: true);
    }
  }

  void _magAuthStep3GetMainInfo() async {
    if (_apiClient.token == null) {
      _toast('Run Handshake First!', isError: true);
      return;
    }
    
    _logMagAuth('>>> Step 3: Requesting main info details');
    try {
      final info = await _stalkerService.getMainInfo();
      _logMagAuth('<<< SUCCESS! Server Name: ${info.serverName}');
      _toast('Main Info Succeeded!');
    } catch (e) {
      _logMagAuth('!!! ERROR: $e');
      _toast('Main Info Failed!', isError: true);
    }
  }

  // ─── 7. Live TV Tester Screen ──────────────────────────────────────────────

  List<Category> _liveGenres = [];
  List<dynamic> _liveChannels = [];
  String? _selectedLiveGenreId;

  Widget _buildLiveTvScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('7. Live TV Telemetry', 'Check genre fetches and channel listing streams directly.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _getLiveGenres,
              icon: const Icon(Icons.category),
              label: const Text('GET GENRES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            if (_liveGenres.isNotEmpty) ...[
              Expanded(
                child: _buildDropdownField('Active Genre', _selectedLiveGenreId ?? '*', [
                  '*',
                  ..._liveGenres.map((g) => g.id),
                ], (val) {
                  if (val != null) {
                    setState(() {
                      _selectedLiveGenreId = val;
                    });
                    _getLiveChannels();
                  }
                }),
              ),
            ],
          ],
        ),
        
        const SizedBox(height: 12),
        
        if (_liveChannels.isNotEmpty) ...[
          _sectionTitleWidget('AVAILABLE CHANNELS (${_liveChannels.length})'),
          Container(
            height: 350,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              itemCount: _liveChannels.length,
              itemBuilder: (context, index) {
                final ch = _liveChannels[index];
                final name = ch.name ?? 'Channel';
                final number = ch.number ?? '${index + 1}';
                final cmd = ch.cmd ?? '';
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(number, style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: Text(cmd, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontFamily: 'monospace')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => _testCreateLink(cmd, 'itv'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        child: const Text('RESOLVE', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _getLiveGenres() async {
    if (_apiClient.token == null) {
      _toast('Authenticate first (Run Handshake)!', isError: true);
      return;
    }
    _toast('Fetching genres...');
    try {
      final genres = await _stalkerService.getCategories('itv');
      setState(() {
        _liveGenres = genres;
        if (genres.isNotEmpty) {
          _selectedLiveGenreId = genres.first.id;
        }
      });
      _toast('Loaded ${genres.length} genres!');
      if (genres.isNotEmpty) _getLiveChannels();
    } catch (e) {
      _toast('Genres fetch failed: $e', isError: true);
    }
  }

  void _getLiveChannels() async {
    _toast('Fetching channels...');
    try {
      final channels = await _stalkerService.getChannels(categoryId: _selectedLiveGenreId);
      setState(() {
        _liveChannels = channels;
      });
      _toast('Loaded ${channels.length} channels!');
    } catch (e) {
      _toast('Channels fetch failed: $e', isError: true);
    }
  }

  void _testCreateLink(String cmd, String type) async {
    _toast('Executing create_link for cmd=$cmd...');
    try {
      final resolved = await _stalkerService.createLink(cmd, type);
      _toast('RESOLVED stream successfully!');
      
      // Auto-populate to Playback Tester
      setState(() {
        _playbackUrlController.text = resolved;
        _currentScreen = DiagnosticScreen.playbackTester;
      });
    } catch (e) {
      if (e is CreateLinkException) {
        _toast('FAILED: ${e.message}', isError: true);
        
        // Push raw response details directly to Response screen
        setState(() {
          _currentScreen = DiagnosticScreen.rawResponse;
        });
      } else {
        _toast('FAILED: $e', isError: true);
      }
    }
  }

  void _testSeriesEpisodeCreateLink(Episode ep) async {
    String targetCmd = ep.cmd;
    if (targetCmd.isEmpty && _selectedSeriesId != null) {
      _toast('Resolving episode command...');
      try {
        final seasonId = ep.rawJson?['season_id']?.toString() ?? '';
        final response = await _stalkerService.resolveEpisodeFileResponse(
          seriesId: _selectedSeriesId!,
          episodeId: ep.id,
          seasonId: seasonId,
        );
        debugPrint('RAW_SERIES_EPISODE_RESPONSE: $response');
        final js = response['js'];
        if (js != null && js != false) {
          final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
          if (rawList.isNotEmpty) {
            final firstItem = rawList.first;
            if (firstItem is Map<String, dynamic>) {
              final fileId = firstItem['id']?.toString();
              if (fileId != null && fileId.isNotEmpty) {
                targetCmd = '/media/file_$fileId.mpg';
              }
            }
          }
        }
      } catch (e) {
        _toast('Resolve failed: $e', isError: true);
      }
    } else {
      debugPrint('RAW_SERIES_EPISODE_RESPONSE: {}');
    }

    debugPrint('SELECTED_EPISODE_JSON: ${ep.rawJson}');
    debugPrint('SELECTED_EPISODE_CMD: $targetCmd');
    _testCreateLink(targetCmd, 'series');
  }

  // ─── 8. VOD Tester Screen ──────────────────────────────────────────────────

  List<Category> _vodCategories = [];
  List<VodItem> _vodMovies = [];
  String? _selectedVodCatId;
  final _manualMovieCmdController = TextEditingController();

  Widget _buildVodTesterScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('8. VOD Movie Telemetry', 'Request video category details and descriptions directly.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _getVodCategories,
              icon: const Icon(Icons.movie_creation),
              label: const Text('GET VOD CATEGORIES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            if (_vodCategories.isNotEmpty) ...[
              Expanded(
                child: _buildDropdownField('Active Category', _selectedVodCatId ?? '*', [
                  '*',
                  ..._vodCategories.map((g) => g.id),
                ], (val) {
                  if (val != null) {
                    setState(() {
                      _selectedVodCatId = val;
                    });
                    _getVodMovies();
                  }
                }),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),
        
        // Manual override inputs
        _buildDashboardCard('QUICK COMMAND OVERRIDE TEST', [
          _buildTextField('Manual Command Override String', _manualMovieCmdController, 'e.g. /media/464066.mpg'),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: () {
              final cmd = _manualMovieCmdController.text.trim();
              if (cmd.isNotEmpty) {
                _testCreateLink(cmd, 'vod');
              }
            },
            child: const Text('RESOLVE DIRECT VOD OVERRIDE'),
          ),
        ]),
        
        const SizedBox(height: 12),
        
        if (_vodMovies.isNotEmpty) ...[
          _sectionTitleWidget('AVAILABLE MOVIES (${_vodMovies.length})'),
          Container(
            height: 350,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              itemCount: _vodMovies.length,
              itemBuilder: (context, index) {
                final movie = _vodMovies[index];
                final title = movie.name;
                final cmd = movie.cmd;
                
                return ListTile(
                  leading: const Icon(Icons.movie, color: Colors.amber),
                  title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: Text('id=${movie.id} | cmd=$cmd', style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontFamily: 'monospace')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => _testVodDescription(movie),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                        child: const Text('GET DESC', style: TextStyle(fontSize: 10)),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: () => _testVodCreateLink(movie),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        child: const Text('RESOLVE', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _getVodCategories() async {
    if (_apiClient.token == null) {
      _toast('Authenticate first (Run Handshake)!', isError: true);
      return;
    }
    _toast('Fetching VOD categories...');
    try {
      final cats = await _moviesService.getCategories();
      setState(() {
        _vodCategories = cats;
        if (cats.isNotEmpty) {
          _selectedVodCatId = cats.first.id;
        }
      });
      _toast('Loaded ${cats.length} VOD categories!');
      if (cats.isNotEmpty) _getVodMovies();
    } catch (e) {
      _toast('VOD categories failed: $e', isError: true);
    }
  }

  void _getVodMovies() async {
    _toast('Fetching movies list...');
    try {
      final movies = await _moviesService.getOrderedList(categoryId: _selectedVodCatId);
      setState(() {
        _vodMovies = movies;
      });
      _toast('Loaded ${movies.length} movies!');
    } catch (e) {
      _toast('Movies failed: $e', isError: true);
    }
  }

  void _testVodDescription(VodItem movie) async {
    _toast('Fetching movie description details...');
    try {
      final details = await _moviesService.getVodInfo(movie);
      if (details != null) {
        _toast('SUCCESS! Override Cmd: ${details.cmd}');
        _manualMovieCmdController.text = details.cmd;
        
        // Show info
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.backgroundLight,
            title: Text(details.name, style: const TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Command: ${details.cmd}', style: const TextStyle(color: AppColors.primary, fontFamily: 'monospace', fontSize: 11)),
                  const SizedBox(height: 8),
                  Text('Description: ${details.description}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Director: ${details.director}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Text('Actors: ${details.actors}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      _toast('Get info failed: $e', isError: true);
    }
  }

  void _testVodCreateLink(VodItem movie) async {
    _toast('Executing createVodLink for movie=${movie.name}...');
    try {
      // Pre-fetch enriched VOD info to obtain the real media path (via get_description / get_info)
      var finalMovie = movie;
      try {
        final enriched = await _moviesService.getVodInfo(movie);
        if (enriched != null) {
          finalMovie = enriched;
        }
      } catch (e) {
        _appLogger.w('DIAG_VOD_TESTER', 'Pre-fetching getVodInfo failed, using raw list command: $e');
      }

      final resolved = await _moviesService.createVodLink(finalMovie);
      _toast('RESOLVED stream successfully!');
      
      setState(() {
        _playbackUrlController.text = resolved;
        _currentScreen = DiagnosticScreen.playbackTester;
      });
    } catch (e) {
      if (e is CreateLinkException) {
        _toast('FAILED: ${e.message}', isError: true);
        setState(() {
          _currentScreen = DiagnosticScreen.rawResponse;
        });
      } else {
        _toast('FAILED: $e', isError: true);
      }
    }
  }

  // ─── 9. Series Tester Screen ───────────────────────────────────────────────

  List<Category> _seriesCategories = [];
  List<SeriesItem> _seriesList = [];
  List<Season> _seriesSeasons = [];
  String? _selectedSeriesCatId;
  String? _selectedSeriesId;

  Widget _buildSeriesTesterScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('9. Series / TV Shows Telemetry', 'Inspect series categories and season arrays.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _getSeriesCategories,
              icon: const Icon(Icons.tv),
              label: const Text('GET SERIES CATEGORIES'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            if (_seriesCategories.isNotEmpty) ...[
              Expanded(
                child: _buildDropdownField('Active Category', _selectedSeriesCatId ?? '*', [
                  '*',
                  ..._seriesCategories.map((g) => g.id),
                ], (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSeriesCatId = val;
                    });
                    _getSeriesList();
                  }
                }),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),
        
        if (_seriesList.isNotEmpty) ...[
          _sectionTitleWidget('AVAILABLE SERIES (${_seriesList.length})'),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              itemCount: _seriesList.length,
              itemBuilder: (context, index) {
                final series = _seriesList[index];
                return ListTile(
                  leading: const Icon(Icons.queue_play_next, color: Colors.purpleAccent),
                  title: Text(series.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text('id=${series.id} | count=${series.seriesCount}', style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                  trailing: ElevatedButton(
                    onPressed: () => _getSeriesSeasons(series.id, series.cmd),
                    child: const Text('LOAD SEASONS', style: TextStyle(fontSize: 10)),
                  ),
                );
              },
            ),
          ),
        ],

        if (_seriesSeasons.isNotEmpty) ...[
          _sectionTitleWidget('SEASONS & EPISODES MAP'),
          ..._seriesSeasons.map((season) {
            return ExpansionTile(
              title: Text(season.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('${season.episodes.length} Episode(s) found'),
              children: season.episodes.map((ep) {
                return ListTile(
                  dense: true,
                  title: Text('EP ${ep.episodeNumber}: ${ep.name}', style: const TextStyle(color: Colors.greenAccent)),
                  subtitle: Text(ep.cmd, style: const TextStyle(color: AppColors.textTertiary, fontSize: 9, fontFamily: 'monospace')),
                  trailing: ElevatedButton(
                    onPressed: () => _testSeriesEpisodeCreateLink(ep),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                    child: const Text('RESOLVE', style: TextStyle(fontSize: 9)),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ],
    );
  }

  void _getSeriesCategories() async {
    if (_apiClient.token == null) {
      _toast('Authenticate first (Run Handshake)!', isError: true);
      return;
    }
    _toast('Fetching Series categories...');
    try {
      final cats = await _seriesService.getCategories();
      setState(() {
        _seriesCategories = cats;
        if (cats.isNotEmpty) {
          _selectedSeriesCatId = cats.first.id;
        }
      });
      _toast('Loaded ${cats.length} Series categories!');
      if (cats.isNotEmpty) _getSeriesList();
    } catch (e) {
      _toast('Series categories failed: $e', isError: true);
    }
  }

  void _getSeriesList() async {
    _toast('Fetching series list...');
    try {
      final list = await _seriesService.getOrderedList(categoryId: _selectedSeriesCatId);
      setState(() {
        _seriesList = list;
        _seriesSeasons = [];
      });
      _toast('Loaded ${list.length} series!');
    } catch (e) {
      _toast('Series list failed: $e', isError: true);
    }
  }

  void _getSeriesSeasons(String seriesId, String seriesCmd) async {
    _toast('Loading seasons hierarchy...');
    try {
      final seasons = await _seriesService.getSeriesInfo(seriesId, seriesCmd: seriesCmd);
      setState(() {
        _seriesSeasons = seasons;
        _selectedSeriesId = seriesId;
      });
      _toast('Built ${seasons.length} seasons!');
    } catch (e) {
      _toast('Seasons fetch failed: $e', isError: true);
    }
  }

  // ─── 10. Header Diff Tool Screen ───────────────────────────────────────────

  final _diffSubeInputController = TextEditingController();
  String _diffOutputString = '';

  Widget _buildHeaderDiffScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('10. Header Diff / Comparison', 'Compare outbound headers directly against Charles / STBEmu logs.'),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PASTE RAW HTTP REQUEST HEADERS FROM STBEMU', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _diffSubeInputController,
                    maxLines: 8,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'GET /stalker_portal/server/load.php HTTP/1.1\nUser-Agent: Mozilla/5.0...\nCookie: mac=00:1e...',
                      filled: true,
                      fillColor: Colors.black,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACTIVE APP OUTBOUND HEADERS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  const SizedBox(height: 6),
                  Container(
                    height: 160,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: AppColors.surface,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _getCurrentActiveHeadersString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _performHeaderDiff,
          icon: const Icon(Icons.difference),
          label: const Text('CALCULATE AND DIFF HEADERS'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
        ),
        
        if (_diffOutputString.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitleWidget('DIFFERENCES REPORT'),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              _diffOutputString,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ]
      ],
    );
  }

  String _getCurrentActiveHeadersString() {
    final buffer = StringBuffer();
    buffer.writeln('User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3');
    buffer.writeln('X-User-Agent: Model: ${_apiClient.stbModel}; Link: ${_apiClient.connectionType}');
    buffer.writeln('Referer: ${_apiClient.portalBase}/c/');
    buffer.writeln('MAC: ${_apiClient.macAddress}');
    if (_apiClient.token != null) {
      buffer.writeln('Authorization: Bearer ${_apiClient.token}');
      buffer.writeln('Cookie: mac=${_apiClient.macAddress}; token=${_apiClient.token}; stb_lang=en; timezone=${_apiClient.timezone}');
    } else {
      buffer.writeln('Cookie: mac=${_apiClient.macAddress}; stb_lang=en; timezone=${_apiClient.timezone}');
    }
    return buffer.toString();
  }

  void _performHeaderDiff() {
    final rawInput = _diffSubeInputController.text.trim();
    if (rawInput.isEmpty) {
      _toast('Paste raw headers first!', isError: true);
      return;
    }
    
    // Parse STBEmu headers
    final emuHeaders = <String, String>{};
    final emuCookies = <String, String>{};
    
    final lines = rawInput.split('\n');
    for (final line in lines) {
      if (line.contains(':')) {
        final idx = line.indexOf(':');
        final key = line.substring(0, idx).trim().toLowerCase();
        final val = line.substring(idx + 1).trim();
        
        if (key == 'cookie') {
          for (final pair in val.split(';')) {
            final idxEq = pair.indexOf('=');
            if (idxEq > 0) {
              emuCookies[pair.substring(0, idxEq).trim()] = pair.substring(idxEq + 1).trim();
            }
          }
        } else {
          emuHeaders[key] = val;
        }
      }
    }
    
    // Build App headers
    final appHeaders = <String, String>{
      'user-agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'x-user-agent': 'Model: ${_apiClient.stbModel}; Link: ${_apiClient.connectionType}',
      'referer': '${_apiClient.portalBase}/c/',
      'mac': _apiClient.macAddress ?? '',
    };
    if (_apiClient.token != null) {
      appHeaders['authorization'] = 'Bearer ${_apiClient.token}';
    }
    
    final appCookies = <String, String>{
      'mac': _apiClient.macAddress ?? '',
      'stb_lang': 'en',
      'timezone': _apiClient.timezone,
    };
    if (_apiClient.token != null) {
      appCookies['token'] = _apiClient.token!;
    }
    
    // Diff Logic
    final buffer = StringBuffer();
    buffer.writeln('=== HEADERS DIFF REPORT ===');
    
    buffer.writeln('\n1. HEADER MISMATCHES:');
    appHeaders.forEach((key, appVal) {
      if (!emuHeaders.containsKey(key)) {
        buffer.writeln('[-] MISSING in STBEmu request: "$key" (App uses: "$appVal")');
      } else {
        final emuVal = emuHeaders[key]!;
        if (emuVal != appVal) {
          buffer.writeln('[!] VALUE MISMATCH for "$key":');
          buffer.writeln('    STBEmu: "$emuVal"');
          buffer.writeln('    App   : "$appVal"');
        }
      }
    });
    
    emuHeaders.forEach((key, emuVal) {
      if (!appHeaders.containsKey(key) && key != 'host' && key != 'connection' && key != 'accept-encoding') {
        buffer.writeln('[+] EXTRA in STBEmu request (Missing in App): "$key" ("$emuVal")');
      }
    });
    
    buffer.writeln('\n2. COOKIE MISMATCHES:');
    appCookies.forEach((key, appVal) {
      if (!emuCookies.containsKey(key)) {
        buffer.writeln('[-] Cookie missing in STBEmu: "$key" (App uses: "$appVal")');
      } else {
        final emuVal = emuCookies[key]!;
        if (emuVal != appVal) {
          buffer.writeln('[!] Cookie value mismatch for "$key":');
          buffer.writeln('    STBEmu: "$emuVal"');
          buffer.writeln('    App   : "$appVal"');
        }
      }
    });
    
    emuCookies.forEach((key, emuVal) {
      if (!appCookies.containsKey(key)) {
        buffer.writeln('[+] Extra cookie in STBEmu (Missing in App): "$key" ("$emuVal")');
      }
    });
    
    setState(() {
      _diffOutputString = buffer.toString();
    });
  }

  // ─── 11. WebView Session Screen ────────────────────────────────────────────

  webview.InAppWebViewController? _webViewController;
  bool _webviewVisible = true;
  String _webviewLogs = '';

  Widget _buildWebViewTesterScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('11. Hybrid WebView Inspector', 'Embedded webview loader for Cloudflare bypass & JS inspections.'),
        
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _webviewLoadPortal,
              icon: const Icon(Icons.web),
              label: const Text('LOAD PORTAL URL'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _webviewSyncCookies,
              icon: const Icon(Icons.sync),
              label: const Text('SYNC COOKIES TO DIO'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _webviewDumpVars,
              icon: const Icon(Icons.summarize),
              label: const Text('DUMP VARIABLES'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                const Text('VISIBLE: ', style: TextStyle(color: Colors.white, fontSize: 11)),
                Switch(
                  value: _webviewVisible,
                  onChanged: (val) => setState(() => _webviewVisible = val),
                  activeColor: AppColors.primary,
                ),
              ],
            )
          ],
        ),
        
        const SizedBox(height: 12),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_webviewVisible)
              Expanded(
                flex: 1,
                child: Container(
                  height: 350,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                  ),
                  child: webview.InAppWebView(
                    initialUrlRequest: webview.URLRequest(
                      url: webview.WebUri(_apiClient.portalUrl ?? 'http://tv.stream4k.cc'),
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    onLoadStop: (controller, url) {
                      _logWebView('Page loaded stop: $url');
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      _logWebView('Console JS: ${consoleMessage.message}');
                    },
                  ),
                ),
              )
            else
              const Expanded(
                flex: 1,
                child: SizedBox(
                  height: 350,
                  child: Center(
                    child: Text('WebView is currently Hidden (Saves Layout)', style: TextStyle(color: AppColors.textTertiary)),
                  ),
                ),
              ),
            
            const SizedBox(width: 16),
            
            Expanded(
              flex: 1,
              child: Container(
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('WEBVIEW EVENT LOGS', style: TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => setState(() => _webviewLogs = ''),
                          child: const Text('CLEAR', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.border),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _webviewLogs.isEmpty ? 'No WebView interactions yet.' : _webviewLogs,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _logWebView(String msg) {
    setState(() {
      _webviewLogs += '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg\n';
    });
  }

  void _webviewLoadPortal() {
    final url = _apiClient.portalUrl;
    if (url == null || url.isEmpty || _webViewController == null) {
      _toast('WebView controller not ready or url empty!', isError: true);
      return;
    }
    
    _logWebView('Loading portal into WebView: $url');
    _webViewController!.loadUrl(urlRequest: webview.URLRequest(url: webview.WebUri(url)));
  }

  void _webviewSyncCookies() async {
    final url = _apiClient.portalUrl;
    if (url == null || url.isEmpty) {
      _toast('No portal URL configured!', isError: true);
      return;
    }
    
    _logWebView('Syncing cookies from WebView to Dio CookieJar...');
    try {
      final cookieManager = webview.CookieManager.instance();
      final webCookies = await cookieManager.getCookies(url: webview.WebUri(url));
      
      final dioCookies = <Cookie>[];
      for (final wc in webCookies) {
        dioCookies.add(Cookie(wc.name, wc.value.toString())
          ..domain = wc.domain
          ..path = wc.path
          ..expires = wc.expiresDate != null ? DateTime.fromMillisecondsSinceEpoch(wc.expiresDate!) : null
          ..secure = wc.isSecure ?? false
          ..httpOnly = wc.isHttpOnly ?? false
        );
        _logWebView('Extracted: ${wc.name}=${wc.value}');
      }
      
      await _apiClient.cookieJar.saveFromResponse(Uri.parse(url), dioCookies);
      _toast('Sync Complete! Added ${dioCookies.length} cookies.');
    } catch (e) {
      _logWebView('Sync Error: $e');
      _toast('Sync failed!', isError: true);
    }
  }

  void _webviewDumpVars() async {
    if (_webViewController == null) return;
    
    _logWebView('Dumping Javascript window details...');
    try {
      final cookie = await _webViewController!.evaluateJavascript(source: 'document.cookie');
      _logWebView('document.cookie: $cookie');
      
      final stb = await _webViewController!.evaluateJavascript(source: 'typeof window.stb !== "undefined" ? JSON.stringify(window.stb) : "undefined"');
      _logWebView('window.stb: $stb');
    } catch (e) {
      _logWebView('Dump Error: $e');
    }
  }

  // ─── 12. Playback Tester Screen ────────────────────────────────────────────

  final _playbackUrlController = TextEditingController();
  
  BetterPlayerController? _diagVideoController;
  final List<String> _playbackEvents = [];

  Widget _buildPlaybackTesterScreen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _screenTitle('12. Premium VideoPlayer Diagnostic Panel', 'Test direct stream loading, and trace buffer logs live.'),
        
        Row(
          children: [
            Expanded(
              child: _buildTextField('DIRECT STREAM PLAYBACK URL', _playbackUrlController, 'Paste stream URL or click Resolve from live/vod tabs'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _startPlayback,
              icon: const Icon(Icons.play_arrow),
              label: const Text('PLAY URL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                if (_diagVideoController != null) {
                  _diagVideoController!.dispose();
                  setState(() {
                    
                    _diagVideoController = null;
                  });
                }
              },
              child: const Text('STOP', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Player Panel
            Expanded(
              flex: 3,
              child: Container(
                height: 250,
                color: Colors.black,
                child: _diagVideoController == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_library, size: 48, color: AppColors.textTertiary),
                            SizedBox(height: 8),
                            Text('Player is Idle. Click PLAY above.', style: TextStyle(color: AppColors.textTertiary)),
                          ],
                        ),
                      )
                    : BetterPlayer(controller: _diagVideoController!),
              ),
            ),
            const SizedBox(width: 12),
            // Right Events Trace
            Expanded(
              flex: 2,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('LIVE VIDEO TELEMETRY', style: TextStyle(color: Colors.cyan, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => setState(() => _playbackEvents.clear()),
                          child: const Text('CLEAR', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.border),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _playbackEvents.length,
                        itemBuilder: (context, index) {
                          return Text(
                            _playbackEvents[index],
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _startPlayback() async {
    final streamUrl = _playbackUrlController.text.trim();
    if (streamUrl.isEmpty) {
      _toast('Playback URL cannot be empty!', isError: true);
      return;
    }
    
    _toast('Initializing media_kit Player...');
    
    if (_diagVideoController != null) {
      _diagVideoController?.dispose();
      _diagVideoController = null;
    }
    
    // Construct player headers
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'Referer': '${_apiClient.portalBase}/c/',
    };
    
    final uri = Uri.parse(_apiClient.portalUrl ?? '');
    final cookies = await _apiClient.cookieJar.loadForRequest(uri);
    if (cookies.isNotEmpty) {
      headers['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    }
    
    _appLogger.player('Starting playback for URL: $streamUrl headers: $headers');
    setState(() {
      _playbackEvents.clear();
      _playbackEvents.add('[${DateTime.now().toIso8601String().substring(11, 19)}] INIT SOURCE...');
    });
    
    try {
      
      
      
      _diagVideoController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: true,
          controlsConfiguration: BetterPlayerControlsConfiguration(showControls: false),
        ),
        betterPlayerDataSource: BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          streamUrl,
          headers: headers,
        ),
      );

      
      _diagVideoController?.addEventsListener((event) {
        if (!mounted) return;
        final timestamp = DateTime.now().toIso8601String().substring(11, 19);
        if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          final error = event.parameters?["error"]?.toString() ?? "Unknown error";
          setState(() {
            _playbackEvents.add('[$timestamp] ERROR: $error');
          });
          _appLogger.player('Playback error', error: error);
        } else if (event.betterPlayerEventType == BetterPlayerEventType.play) {
          setState(() {
            _playbackEvents.add('[$timestamp] PLAYING');
          });
        } else if (event.betterPlayerEventType == BetterPlayerEventType.pause) {
          setState(() {
            _playbackEvents.add('[$timestamp] PAUSED');
          });
        }
      });

      setState(() {}); // refresh to show video widget
      
      // handled by init
      
      final timestamp = DateTime.now().toIso8601String().substring(11, 19);
      setState(() {
        _playbackEvents.add('[$timestamp] INITIALIZED & PLAYING');
      });
      _toast('Playback active!');
    } catch (e) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 19);
      setState(() {
        _playbackEvents.add('[$timestamp] SETUP ERROR: $e');
        
        _diagVideoController = null;
      });
      _toast('Player setup failed: $e', isError: true);
      _appLogger.player('Setup failed', error: e);
    }
  }

  // ─── Custom UI Utility Builders ────────────────────────────────────────────

  Widget _screenTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border),
        ],
      ),
    );
  }

  Widget _sectionTitleWidget(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 12),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    // Deduplicate dropdown items
    final uniqueItems = items.toSet().toList();

    // Ensure the current value exists in the items list to prevent Flutter assertion crashes
    String activeValue = value;
    if (!uniqueItems.contains(activeValue)) {
      if (uniqueItems.contains('*')) {
        activeValue = '*';
      } else if (uniqueItems.isNotEmpty) {
        activeValue = uniqueItems.first;
      } else {
        uniqueItems.add(activeValue);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: DropdownButtonFormField<String>(
              value: activeValue,
              onChanged: onChanged,
              dropdownColor: AppColors.backgroundLight,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(),
              ),
              items: uniqueItems.map((i) {
                return DropdownMenuItem<String>(
                  value: i,
                  child: Text(i),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    
    _portalUrlController.dispose();
    _macController.dispose();
    _timezoneController.dispose();
    _requestEndpointController.dispose();
    _requestBodyController.dispose();
    _manualMovieCmdController.dispose();
    _diffSubeInputController.dispose();
    _playbackUrlController.dispose();
    super.dispose();
  }
}
