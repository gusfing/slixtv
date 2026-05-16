import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/logging/app_logger.dart';

class DebugDashboardScreen extends StatefulWidget {
  // Keeping constructor parameters so it doesn't break login_screen.dart,
  // but we won't strictly rely on them for the new playback diagnostics.
  final dynamic deviceIdentity;
  final dynamic sessionManager;
  final dynamic logger;
  final dynamic playerHeadersService;
  final dynamic errorHandler;

  const DebugDashboardScreen({
    Key? key,
    this.deviceIdentity,
    this.sessionManager,
    this.logger,
    this.playerHeadersService,
    this.errorHandler,
  }) : super(key: key);

  @override
  State<DebugDashboardScreen> createState() => _DebugDashboardScreenState();
}

class _DebugDashboardScreenState extends State<DebugDashboardScreen> {
  Timer? _refreshTimer;
  final AppLogger _appLogger = AppLogger();

  @override
  void initState() {
    super.initState();
    // Auto-refresh every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _copyDebugReport() {
    final state = _appLogger.debugState;
    final sb = StringBuffer();
    sb.writeln('=== MAG PLAYBACK DIAGNOSTICS ===');
    sb.writeln('Token: ${state.token}');
    sb.writeln('Cookies: ${state.cookies}');
    sb.writeln('Selected Item: ${state.selectedContent}');
    sb.writeln('create_link Request: ${state.requestPayload}');
    sb.writeln('Raw Response: ${state.rawResponse}');
    sb.writeln('Final Stream URL: ${state.resolvedUrl}');
    sb.writeln('Player Headers: ${state.playerHeaders}');
    sb.writeln('Last Error: ${state.lastError}');

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostics copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final state = _appLogger.debugState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback Diagnostics'),
        actions: [
          IconButton(icon: const Icon(Icons.copy), onPressed: _copyDebugReport),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {})),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Token', state.token.isEmpty ? 'Not set' : state.token),
          _buildSection('Cookies', state.cookies.isEmpty ? 'Not set' : state.cookies),
          _buildSection('Selected Item', state.selectedContent.isEmpty ? 'None' : state.selectedContent),
          _buildSection('create_link Request', state.requestPayload.isEmpty ? 'None' : state.requestPayload),
          _buildSection('Raw Response', state.rawResponse.isEmpty ? 'None' : state.rawResponse),
          _buildSection('Redirects', state.redirects.isEmpty ? 'None' : state.redirects),
          _buildSection('Final Stream URL', state.resolvedUrl.isEmpty ? 'None' : state.resolvedUrl),
          _buildSection('Player Headers', state.playerHeaders.isEmpty ? 'None' : state.playerHeaders),
          if (state.lastError.isNotEmpty)
            _buildSection('Last Error', state.lastError, color: Colors.red.shade100),
          
          const SizedBox(height: 24),
          const Text('Recent Logs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          _buildLogsList(),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    final logs = _appLogger.logBuffer.reversed.take(50).toList();
    if (logs.isEmpty) return const Text('No logs available');
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isError = log.level.name.toLowerCase() == 'error';
        
        return Container(
          color: isError ? Colors.red.shade50 : (index % 2 == 0 ? Colors.white : Colors.grey.shade50),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: SelectableText(
            log.toString(),
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: isError ? Colors.red.shade900 : Colors.black87),
          ),
        );
      },
    );
  }
}
