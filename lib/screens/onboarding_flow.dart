import 'package:flutter/material.dart';

import '../widgets/app_avatar.dart';
import '../widgets/onboarding_permission_gate.dart';
import '../widgets/onboarding_scene.dart';
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
    required this.onEnterDaily,
    required this.onSkipFirstRace,
    this.onboardingV2Enabled = false,
    this.displayName,
    this.onFetchActiveDaily,
    this.onEnterVerifiedDaily,
    this.onFindRace,
    this.firstRaceShareTokenPending = false,
    this.welcomeReferralCode,
    this.onWelcomeDismissed,
    this.onFetchReferralPreview,
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

  /// Confirms the auto-enrollment and drops the user into the live Daily race.
  /// The host (MainShell) closes the first-race onboarding gate, then routes to
  /// the active Daily race — or falls back to Home when none is available — so
  /// this step never has to know about races or navigation.
  final Future<void> Function() onEnterDaily;

  /// Skips the first-race step (marks seen on the backend + locally). Used for
  /// the pending-share precedence path (a specific race is already queued).
  final VoidCallback onSkipFirstRace;

  /// Explicit remote opt-in. False/missing retains every v1 gate above.
  final bool onboardingV2Enabled;
  final String? displayName;
  final Future<Map<String, dynamic>?> Function()? onFetchActiveDaily;
  final Future<void> Function(String raceId)? onEnterVerifiedDaily;
  final Future<void> Function()? onFindRace;

  /// True when a race share link is waiting to be joined. The first-race step
  /// then auto-skips the generic public picker — the user already has a
  /// specific race to join, which MainShell joins + opens once onboarding ends.
  final bool firstRaceShareTokenPending;

  /// One-shot code a just-referred user signed up with. When present (and the
  /// callbacks below are wired), a welcome step greets them by inviter before
  /// the permission gates. Null for organic installs — they see no extra step.
  final String? welcomeReferralCode;

  /// Marks the welcome shown (clears [welcomeReferralCode]) so the flow advances.
  final VoidCallback? onWelcomeDismissed;

  /// Fetches the public inviter preview ({inviterName, inviterAvatar,
  /// rewardCoins}) for [welcomeReferralCode]. Errors → a generic welcome.
  final Future<Map<String, dynamic>> Function(String code)?
  onFetchReferralPreview;

  final String? error;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // Step 0: tailored welcome for a referred user (only when a code resolved
    // and the host wired the callbacks). Organic installs skip straight to the
    // permission gates — no added friction.
    if (welcomeReferralCode != null && onWelcomeDismissed != null) {
      return OnboardingReferralWelcomeStep(
        code: welcomeReferralCode!,
        onFetchPreview: onFetchReferralPreview,
        onContinue: onWelcomeDismissed!,
      );
    }

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
    //
    // Runs for V2 too, and deliberately sits AFTER health and BEFORE the daily
    // intro. V2 used to return the daily intro above this check, which left
    // the gate unreachable — a brand-new user was never asked, even on a fresh
    // install, and ended up with notifications permanently off unless they
    // happened to find the Profile or race-detail opt-in. Only an undetermined
    // state prompts, so a previous grant or denial is still never re-nagged.
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

    // V2 intentionally removes the tutorial blocking gate. A pending share
    // takes precedence inside this step after Health succeeds.
    if (onboardingV2Enabled) {
      return OnboardingDailyIntroStep(
        displayName: displayName,
        skipForPendingShare: firstRaceShareTokenPending,
        onSkipForShare: onSkipFirstRace,
        onFetchDaily: onFetchActiveDaily,
        onEnterDaily: onEnterVerifiedDaily,
        onFindRace: onFindRace,
      );
    }

    // Step 3: tutorial intro (after the permission gates, before first race).
    if (!tutorialOnboardingSeen) {
      return OnboardingTutorialStep(
        onStart: onStartTutorial,
        onSkip: onSkipTutorial,
      );
    }

    // Step 4: you're auto-enrolled — confirm + drop into the live Daily race.
    // Enrollment already happened server-side on account creation, so this step
    // only celebrates it and routes; it never joins a race itself.
    return OnboardingAutoEnrolledStep(
      onEnterDaily: onEnterDaily,
      onSkip: onSkipFirstRace,
      skipForPendingShare: firstRaceShareTokenPending,
    );
  }
}

/// V2's final gate is backed by a real, accepted Daily race. Until the payload
/// proves ACTIVE + ACCEPTED, this screen never claims enrollment or rewards.
class OnboardingDailyIntroStep extends StatefulWidget {
  const OnboardingDailyIntroStep({
    super.key,
    required this.displayName,
    required this.skipForPendingShare,
    required this.onSkipForShare,
    this.onFetchDaily,
    this.onEnterDaily,
    this.onFindRace,
  });

  final String? displayName;
  final bool skipForPendingShare;
  final VoidCallback onSkipForShare;
  final Future<Map<String, dynamic>?> Function()? onFetchDaily;
  final Future<void> Function(String raceId)? onEnterDaily;
  final Future<void> Function()? onFindRace;

