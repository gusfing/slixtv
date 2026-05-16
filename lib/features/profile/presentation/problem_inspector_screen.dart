import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/logging/app_logger.dart';

class ProblemInspectorScreen extends StatelessWidget {
  const ProblemInspectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger();
    final diagnosis = logger.diagnosis;
    final lastProb = logger.lastCriticalProblem;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Problem Inspector'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logger.exportLogs()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Diagnosis Card
            Container(
              width: double.infinity,
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
                        lastProb != null ? 'System Diagnosis' : 'System Healthy',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: lastProb != null ? AppColors.error : AppColors.success,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    diagnosis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (lastProb != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Time: ${lastProb.timestamp.hour}:${lastProb.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Technical Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            if (lastProb != null) ...[
              _detailRow('Component', lastProb.tag),
              _detailRow('Message', lastProb.message),
              if (lastProb.error != null) _detailRow('Internal Error', lastProb.error!),
            ] else 
              const Text('No technical errors recorded yet.', style: TextStyle(color: AppColors.textSecondary)),

            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => logger.clearBuffer(),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Clear Log History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
