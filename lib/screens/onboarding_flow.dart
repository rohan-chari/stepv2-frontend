import 'package:flutter/material.dart';

import '../widgets/home_chrome.dart';
import '../widgets/onboarding_permission_gate.dart';
import '../widgets/pill_button.dart';
import '../styles.dart';
import '../utils/at_name.dart';

/// Standalone onboarding flow shown after sign-in until the user has granted
/// health access, answered the notification prompt, and seen the
/// "join your first race" step. Steps advance as the underlying state (driven
/// by [MainShell]) changes.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({
    super.key,
    required this.healthAuthorized,
    required this.notificationsState,
    required this.tutorialOnboardingSeen,
    required this.firstRaceOnboardingSeen,
    required this.onEnableHealth,
    required this.onEnableNotifications,
    required this.onStartTutorial,
    required this.onSkipTutorial,
    required this.onFetchOnboardingRaces,
    required this.onJoinOnboardingRace,
    required this.onSkipFirstRace,
    this.firstRaceShareTokenPending = false,
    this.error,
    this.isLoading = false,
  });

  final bool healthAuthorized;

  /// null = not yet prompted, true = granted, false = denied.
  final bool? notificationsState;

  /// Whether this account has completed or skipped the tutorial onboarding step.
  final bool tutorialOnboardingSeen;

  /// Whether the backend says this account already saw the first-race step.
  final bool firstRaceOnboardingSeen;

  final VoidCallback onEnableHealth;
  final VoidCallback onEnableNotifications;

  /// Launches the tutorial (which grants the one-time reward on completion).
  final VoidCallback onStartTutorial;

  /// Skips the tutorial step (marks seen, no reward).
  final VoidCallback onSkipTutorial;

  /// Fetches public races for the onboarding step (already restricted to the
  /// qualifying set will be applied by the step itself). Returns null on error.
  final Future<List<Map<String, dynamic>>?> Function() onFetchOnboardingRaces;

  /// Joins a race with the onboarding flag set. Returns true on success.
  final Future<bool> Function(String raceId) onJoinOnboardingRace;

  /// Skips the first-race step (marks seen on the backend + locally).
  final VoidCallback onSkipFirstRace;

  /// True when a race share link is waiting to be joined. The first-race step
  /// then auto-skips the generic public picker — the user already has a
  /// specific race to join, which MainShell joins + opens once onboarding ends.
  final bool firstRaceShareTokenPending;

  final String? error;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // Step 1: health permission (required to proceed).
    if (!healthAuthorized) {
      return OnboardingPermissionGate(
        label: 'HEALTH DATA',
        headline: 'Connect steps to start racing',
        body:
            'Bara uses your step count to run fair races. We do not read routes, workouts, or location.',
        icon: Icons.favorite_rounded,
        onContinue: onEnableHealth,
        error: error,
        isLoading: isLoading,
        retryLabel: 'TRY AGAIN',
      );
    }

    // Step 2: notification permission (granted or denied both advance).
    if (notificationsState == null) {
      return OnboardingPermissionGate(
        label: 'NOTIFICATIONS',
        headline: 'Stay in the race',
        body:
            'Get race invites, friend requests, and important match updates as they happen.',
        icon: Icons.notifications_rounded,
        onContinue: onEnableNotifications,
      );
    }

    // Step 3: tutorial intro (after the permission gates, before first race).
    if (!tutorialOnboardingSeen) {
      return OnboardingTutorialStep(
        onStart: onStartTutorial,
        onSkip: onSkipTutorial,
      );
    }

    // Step 4: join your first race.
    return OnboardingFirstRaceStep(
      onFetchOnboardingRaces: onFetchOnboardingRaces,
      onJoinOnboardingRace: onJoinOnboardingRace,
      onSkip: onSkipFirstRace,
      skipForPendingShare: firstRaceShareTokenPending,
    );
  }
}

