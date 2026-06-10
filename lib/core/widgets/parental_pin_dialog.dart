import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../../features/auth/domain/providers.dart';

class ParentalPinDialog extends ConsumerStatefulWidget {
  final String? title;
  final String? instruction;
  final String? expectedPin;
  final ValueChanged<String>? onSubmit;

  const ParentalPinDialog({
    super.key,
    this.title,
    this.instruction,
    this.expectedPin,
    this.onSubmit,
  });

  /// Static helper to display the premium parental PIN dialog.
  /// Returns [true] if successfully authenticated, [false] otherwise.
  static Future<bool> show(
    BuildContext context, {
    String? title,
    String? instruction,
    String? expectedPin,
    ValueChanged<String>? onSubmit,
  }) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Parental PIN',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return ParentalPinDialog(
          title: title,
          instruction: instruction,
          expectedPin: expectedPin,
          onSubmit: onSubmit,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeInOutBack);
        return ScaleTransition(
          scale: curve,
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  @override
  ConsumerState<ParentalPinDialog> createState() => _ParentalPinDialogState();
}

class _ParentalPinDialogState extends ConsumerState<ParentalPinDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  final FocusNode _focusNode = FocusNode();
  String _pin = '';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyPress(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _pin += digit;
    });

    if (_pin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _hasError = false;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    if (widget.onSubmit != null) {
      widget.onSubmit!(_pin);
      return;
    }

    final lockState = ref.read(parentalLockProvider);
    final correctPin = widget.expectedPin ?? lockState.pin;

    if (_pin == correctPin) {
      // PIN is correct! Unlock the session and return true.
      HapticFeedback.mediumImpact();
      if (widget.expectedPin == null) {
        ref.read(parentalLockProvider.notifier).unlockSession();
      }
      Navigator.of(context).pop(true);
    } else {
      // PIN is incorrect. Trigger shake animation and error visual state.
      HapticFeedback.heavyImpact();
      setState(() {
        _hasError = true;
      });
      await _shakeController.forward(from: 0.0);
      setState(() {
        _pin = '';
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.backspace) {
        _onBackspace();
      } else if (key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop(false);
      } else {
        final char = event.character;
        if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
          _onKeyPress(char);
        }
      }
    }
  }

  Widget _buildDot(int index) {
    final isFilled = index < _pin.length;
    
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _hasError
            ? AppColors.error
            : isFilled
                ? AppColors.primary
                : Colors.transparent,
        border: Border.all(
          color: _hasError
              ? AppColors.error
              : isFilled
                  ? AppColors.primary
                  : Colors.white30,
          width: 2,
        ),
        boxShadow: isFilled && !_hasError
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : _hasError
                ? [
                    BoxShadow(
                      color: AppColors.error.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
      ),
    );
  }

  Widget _buildKeypadButton(String value, {VoidCallback? onPressed, Widget? customChild}) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed ?? () => _onKeyPress(value),
          borderRadius: BorderRadius.circular(26),
          hoverColor: AppColors.primary.withValues(alpha: 0.15),
          splashColor: AppColors.primary.withValues(alpha: 0.25),
          child: Center(
            child: customChild ??
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Center(
                child: AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final sineValue = sin(_shakeController.value * 3 * pi);
                    return Transform.translate(
                      offset: Offset(sineValue * 16, 0),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 520,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 40,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Column: Lock Icon, Title, Instruction, Dots, Error
                        Expanded(
                          flex: 11,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Shield Icon with Glow
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _hasError
                                      ? AppColors.error.withValues(alpha: 0.08)
                                      : AppColors.primary.withValues(alpha: 0.08),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _hasError
                                          ? AppColors.error.withValues(alpha: 0.15)
                                          : AppColors.primary.withValues(alpha: 0.15),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  _hasError ? Icons.gpp_bad_rounded : Icons.lock_outline_rounded,
                                  color: _hasError ? AppColors.error : AppColors.primary,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Title
                              Text(
                                widget.title ?? 'PARENTAL LOCK',
                                style: TextStyle(
                                  color: _hasError ? AppColors.error : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Subtitle
                              Text(
                                widget.instruction ?? 'Enter 4-digit PIN to access content',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              // PIN Dots
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(4, _buildDot),
                              ),
                              const SizedBox(height: 6),
                              // Error message
                              SizedBox(
                                height: 16,
                                child: AnimatedOpacity(
                                  opacity: _hasError ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Text(
                                    'Incorrect PIN code. Try again.',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Glassmorphic Divider
                        Container(
                          width: 1,
                          height: 180,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(alpha: 0.08),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                        
                        // Right Column: Wrap Keypad
                        SizedBox(
                          width: 180,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildKeypadButton('1'),
                              _buildKeypadButton('2'),
                              _buildKeypadButton('3'),
                              _buildKeypadButton('4'),
                              _buildKeypadButton('5'),
                              _buildKeypadButton('6'),
                              _buildKeypadButton('7'),
                              _buildKeypadButton('8'),
                              _buildKeypadButton('9'),
                              // Cancel Button
                              _buildKeypadButton(
                                'cancel',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).pop(false);
                                },
                                customChild: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                              ),
                              _buildKeypadButton('0'),
                              // Backspace Button
                              _buildKeypadButton(
                                'backspace',
                                onPressed: _onBackspace,
                                customChild: const Icon(
                                  Icons.backspace_outlined,
                                  color: Colors.white70,
                                  size: 18,
                                ),
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
        ),
      ),
    );
  }
}
