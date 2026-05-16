import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/config/app_config.dart';
import '../domain/providers.dart';
import '../../profile/presentation/problem_inspector_screen.dart';
import '../../mag_emulator/mag_emulator_provider.dart';
import '../../mag_emulator/presentation/screens/debug_dashboard_screen.dart';

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
  bool _rememberMe = false;
  bool _obscureUrl = false;
  bool _showHelpButton = false;
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
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final creds = await storage.getPortalCredentials();
    final rememberMe = await storage.getRememberMe();

    if (creds['portalUrl'] != null) {
      _portalController.text = creds['portalUrl']!;
    }
    if (creds['macAddress'] != null) {
      _macController.text = creds['macAddress']!;
    }
    if (mounted) {
      setState(() => _rememberMe = rememberMe);
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
      
      // Open the Playback Diagnostics Dashboard directly
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DebugDashboardScreen(),
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

    await ref.read(authProvider.notifier).login(
          _portalController.text.trim(),
          _macController.text.trim().toUpperCase(),
          rememberMe: _rememberMe,
        );
    
    _loadingTimer?.cancel();
    if (mounted) setState(() => _showHelpButton = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo
                FadeInDown(
                  duration: const Duration(milliseconds: 600),
                  child: Center(
                    child: GestureDetector(
                      onTap: _handleDebugTap,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'S',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                FadeInDown(
                  delay: const Duration(milliseconds: 200),
                  child: Text(
                    AppStrings.loginTitle,
                    style: Theme.of(context).textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                FadeInDown(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    AppStrings.loginSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),

                // Portal URL field
                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  child: TextFormField(
                    controller: _portalController,
                    validator: _validatePortalUrl,
                    enabled: !isLoading,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: AppStrings.portalUrl,
                      hintText: AppStrings.portalUrlHint,
                      prefixIcon: const Icon(Icons.link_rounded, color: AppColors.textTertiary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureUrl ? Icons.visibility : Icons.visibility_off,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureUrl = !_obscureUrl),
                      ),
                    ),
                    obscureText: _obscureUrl,
                  ),
                ),
                const SizedBox(height: 16),

                // MAC Address field
                FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: TextFormField(
                    controller: _macController,
                    validator: _validateMac,
                    enabled: !isLoading,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: AppStrings.macAddress,
                      hintText: AppStrings.macAddressHint,
                      prefixIcon: Icon(Icons.router_rounded, color: AppColors.textTertiary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Remember Me
                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: isLoading
                            ? null
                            : (v) => setState(() => _rememberMe = v ?? false),
                        activeColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.textTertiary),
                      ),
                      Text(
                        AppStrings.rememberMe,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Error message
                if (authState.status == AuthStatus.error &&
                    authState.errorMessage != null)
                  FadeIn(
                    child: Container(
                      padding: const EdgeInsets.all(AppDimensions.md),
                      margin: const EdgeInsets.only(bottom: AppDimensions.md),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              authState.errorMessage!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Connect button
                FadeInUp(
                  delay: const Duration(milliseconds: 700),
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _connect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.8)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(AppStrings.connecting),
                              ],
                            )
                          : const Text(
                              AppStrings.connect,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
                if (_showHelpButton) ...[
                  const SizedBox(height: 16),
                  FadeIn(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ProblemInspectorScreen()),
                        );
                      },
                      icon: const Icon(Icons.troubleshoot_rounded, size: 18),
                      label: const Text('Having trouble? View Diagnosis'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // Version info
                FadeIn(
                  delay: const Duration(milliseconds: 900),
                  child: Text(
                    'v${AppConfig.appVersion}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textHint,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

