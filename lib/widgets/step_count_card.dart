import 'package:flutter/material.dart';
import '../models/step_data.dart';
import '../styles.dart';

class StepCountCard extends StatelessWidget {
  final StepData? stepData;
  final bool isLoading;
  final String? error;
  final String? hint;

  const StepCountCard({
    super.key,
    this.stepData,
    this.isLoading = false,
    this.error,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 300),
      child: Card(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.directions_walk,
                size: 64,
                color: AppColors.accent,
              ),
              const SizedBox(height: 16),
              Text(
                "Today's Steps",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              if (isLoading)
                const CircularProgressIndicator(color: AppColors.accent)
              else if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  '${stepData?.steps ?? 0}',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.accent,
                      ),
                ),
              if (hint != null) ...[
                const SizedBox(height: 16),
                Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.4),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
