import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/providers.dart';
import '../../profile/presentation/technical_inspector_screen.dart';

/// Login screen for MAG/Stalker portal authentication.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _portalController = TextEditingController();
  final _macController = TextEditingController();
  final _stbModelController = TextEditingController(text: 'MAG250');
  final _serialNumberController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'Europe/Kyiv');
  
  // Xtream Codes inputs
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isXtreamMode = false;

  bool _urlEncodeMac = true;
  bool _showAdvancedSettings = false;
  bool _rememberMe = false;
  bool _obscureUrl = false;
  bool _showHelpButton = false;
  bool _isSavingDebugFile = false;
  Timer? _loadingTimer;

  // Debug tap counter
  int _debugTapCount = 0;
  DateTime? _firstTapTime;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _portalController.dispose();
    _macController.dispose();
    _stbModelController.dispose();
    _serialNumberController.dispose();
    _timezoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final creds = await storage.getPortalCredentials();
    final xtreamCreds = await storage.getXtreamCredentials();
    final authType = await storage.getAuthType();
    final rememberMe = await storage.getRememberMe();

    if (creds['portalUrl'] != null) {
      _portalController.text = creds['portalUrl']!;
    }
    if (creds['macAddress'] != null) {
      _macController.text = creds['macAddress']!;
    }
    if (creds['stbModel'] != null) {
      _stbModelController.text = creds['stbModel']!;
    }
    if (creds['serialNumber'] != null) {
      _serialNumberController.text = creds['serialNumber']!;
    }
    if (creds['timezone'] != null) {
      _timezoneController.text = creds['timezone']!;
    }
    if (creds['urlEncodeMac'] != null) {
      _urlEncodeMac = creds['urlEncodeMac'] == 'true';
    }

    if (xtreamCreds['username'] != null) {
      _usernameController.text = xtreamCreds['username']!;
    }
    if (xtreamCreds['password'] != null) {
      _passwordController.text = xtreamCreds['password']!;
    }

    if (mounted) {
      setState(() {
        _rememberMe = rememberMe;
        _isXtreamMode = authType == 'xtream';
      });
    }
  }

  void _handleDebugTap() {
    final now = DateTime.now();
    if (_firstTapTime == null ||
        now.difference(_firstTapTime!) > AppConfig.debugTapWindow) {
      _debugTapCount = 1;
      _firstTapTime = now;
    } else {
      _debugTapCount++;
    }

    if (_debugTapCount >= AppConfig.debugTapCount) {
      _debugTapCount = 0;
      _firstTapTime = null;
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TechnicalInspectorScreen(),
        ),
      );
    }
  }

  String? _validatePortalUrl(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.invalidPortal;
    final url = value.trim();
    if (!url.contains('.') && !url.contains('localhost')) {
      return AppStrings.invalidPortal;
    }
    return null;
  }

  String? _validateMac(String? value) {
    if (value == null || value.trim().isEmpty) return AppStrings.invalidMac;
    final mac = value.trim().toUpperCase();
    final macRegex = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');
    if (!macRegex.hasMatch(mac)) return AppStrings.invalidMac;
    return null;
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    _loadingTimer?.cancel();
    setState(() => _showHelpButton = false);
    _loadingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showHelpButton = true);
    });

    if (_isXtreamMode) {
      await ref.read(authProvider.notifier).loginXtream(
            _portalController.text.trim(),
            _usernameController.text.trim(),
            _passwordController.text.trim(),
            rememberMe: _rememberMe,
          );
    } else {
      await ref.read(authProvider.notifier).login(
            _portalController.text.trim(),
            _macController.text.trim().toUpperCase(),
            rememberMe: _rememberMe,
            stbModel: _stbModelController.text.trim(),
            serialNumber: _serialNumberController.text.trim(),
            timezone: _timezoneController.text.trim(),
            urlEncodeMac: _urlEncodeMac,
          );
    }
    
    _loadingTimer?.cancel();
    if (mounted) setState(() => _showHelpButton = false);
  }

  /// Exports the full diagnostic log (all HTTP requests + log entries) to a
  /// .txt file and opens the native share / Save-to-Files sheet.
  Future<void> _saveDebugFile() async {
    if (_isSavingDebugFile) return;
    setState(() => _isSavingDebugFile = true);
    try {
      final logger = AppLogger();
      final content = logger.exportConversationLogs();

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File('${dir.path}/sflix_debug_$timestamp.txt');
      await file.writeAsString(content);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'SFLIX TV Debug Log – $timestamp',
        text:
            'Login failed debug log. Please share this file so the issue can be investigated.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create debug file: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDebugFile = false);
    }
  }

  Widget _buildCardInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool enabled = true,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1726),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.only(left: 10),
      alignment: Alignment.center,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        enabled: enabled,
        textCapitalization: textCapitalization,
        autocorrect: false,
        cursorColor: AppColors.primary,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          suffixIcon: suffixIcon ?? Icon(
            icon,
            size: 16,
            color: AppColors.primary,
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          errorStyle: const TextStyle(height: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              AppColors.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // LEFT SIDE (Branding)
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // App Logo
                            FadeInDown(
                              duration: const Duration(milliseconds: 800),
                              child: Center(
                                child: GestureDetector(
                                  onTap: _handleDebugTap,
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.primaryGradient,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(0.4),
                                          blurRadius: 15,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'S',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: -1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Headings
                            FadeInDown(
                              delay: const Duration(milliseconds: 100),
                              duration: const Duration(milliseconds: 600),
                              child: Text(
                                AppStrings.loginTitle,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FadeInDown(
                              delay: const Duration(milliseconds: 200),
                              duration: const Duration(milliseconds: 600),
                              child: const Text(
                                'Sign in to enjoy all your favorite movies, series, and live TV channels.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // RIGHT SIDE (Form Card & Actions)
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FadeInUp(
                            duration: const Duration(milliseconds: 800),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2A3B),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Stalker / Xtream toggle tabs
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(() => _isXtreamMode = false),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: !_isXtreamMode ? AppColors.primary : Colors.transparent,
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: Text(
                                                'Stalker'.toUpperCase(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: !_isXtreamMode ? Colors.white : Colors.white54,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => setState(() => _isXtreamMode = true),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _isXtreamMode ? AppColors.primary : Colors.transparent,
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: Text(
                                                'Xtream'.toUpperCase(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _isXtreamMode ? Colors.white : Colors.white54,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Server URL Input
                                  _buildCardInput(
                                    controller: _portalController,
                                    validator: _validatePortalUrl,
                                    enabled: !isLoading,
                                    keyboardType: TextInputType.url,
                                    label: _isXtreamMode ? 'Server URL' : AppStrings.portalUrl,
                                    icon: Icons.link_rounded,
                                    obscureText: _obscureUrl,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureUrl ? Icons.visibility : Icons.visibility_off,
                                        color: AppColors.primary,
                                        size: 16,
                                      ),
                                      onPressed: () => setState(() => _obscureUrl = !_obscureUrl),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  if (!_isXtreamMode) ...[
                                    // MAC Address Input
                                    _buildCardInput(
                                      controller: _macController,
                                      validator: _validateMac,
                                      enabled: !isLoading,
                                      label: AppStrings.macAddress,
                                      icon: Icons.router_rounded,
                                      textCapitalization: TextCapitalization.characters,
                                    ),
                                    const SizedBox(height: 8),

                                    // Advanced settings expander
                                    InkWell(
                                      onTap: isLoading ? null : () => setState(() => _showAdvancedSettings = !_showAdvancedSettings),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Row(
                                              children: [
                                                Icon(Icons.settings_suggest_rounded, color: AppColors.primary, size: 14),
                                                SizedBox(width: 6),
                                                Text(
                                                  'ADVANCED EMULATION SETTINGS',
                                                  style: TextStyle(
                                                    color: AppColors.primary,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Icon(
                                              _showAdvancedSettings ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                              color: AppColors.primary,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Expandable section
                                    AnimatedCrossFade(
                                      firstChild: const SizedBox.shrink(),
                                      secondChild: Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // STB Model Dropdown
                                            Container(
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1A1726),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.white10),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              child: DropdownButtonFormField<String>(
                                                value: _stbModelController.text,
                                                dropdownColor: const Color(0xFF1A1726),
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  prefixIcon: Icon(Icons.screenshot_monitor_rounded, color: AppColors.primary, size: 16),
                                                  labelText: 'STB MODEL',
                                                  labelStyle: TextStyle(color: Colors.white38, fontSize: 9),
                                                  filled: true,
                                                  fillColor: Colors.transparent,
                                                ),
                                                items: ['MAG250', 'MAG254', 'MAG322', 'MAG420'].map((String val) {
                                                  return DropdownMenuItem<String>(
                                                    value: val,
                                                    child: Text(val, style: const TextStyle(color: Colors.white)),
                                                  );
                                                }).toList(),
                                                onChanged: isLoading ? null : (val) {
                                                  if (val != null) {
                                                    setState(() => _stbModelController.text = val);
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // Serial Number
                                            _buildCardInput(
                                              controller: _serialNumberController,
                                              enabled: !isLoading,
                                              label: 'CUSTOM SERIAL NUMBER',
                                              icon: Icons.fingerprint_rounded,
                                              suffixIcon: TextButton(
                                                onPressed: isLoading ? null : () {
                                                  final macText = _macController.text.trim();
                                                  if (macText.isNotEmpty) {
                                                    final cleanMac = macText.replaceAll(':', '').toUpperCase();
                                                    setState(() {
                                                      _serialNumberController.text = cleanMac;
                                                    });
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Serial matched to MAC (no colons).'),
                                                        duration: Duration(seconds: 1),
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Enter a MAC address first.'),
                                                        duration: Duration(seconds: 1),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: const Text('MATCH MAC', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // Timezone
                                            _buildCardInput(
                                              controller: _timezoneController,
                                              enabled: !isLoading,
                                              label: 'TIMEZONE COOKIE VALUE',
                                              icon: Icons.public_rounded,
                                            ),
                                            const SizedBox(height: 8),

                                            // URL Encode MAC colons Switch
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('URL ENCODE MAC COLONS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                    SizedBox(height: 1),
                                                    Text('Fixes Cloudflare/proxy stripping', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                                                  ],
                                                ),
                                                SizedBox(
                                                  height: 24,
                                                  child: Switch(
                                                    value: _urlEncodeMac,
                                                    activeColor: AppColors.primary,
                                                    onChanged: isLoading ? null : (val) => setState(() => _urlEncodeMac = val),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      crossFadeState: _showAdvancedSettings ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                                      duration: const Duration(milliseconds: 300),
                                    ),
                                  ] else ...[
                                    // Username field
                                    _buildCardInput(
                                      controller: _usernameController,
                                      validator: (val) => val == null || val.trim().isEmpty ? 'Please enter username' : null,
                                      enabled: !isLoading,
                                      label: 'Username',
                                      icon: Icons.person_rounded,
                                    ),
                                    const SizedBox(height: 8),

                                    // Password field
                                    _buildCardInput(
                                      controller: _passwordController,
                                      validator: (val) => val == null || val.isEmpty ? 'Please enter password' : null,
                                      enabled: !isLoading,
                                      label: 'Password',
                                      icon: Icons.lock_rounded,
                                      obscureText: _obscurePassword,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),

                                  // Remember Me & Actions row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
                                        onTap: isLoading ? null : () => setState(() => _rememberMe = !_rememberMe),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: Checkbox(
                                                  value: _rememberMe,
                                                  onChanged: isLoading ? null : (v) => setState(() => _rememberMe = v ?? false),
                                                  activeColor: AppColors.primary,
                                                  checkColor: Colors.white,
                                                  side: const BorderSide(color: Colors.white70, width: 1.2),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Text(
                                                AppStrings.rememberMe,
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Error Notification panel inside the Card
                                  if (authState.status == AuthStatus.error && authState.errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.error.withOpacity(0.25),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline_rounded, color: AppColors.primary, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              authState.errorMessage!,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ── Save Debug File button ──
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isSavingDebugFile ? null : _saveDebugFile,
                                        icon: _isSavingDebugFile
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 1.5,
                                                  valueColor: AlwaysStoppedAnimation(Colors.amber),
                                                ),
                                              )
                                            : const Icon(Icons.save_alt_rounded, size: 13, color: Colors.amber),
                                        label: Text(
                                          _isSavingDebugFile ? 'PREPARING...' : 'SAVE DEBUG FILE',
                                          style: const TextStyle(
                                            color: Colors.amber,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.amber, width: 1),
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],

                                  // Action Buttons inside the card side-by-side
                                  Row(
                                    children: [
                                      // CONNECT BUTTON
                                      Expanded(
                                        flex: 6,
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            gradient: AppColors.primaryGradient,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary.withOpacity(0.3),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton(
                                            onPressed: isLoading ? null : _connect,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: isLoading
                                                ? const Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor: AlwaysStoppedAnimation(Colors.white),
                                                        ),
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'CONNECTING',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w800,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : const Text(
                                                    'CONNECT',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // DEMO PORTAL BUTTON
                                      Expanded(
                                        flex: 5,
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.02),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.1),
                                              width: 1.0,
                                            ),
                                          ),
                                          child: OutlinedButton(
                                            onPressed: isLoading
                                                ? null
                                                : () {
                                                    _portalController.text = 'http://tv.stream4k.cc';
                                                    _macController.text = '00:1E:99:2C:D2:08';
                                                    _connect();
                                                  },
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide.none,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: const Text(
                                              'USE DEMO',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Help and Diagnosis & Version bottom panel
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_showHelpButton)
                                FadeIn(
                                  child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const TechnicalInspectorScreen()),
                                      );
                                    },
                                    icon: const Icon(Icons.troubleshoot_rounded, size: 12, color: Colors.white54),
                                    label: const Text(
                                      'Troubleshoot',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.textTertiary,
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(),

                              // Version tag
                              FadeIn(
                                delay: const Duration(milliseconds: 300),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8.0, right: 4.0),
                                  child: Text(
                                    'v${AppConfig.appVersion}',
                                    style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

