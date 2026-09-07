import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/rewarded_coins_controller.dart';
import '../styles.dart';
import 'error_toast.dart';
import 'info_toast.dart';
import 'pill_button.dart';

/// Keeps standalone Home injection usable; production passes the shell's
/// controller. The entire Home (including its + route) receives the same owner.
class HomeRewardedCoinsHost extends StatefulWidget {
  const HomeRewardedCoinsHost({
    super.key,
    required this.auth,
    required this.api,
    this.ads,
    this.controller,
    required this.builder,
  });
  final AuthService auth;
  final BackendApiService api;
  final ExtraSpinAdController? ads;
  final RewardedCoinsController? controller;
  final Widget Function(BuildContext, RewardedCoinsController?) builder;
  @override
  State<HomeRewardedCoinsHost> createState() => _HomeRewardedCoinsHostState();
}

class _HomeRewardedCoinsHostState extends State<HomeRewardedCoinsHost> {
  RewardedCoinsController? _controller;
  bool _owns = false;
  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _owns = widget.controller == null && widget.ads != null;
    _controller =
        widget.controller ??
        (widget.ads != null
            ? RewardedCoinsController(
                auth: widget.auth,
                api: widget.api,
                ads: widget.ads!,
              )
            : null);
    // Eligibility must not delay Home's first frame or start ads in build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      if (mounted && controller != null && controller.supported) {
        unawaited(controller.refresh());
      }
    });
  }

  @override
  void didUpdateWidget(HomeRewardedCoinsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.ads != widget.ads ||
        oldWidget.auth != widget.auth) {
      if (_owns) _controller?.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    if (_owns) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

class HomeRewardedCoins extends StatelessWidget {
  const HomeRewardedCoins({super.key, required this.controller});
  final RewardedCoinsController controller;

  Future<void> _claim(BuildContext context) async {
    final token = controller.auth.authToken;
    try {
      final amount = await controller.claim();
      if (context.mounted &&
          controller.auth.authToken == token &&
          amount != null) {
        showInfoToast(context, '+$amount coins earned!');
      }
    } catch (_) {
      if (context.mounted && controller.auth.authToken == token) {
        showErrorToast(context, 'Reward failed. Try again later.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.supported || !controller.live) {
        return const SizedBox.shrink();
      }
      final colors = AppColors.of(context);
      final waiting = controller.busy || controller.loading;
      final label = waiting
          ? 'LOADING AD...'
          : controller.pending
          ? 'CLAIM COINS'
          : controller.ready
          ? 'WATCH AD'
          : 'TRY AGAIN';
      final detail = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bonus coins',
            style: PixelText.title(size: 16, color: colors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            '${controller.homeRewardCopy} · ${controller.remaining} ads left today',
            style: PixelText.body(size: 13, color: colors.textMid),
          ),
        ],
      );
      Widget button(bool fullWidth) => PillButton(
        label: label,
        fullWidth: fullWidth,
        variant: PillButtonVariant.rewardedAd,
        onPressed: waiting
            ? null
            : controller.pending || controller.ready
            ? () => _claim(context)
            : controller.prepare,
      );
      return Padding(
        key: const Key('home-rewarded-coins'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.parchment,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.roofDark.withValues(alpha: .55),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), offset: Offset(0, 3)),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(13) > 17) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [detail, const SizedBox(height: 10), button(true)],
                );
              }
              return Row(
                children: [
                  Expanded(child: detail),
                  const SizedBox(width: 12),
                  button(false),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
