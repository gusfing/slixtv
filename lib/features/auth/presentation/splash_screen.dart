import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/domain/providers.dart';
import '../../profile/presentation/problem_inspector_screen.dart';
import '../../mag_emulator/mag_emulator_provider.dart';

/// Animated splash screen with session restore.
class SplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onAuthenticated;
  final VoidCallback onUnauthenticated;

  const SplashScreen({
    super.key,
    required this.onAuthenticated,
    required this.onUnauthenticated,
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _showHelpButton = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _initApp();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    // Minimum splash duration for branding
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    // Show help button if it takes too long
    _loadingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showHelpButton = true);
    });

    // Pre-warm MAG device identity in parallel (non-blocking)
    ref.read(deviceIdentityProvider.future).ignore();

    // Try restoring session
    final restored = await ref.read(authProvider.notifier).tryRestoreSession();

    _loadingTimer?.cancel();

    if (!mounted) return;

    if (restored) {
      widget.onAuthenticated();
    } else {
      widget.onUnauthenticated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            FadeInDown(
              duration: const Duration(milliseconds: 800),
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.05),
                    child: child,
                  );
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // App name
            FadeInUp(
              delay: const Duration(milliseconds: 300),
              duration: const Duration(milliseconds: 800),
              child: Text(
                AppStrings.appName,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            FadeInUp(
              delay: const Duration(milliseconds: 500),
              duration: const Duration(milliseconds: 800),
              child: Text(
                AppStrings.appTagline,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1,
                    ),
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            // Loading indicator
            FadeIn(
              delay: const Duration(milliseconds: 800),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    AppColors.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            if (_showHelpButton) ...[
              const SizedBox(height: 32),
              FadeIn(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProblemInspectorScreen()),
                    );
                  },
                  icon: const Icon(Icons.troubleshoot_rounded, size: 18),
                  label: const Text('Still loading? Run Diagnosis'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