/// "Earn your first 100 coins" onboarding step. Mirrors the permission gates'
/// green arcade styling and the first-race step's primary/skip layout. Starting
/// launches the tutorial (which grants the one-time reward on completion);
/// skipping marks the step seen without a reward (the user can still earn it
/// later by finishing a replay).
class OnboardingTutorialStep extends StatelessWidget {
  const OnboardingTutorialStep({
    super.key,
    required this.onStart,
    required this.onSkip,
  });

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.roofLight,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ArcadeCheckerPainter(drawBottomStripe: false),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 24 : 58,
                          24,
                          128,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: compact ? 132 : 160,
                              height: compact ? 132 : 160,
                              decoration: BoxDecoration(
                                color: AppColors.parchment.withValues(
                                  alpha: 0.12,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.parchmentLight.withValues(
                                    alpha: 0.30,
                                  ),
                                  width: 3,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '100',
                                style: HomeText.title(
                                  size: compact ? 44 : 54,
                                  color: AppColors.parchment,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'FIRST 100 COINS',
                              style: HomeText.label(
                                size: 13,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.86,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Earn your first 100 coins',
                              style: HomeText.title(
                                size: 32,
                                color: AppColors.parchment,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Take the quick tour to learn how Bara works — '
                              'finish it and we’ll drop 100 coins in your '
                              'balance to get you started.',
                              style: HomeText.body(
                                size: 15,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.92,
                                ),
                                height: 1.38,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 52),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: PillButton(
                                label: 'START TUTORIAL',
                                variant: PillButtonVariant.secondary,
                                fullWidth: true,
                                padding: EdgeInsets.zero,
                                icon: Icons.play_arrow_rounded,
                                onPressed: onStart,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: onSkip,
                              child: Text(
                                'Skip for now',
                                style: HomeText.body(
                                  size: 15,
                                  color: AppColors.parchmentLight.withValues(
                                    alpha: 0.92,
                                  ),
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Join your first race" onboarding step. Fetches public races, filters to
/// free + powerups-enabled races, and lets the user join one (granting mystery
/// boxes) or skip. Empty/error → auto-skips so onboarding never dead-ends.
class OnboardingFirstRaceStep extends StatefulWidget {
  const OnboardingFirstRaceStep({
    super.key,
    required this.onFetchOnboardingRaces,
    required this.onJoinOnboardingRace,
    required this.onSkip,
    this.skipForPendingShare = false,
  });

  final Future<List<Map<String, dynamic>>?> Function() onFetchOnboardingRaces;
  final Future<bool> Function(String raceId) onJoinOnboardingRace;
  final VoidCallback onSkip;

  /// When true, skip the generic public picker entirely (a share link is
  /// pending — MainShell will join that specific race after onboarding).
  final bool skipForPendingShare;

  @override
  State<OnboardingFirstRaceStep> createState() =>
      _OnboardingFirstRaceStepState();
}

class _OnboardingFirstRaceStepState extends State<OnboardingFirstRaceStep> {
  bool _loading = true;
  List<Map<String, dynamic>> _races = const [];
  String? _joiningRaceId;
  bool _skipping = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A pending share link means the user already has a specific race to join
    // (MainShell joins + opens it once onboarding ends). Skip the generic
    // picker straight through so onboarding doesn't dead-end on it.
    if (widget.skipForPendingShare) {
      widget.onSkip();
      return;
    }

    final races = await widget.onFetchOnboardingRaces();
    if (!mounted) return;

    // Fetch error → auto-skip so the user never dead-ends here.
    if (races == null) {
      widget.onSkip();
      return;
    }

    final qualifying = races.where((race) {
      final buyIn = race['buyInAmount'] as int? ?? 0;
      final powerupsEnabled = race['powerupsEnabled'] as bool? ?? false;
      return buyIn == 0 && powerupsEnabled;
    }).toList(growable: false);

    // No qualifying races → auto-skip.
    if (qualifying.isEmpty) {
      widget.onSkip();
      return;
    }

    setState(() {
      _races = qualifying;
      _loading = false;
    });
  }

  Future<void> _join(Map<String, dynamic> race) async {
    if (_joiningRaceId != null || _skipping) return;
    final raceId = race['id'] as String?;
    if (raceId == null) return;
    setState(() => _joiningRaceId = raceId);
    final success = await widget.onJoinOnboardingRace(raceId);
    if (!mounted) return;
    if (!success) {
      setState(() => _joiningRaceId = null);
    }
    // On success MainShell exits onboarding + navigates to the race; this
    // widget will be torn down, so no further state changes needed.
  }

  void _skip() {
    if (_skipping || _joiningRaceId != null) return;
    setState(() => _skipping = true);
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.roofLight,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ArcadeCheckerPainter(drawBottomStripe: false),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 24 : 48,
                          24,
                          128,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'FIRST RACE',
                              style: HomeText.label(
                                size: 13,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.86,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Join your first race',
                              style: HomeText.title(
                                size: 32,
                                color: AppColors.parchment,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Pick a free race to get going — join now and we’ll '
                              'drop 3 mystery boxes in your bag.',
                              style: HomeText.body(
                                size: 15,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.92,
                                ),
                                height: 1.38,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(top: 32),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.parchment,
                                    strokeWidth: 3,
                                  ),
                                ),
                              )
                            else
                              ..._races.map(
                                (race) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _OnboardingRaceCard(
                                    race: race,
                                    isJoining:
                                        _joiningRaceId == race['id'] as String?,
                                    disabled: _joiningRaceId != null ||
                                        _skipping,
                                    onJoin: () => _join(race),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
                        child: TextButton(
                          onPressed: (_joiningRaceId != null || _skipping)
                              ? null
                              : _skip,
                          child: Text(
                            'Maybe later',
                            style: HomeText.body(
                              size: 15,
                              color: AppColors.parchmentLight.withValues(
                                alpha: 0.92,
                              ),
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single selectable public-race card styled for the onboarding (green)
/// background. The shared `PublicRacesScreen` card uses a parchment `RetroCard`
/// that clashes with the onboarding aesthetic, so this is a themed variant.
class _OnboardingRaceCard extends StatelessWidget {
  const _OnboardingRaceCard({
    required this.race,
    required this.isJoining,
    required this.disabled,
    required this.onJoin,
  });

  final Map<String, dynamic> race;
  final bool isJoining;
  final bool disabled;
  final VoidCallback onJoin;

  String _timeLeftLabel() {
    final endsAt = DateTime.tryParse(race['endsAt'] as String? ?? '');
    final maxDurationDays = race['maxDurationDays'] as int? ?? 7;
    if (endsAt == null) return '${maxDurationDays}d';
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'soon';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    return '${remaining.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final name = race['name'] as String? ?? 'Race';
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? 'Someone';
    final participantCount = race['participantCount'] as int? ?? 0;
    // null => no participant limit (unlimited).
    final maxParticipants = race['maxParticipants'] as int?;
    final runnersLabel = maxParticipants == null
        ? '$participantCount'
        : '$participantCount/$maxParticipants';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.parchment.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.parchmentLight.withValues(alpha: 0.30),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.toUpperCase(),
            style: HomeText.title(size: 16, color: AppColors.parchment),
          ),
          const SizedBox(height: 4),
          Text(
            'BY ${atName(creatorName)}'.toUpperCase(),
            style: HomeText.label(
              size: 11,
              color: AppColors.parchmentLight.withValues(alpha: 0.80),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('ENDS IN', _timeLeftLabel()),
              const SizedBox(width: 16),
              _stat('RUNNERS', runnersLabel),
              const SizedBox(width: 16),
              _stat('BUY-IN', 'FREE'),
              const SizedBox(width: 16),
              _stat('POWERUPS', 'ON'),
            ],
          ),
          const SizedBox(height: 14),
          PillButton(
            label: isJoining ? 'JOINING...' : 'JOIN',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            onPressed: (disabled || isJoining) ? null : onJoin,
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: HomeText.label(
            size: 10,
            color: AppColors.parchmentLight.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: HomeText.title(size: 14, color: AppColors.parchment),
        ),
      ],
    );
  }
}