  @override
  State<OnboardingDailyIntroStep> createState() =>
      _OnboardingDailyIntroStepState();
}

class _OnboardingDailyIntroStepState extends State<OnboardingDailyIntroStep> {
  Map<String, dynamic>? _daily;
  bool _loading = true;
  bool _entering = false;

  @override
  void initState() {
    super.initState();
    if (widget.skipForPendingShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSkipForShare();
      });
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final value = await widget.onFetchDaily?.call();
      if (!mounted) return;
      setState(() {
        _daily = value;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _timeRemaining {
    final raw = _daily?['endsAt'];
    final end = raw is String ? DateTime.tryParse(raw) : null;
    if (end == null) return 'Ends today';
    final remaining = end.difference(DateTime.now());
    if (remaining.isNegative) return 'Ending soon';
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
    }
    return '${remaining.inMinutes.clamp(1, 59)}m left';
  }

  Future<void> _enter() async {
    final raceId = (_daily?['raceId'] ?? _daily?['id']) as String?;
    if (raceId == null || raceId.isEmpty || _entering) return;
    setState(() => _entering = true);
    await widget.onEnterDaily?.call(raceId);
    if (mounted) setState(() => _entering = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.skipForPendingShare || _loading) {
      return const OnboardingSceneLoading();
    }

    final colors = AppColors.of(context);
    final daily = _daily;
    final verified = daily != null;
    final racerName = widget.displayName?.trim();
    final handle = atName(
      racerName == null || racerName.isEmpty ? 'Racer' : racerName,
    );
    final title = verified
        ? (daily['name'] as String? ?? 'Daily Race')
        : 'Your first race is waiting';

    return OnboardingScene(
      headline: title,
      emblem: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: colors.textLight.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: colors.textLight.withValues(alpha: 0.30),
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.emoji_events_rounded,
          size: 54,
          color: colors.pillGold,
        ),
      ),
      dockLabel: verified ? 'TODAY’S RACE' : 'READY TO RACE',
      dockBody: verified
          ? '$_timeRemaining · Move at your own pace. Most steps at the finish wins.'
          : 'We couldn’t confirm a Daily spot right now. You can still enter Bara and find a race.',
      dockExtra: verified
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.parchmentLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.woodDark, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    handle,
                    style: PixelText.title(size: 20, color: colors.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This is your racer tag—the name other players see. It won’t change how you sign in, and you can update it anytime in Profile.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                ],
              ),
            )
          : null,
      actions: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: PillButton(
            key: const Key('onboarding-v2-primary'),
            label: verified
                ? (_entering ? 'OPENING...' : 'SEE MY RACE')
                : 'FIND A RACE',
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            padding: EdgeInsets.zero,
            onPressed: _entering
                ? null
                : verified
                ? _enter
                : widget.onFindRace,
          ),
        ),
      ],
    );
  }
}

/// Tailored welcome for a referred user (onboarding step 0). Greets them by
/// inviter and states the shared reward, then a single "Let's go" advances into
/// the normal gates. Best-effort: if the inviter preview can't be fetched it
/// falls back to a generic "A friend invited you" so onboarding never stalls.
class OnboardingReferralWelcomeStep extends StatefulWidget {
  const OnboardingReferralWelcomeStep({
    super.key,
    required this.code,
    required this.onContinue,
    this.onFetchPreview,
  });

  final String code;
  final VoidCallback onContinue;
  final Future<Map<String, dynamic>> Function(String code)? onFetchPreview;

  @override
  State<OnboardingReferralWelcomeStep> createState() =>
      _OnboardingReferralWelcomeStepState();
}

