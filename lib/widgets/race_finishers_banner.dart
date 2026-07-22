import 'package:flutter/material.dart';

import '../styles.dart';

class RaceFinishersBanner extends StatelessWidget {
  final int finishedCount;
  final int targetSteps;

  const RaceFinishersBanner({
    super.key,
    required this.finishedCount,
    required this.targetSteps,
  });

  @override
  Widget build(BuildContext context) {
    final title = finishedCount == 1
        ? '1 FINISHER'
        : '$finishedCount FINISHERS';
    final subtitle = 'CLEARED THE ${_formatSteps(targetSteps)} STEP LINE';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.of(context).woodShadow.withValues(alpha: 0.35),
            offset: const Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.of(context).coinLight,
              AppColors.of(context).coinMid,
              AppColors.of(context).coinDark,
            ],
          ),
          border: Border.all(
            color: AppColors.of(context).woodShadow,
            width: 1.2,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.of(context).roofLight,
                AppColors.of(context).roofMid,
                AppColors.of(context).roofDark,
              ],
            ),
            border: Border.all(
              color: AppColors.of(context).pillGold.withValues(alpha: 0.9),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.of(context).coinLight,
                      AppColors.of(context).coinDark,
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.of(context).woodShadow,
                    width: 1.1,
                  ),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: PixelText.title(size: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 12.5,
                        color: AppColors.of(context).textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSteps(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
