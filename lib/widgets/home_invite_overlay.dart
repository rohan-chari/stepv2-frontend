import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/home_invite_preflight.dart';
import '../styles.dart';
import 'pill_button.dart';
import 'spinning_coin.dart';

/// Focused shell-route card. It owns only visual/interaction state; MainShell
/// owns data freshness, sequencing, and the authoritative response calls.
class HomeInviteOverlay extends StatefulWidget {
  const HomeInviteOverlay({
    super.key,
    required this.invite,
    required this.onRespond,
  });

  final HomeInvite invite;
  final Future<void> Function(bool accept) onRespond;

  @override
  State<HomeInviteOverlay> createState() => _HomeInviteOverlayState();
}

class _HomeInviteOverlayState extends State<HomeInviteOverlay> {
  bool _acting = false;
  bool? _accepting;
  String? _error;

  Future<void> _respond(bool accept) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _accepting = accept;
      _error = null;
    });
    try {
      await widget.onRespond(accept);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _acting = false;
          _accepting = null;
          _error = error.toString();
        });
      }
    }
  }

  void _dismiss() {
    if (!_acting) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final colors = AppColors.of(context);
    return PopScope(
      canPop: !_acting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.46)),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      key: const Key('home-invite-overlay'),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      decoration: BoxDecoration(
                        color: colors.parchment,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.parchmentBorder,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.woodDarker.withValues(alpha: 0.58),
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              label: 'Dismiss invitation',
                              button: true,
                              child: IconButton(
                                key: const Key('home-invite-dismiss'),
                                onPressed: _acting ? null : _dismiss,
                                icon: const Icon(Icons.close_rounded),
                                color: colors.textMid,
                              ),
                            ),
                          ),
                          Text(
                            invite.isTournament
                                ? 'BRACKET INVITE'
                                : 'RACE INVITE',
                            style: PixelText.title(
                              size: 11,
                              color: colors.coinDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            invite.name,
                            textAlign: TextAlign.center,
                            style: PixelText.title(
                              size: 20,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Invited by @${invite.creatorName ?? 'A runner'}',
                            textAlign: TextAlign.center,
                            style: PixelText.body(
                              size: 13,
                              color: colors.textMid,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (invite.durationDays case final days?)
                                _fact(
                                  context,
                                  '$days ${days == 1 ? 'DAY' : 'DAYS'}',
                                ),
                              if (!invite.isTournament &&
                                  invite.status == 'ACTIVE')
                                _fact(context, 'UNDERWAY'),
                              if (invite.isTeamRace)
                                _fact(context, 'TEAM AUTO-ASSIGN'),
                              if (invite.buyInAmount > 0)
                                _fact(context, '${invite.buyInAmount} GOLD'),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: PixelText.body(
                                size: 12,
                                color: colors.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                            PillButton(
                              key: const Key('home-invite-retry'),
                              label: 'RETRY',
                              variant: PillButtonVariant.secondary,
                              fullWidth: true,
                              onPressed: () => _respond(_accepting ?? true),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: PillButton(
                                  key: const Key('home-invite-accept'),
                                  label: _acting && _accepting == true
                                      ? 'JOINING…'
                                      : invite.buyInAmount > 0
                                      ? 'ACCEPT · ${invite.buyInAmount}'
                                      : 'ACCEPT',
                                  leading: invite.buyInAmount > 0
                                      ? const SpinningCoin(size: 14)
                                      : null,
                                  variant: PillButtonVariant.decision,
                                  fullWidth: true,
                                  loading: _acting && _accepting == true,
                                  onPressed: _acting
                                      ? null
                                      : () => _respond(true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: PillButton(
                                  key: const Key('home-invite-decline'),
                                  label: _acting && _accepting == false
                                      ? 'DECLINING…'
                                      : 'DECLINE',
                                  variant: PillButtonVariant.destructive,
                                  fullWidth: true,
                                  loading: _acting && _accepting == false,
                                  onPressed: _acting
                                      ? null
                                      : () => _respond(false),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.of(context).parchmentDark,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: PixelText.title(size: 9, color: AppColors.of(context).textMid),
    ),
  );
}