class _OnboardingReferralWelcomeStepState
    extends State<OnboardingReferralWelcomeStep> {
  bool _loading = true;
  String? _inviterName;
  String? _inviterAvatar;
  int? _rewardCoins;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final fetch = widget.onFetchPreview;
    if (fetch == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final preview = await fetch(widget.code);
      if (!mounted) return;
      setState(() {
        _inviterName = preview['inviterName'] as String?;
        _inviterAvatar = preview['inviterAvatar'] as String?;
        _rewardCoins = (preview['rewardCoins'] as num?)?.toInt();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviter = _inviterName;
    final headline = inviter != null && inviter.isNotEmpty
        ? '${atName(inviter)} invited you to Bara'
        : 'A friend invited you to Bara';
    final reward = _rewardCoins;
    final body = reward != null && reward > 0
        ? 'Finish your first race and you’ll both earn coins — '
              '$reward to get you started.'
        : 'Finish your first race and you’ll both earn coins.';

    if (_loading) {
      return const OnboardingSceneLoading();
    }

    return OnboardingScene(
      headline: headline,
      emblem: AppAvatar(
        name: inviter ?? 'Friend',
        imageUrl: _inviterAvatar,
        size: 96,
        borderColor: AppColors.of(context).textLight,
        borderWidth: 3,
      ),
      dockLabel: 'YOU’RE INVITED',
      dockBody: body,
      actions: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: PillButton(
            label: "LET'S GO",
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            padding: EdgeInsets.zero,
            icon: Icons.arrow_forward_rounded,
            onPressed: widget.onContinue,
          ),
        ),
      ],
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
    final colors = AppColors.of(context);
    return OnboardingScene(
      headline: 'Earn your first 100 coins',
      emblem: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          color: colors.textLight.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: colors.textLight.withValues(alpha: 0.30),
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '100',
          style: PixelText.title(size: 38, color: colors.textLight),
        ),
      ),
      dockLabel: 'FIRST 100 COINS',
      dockBody:
          'Take the quick tour to learn how Bara works — '
          'finish it and we’ll drop 100 coins in your '
          'balance to get you started.',
      actions: [
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
        const SizedBox(height: 2),
        TextButton(
          onPressed: onSkip,
          child: Text(
            'Skip for now',
            style: PixelText.body(
              size: 14,
              color: colors.textMid,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Onboarding step 4 (redesigned): the user is ALREADY auto-enrolled in the
/// Daily & Weekly challenge server-side on account creation (see
/// `autoEnrollNewUser.js`), so this step no longer asks them to pick a race. It
/// celebrates the enrollment, tells them the 3 welcome boxes are waiting and how
/// to opt out, then drops them straight into the live Daily race.
///
/// This step never joins a race itself (that already happened) — the CTA hands
/// off to [onEnterDaily], which closes the onboarding gate and routes to the
/// active Daily race, or falls back to Home when none is available.
class OnboardingAutoEnrolledStep extends StatefulWidget {
  const OnboardingAutoEnrolledStep({
    super.key,
    required this.onEnterDaily,
    required this.onSkip,
    this.skipForPendingShare = false,
  });

  /// Closes the first-race gate and routes into the live Daily race (or Home on
  /// fallback). Awaited so the button can show a pressed/working state.
  final Future<void> Function() onEnterDaily;

  /// Used only for the pending-share precedence path: a specific race is already
  /// queued, so skip this celebration and let MainShell open that race instead.
  final VoidCallback onSkip;

  /// When true, a share link is pending — auto-skip so onboarding hands off to
  /// the queued race rather than the generic Daily drop-in.
  final bool skipForPendingShare;

  @override
  State<OnboardingAutoEnrolledStep> createState() =>
      _OnboardingAutoEnrolledStepState();
}

class _OnboardingAutoEnrolledStepState extends State<OnboardingAutoEnrolledStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  bool _entering = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    // A pending share link means the user already has a specific race queued;
    // hand off immediately rather than showing the generic Daily celebration.
    if (widget.skipForPendingShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSkip();
      });
      return;
    }
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_entering) return;
    setState(() => _entering = true);
    // On success MainShell exits onboarding + routes (Daily race or Home); this
    // widget is torn down, so the mounted guard covers the fallback path.
    await widget.onEnterDaily();
    if (mounted) setState(() => _entering = false);
  }

  @override
  Widget build(BuildContext context) {
    // While a share link is pending we're auto-skipping — render a neutral
    // holding view (no CTA) so the celebration never flashes before the handoff.
    if (widget.skipForPendingShare) {
      return const OnboardingSceneLoading();
    }

    return OnboardingScene(
      headline: 'Entered in the Daily & Weekly challenge',
      emblem: _EnrolledEmblem(animation: _intro, size: 108),
      sceneExtra: const Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          _EnrolledChip(icon: Icons.bolt_rounded, label: 'DAILY 10K'),
          _EnrolledChip(icon: Icons.calendar_month_rounded, label: 'WEEKLY'),
          _EnrolledChip(icon: Icons.card_giftcard_rounded, label: '3 BOXES'),
        ],
      ),
      dockLabel: "YOU'RE IN",
      dockBody:
          'We saved you a spot in both races and dropped '
          '3 mystery boxes in your bag. You can turn '
          'auto-join off anytime on the Races page.',
      actions: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: PillButton(
            label: _entering ? 'STARTING...' : 'START THE DAILY CHALLENGE',
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            padding: EdgeInsets.zero,
            icon: Icons.play_arrow_rounded,
            onPressed: _entering ? null : _enter,
          ),
        ),
      ],
    );
  }
}

/// The celebratory badge at the top of the auto-enrolled step. A soft ring with
/// a checkmark that pops in on entry (scale + fade) — juice without confetti
/// (confetti is reserved for actual race finishes).
class _EnrolledEmblem extends StatelessWidget {
  const _EnrolledEmblem({required this.animation, required this.size});

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(parent: animation, curve: Curves.elasticOut);
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.5, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.55, end: 1).animate(pop),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.of(context).textLight.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.of(context).textLight.withValues(alpha: 0.30),
              width: 3,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: size * 0.5,
            color: AppColors.of(context).textLight,
          ),
        ),
      ),
    );
  }
}

/// A small labeled pill summarizing what the user was auto-enrolled into.
class _EnrolledChip extends StatelessWidget {
  const _EnrolledChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.of(context).textLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.of(context).textLight.withValues(alpha: 0.28),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.of(context).textLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: PixelText.body(
              size: 11,
              color: AppColors.of(context).textLight,
            ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}
