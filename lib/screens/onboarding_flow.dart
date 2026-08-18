import 'package:flutter/material.dart';

import '../widgets/app_avatar.dart';
import '../widgets/onboarding_permission_gate.dart';
import '../widgets/onboarding_scene.dart';
import '../widgets/pill_button.dart';
import '../styles.dart';
import '../utils/at_name.dart';
// One shared definition of the qualifying race, so the referred-install scene
// can't drift from the referral screen / Get Coins copy.
import 'referral_screen.dart' show kReferralQualificationCopy;

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
    this.onboardingV3Enabled = false,
    this.tutorialMandatory = false,
    this.healthAttemptCount = 0,
    this.onOpenHealthSettings,
    this.onEscapeHealthGate,
    this.onFetchInviterRace,
    this.onJoinInviterRace,
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

  /// Explicit remote opt-in to the onboarding revamp. False/missing renders
  /// the v2 (or v1) sequence byte-for-byte as it ships today — that is the
  /// rollback path, and it is why the v2 branch below is untouched.
  final bool onboardingV3Enabled;

  /// Batch 2026-08-09 item 9. True only when the backend flag
  /// `tutorialMandatoryEnabled` is on AND the host's local abandon circuit
  /// breaker has not tripped — the host owns that decision. Defaults false, so
  /// an older backend renders this flow exactly as it ships today.
  final bool tutorialMandatory;

  /// How many completed health-permission attempts the user has made. Drives
  /// the Android ladder; the host owns the counter (it must survive an app
  /// kill mid-onboarding).
  final int healthAttemptCount;

  /// Launches the platform health settings. Only wired once retrying has
  /// stopped being useful.
  final VoidCallback? onOpenHealthSettings;

  /// Lets the user out of the health gate into the degraded state.
  final VoidCallback? onEscapeHealthGate;

  /// Resolves the inviter's joinable race for a referred install
  /// (`GET /referrals/inviter-race`). Null result, `{race: null}`, a 404 from
  /// an older backend, or any error all fall through to the Daily intro.
  final Future<Map<String, dynamic>?> Function()? onFetchInviterRace;

  /// Joins the inviter's race and hands off to it, closing the first-race gate.
  final Future<void> Function(String raceId)? onJoinInviterRace;

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
    //
    // "Hard-blocking" is the default posture, not an absolute (spec §3): the
    // gate blocks until the OS has demonstrably stopped cooperating, at which
    // point the host wires the settings launcher and the escape hatch. A user
    // who simply hasn't tapped Allow yet is still blocked.
    if (!healthAuthorized) {
      return OnboardingPermissionGate(
        label: 'HEALTH DATA',
        headline: 'Connect steps to start racing',
        // Item 6 (batch 2026-08-08): the privacy pitch, expanded. It must stay
        // TRUTHFUL — we DO store step counts and a display name server-side, so
        // this never claims "we collect nothing"; it is specific about what we
        // do not read and what we never do with it.
        body:
            'Bara only reads your step count. It never reads your routes, '
            'workouts, heart rate, or location. Your steps are used for races and '
            'nothing else, and we never sell your data.',
        icon: Icons.favorite_rounded,
        onContinue: onEnableHealth,
        error: error,
        isLoading: isLoading,
        retryLabel: 'TRY AGAIN',
        onOpenSettings: onboardingV3Enabled ? onOpenHealthSettings : null,
        onEscape: onboardingV3Enabled ? onEscapeHealthGate : null,
      );
    }

    // V3: notifications are no longer a gate — the ask moved to the first
    // mystery-box open (§5.4), with a third-session backstop. The tutorial is
    // deliberately back in the critical path, cut from ten steps to five, and
    // sits BEFORE the race intro because that intro's CTA drops the user into
    // a live race — they should know what a race is first (§5.11.2).
    if (onboardingV3Enabled) {
      if (!tutorialOnboardingSeen) {
        // Demo-race spec §5.8: same position, same two callbacks — the
        // passive spotlight walkthrough is replaced by a playable 90-second
        // race the user wins. The spotlight tutorial itself is untouched and
        // still reachable from Profile → Settings.
        return OnboardingDemoRaceStep(
          onStart: onStartTutorial,
          onSkip: onSkipTutorial,
          mandatory: tutorialMandatory,
        );
      }
      return OnboardingInviterRaceStep(
        displayName: displayName,
        skipForPendingShare: firstRaceShareTokenPending,
        onSkipForShare: onSkipFirstRace,
        onFetchInviterRace: onFetchInviterRace,
        onJoinInviterRace: onJoinInviterRace,
        onFetchDaily: onFetchActiveDaily,
        onEnterDaily: onEnterVerifiedDaily,
        onFindRace: onFindRace,
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
        mandatory: tutorialMandatory,
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

  Future<void> _enter() async {
    final raceId = (_daily?['raceId'] ?? _daily?['id']) as String?;
    if (raceId == null || raceId.isEmpty || _entering) return;
    setState(() => _entering = true);
    await widget.onEnterDaily?.call(raceId);
    if (mounted) setState(() => _entering = false);
  }

  @override
  Widget build(BuildContext context) => OnboardingTheme(builder: _buildStep);

  // Pinned to the daytime palette: the racer-tag card below is built here,
  // above OnboardingScene's own Theme, so its fill and its text have to come
  // from the palette the scene renders under.
  Widget _buildStep(BuildContext context) {
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
    // The headline used to be the race's own name ("Daily 10K Sprint"), which
    // read as a title card for a thing the user had no context for. Say what
    // this moment actually is instead — the race name is not load-bearing here.
    final title = verified
        ? 'Now you’re ready to join your first race'
        : 'Your first race is waiting';

    return OnboardingScene(
      headline: title,
      // No trophy emblem: the race name IS the centerpiece here, and a generic
      // cup in a ring only pushed it up into the corner of the sky.
      dockLabel: verified ? 'DAILY CHALLENGE' : 'READY TO RACE',
      // The one thing worth saying here, and the only thing the demo could not
      // teach: the next race is not a script. The countdown-plus-rules line
      // this replaced was a third voice explaining mechanics they just played.
      dockBody: verified
          ? 'Your first real race, against real people walking right now.'
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
                    'This is your racer tag. It’s the name other players see. It won’t change how you sign in, and you can update it anytime in Profile.',
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
                ? (_entering ? 'OPENING...' : 'JOIN RACE')
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

/// V3's final gate for a referred user: land on the *inviter's* race instead of
/// the generic Daily intro (spec §5.8).
///
/// The fallback is the important part. `GET /referrals/inviter-race` is a new
/// endpoint, and the backend deploys independently of the app — a client
/// carrying this code can absolutely hit a backend that has never heard of it.
/// A 404, a timeout, any error, an explicit `{race: null}`, or simply no wired
/// fetcher all render [OnboardingDailyIntroStep] exactly as today. There is no
/// error state here on purpose: a referred user who can't be matched is just an
/// ordinary new user, and should be treated as one.
class OnboardingInviterRaceStep extends StatefulWidget {
  const OnboardingInviterRaceStep({
    super.key,
    required this.displayName,
    required this.skipForPendingShare,
    required this.onSkipForShare,
    this.onFetchInviterRace,
    this.onJoinInviterRace,
    this.onFetchDaily,
    this.onEnterDaily,
    this.onFindRace,
  });

  final String? displayName;
  final bool skipForPendingShare;
  final VoidCallback onSkipForShare;
  final Future<Map<String, dynamic>?> Function()? onFetchInviterRace;
  final Future<void> Function(String raceId)? onJoinInviterRace;
  final Future<Map<String, dynamic>?> Function()? onFetchDaily;
  final Future<void> Function(String raceId)? onEnterDaily;
  final Future<void> Function()? onFindRace;

  @override
  State<OnboardingInviterRaceStep> createState() =>
      _OnboardingInviterRaceStepState();
}

class _OnboardingInviterRaceStepState extends State<OnboardingInviterRaceStep> {
  bool _loading = true;
  bool _joining = false;
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _inviter;

  @override
  void initState() {
    super.initState();
    if (widget.skipForPendingShare) {
      // A pending share link is a more specific intent than a referral offer;
      // hand off immediately rather than showing either race screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSkipForShare();
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final fetch = widget.onFetchInviterRace;
    if (fetch == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final payload = await fetch();
      if (!mounted) return;
      final race = payload?['race'];
      final inviter = payload?['inviter'];
      setState(() {
        _race = race is Map<String, dynamic> ? race : null;
        _inviter = inviter is Map<String, dynamic> ? inviter : null;
        _loading = false;
      });
    } catch (_) {
      // 404 on an older backend, offline, timeout — all identical here.
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _inviterName {
    final raw = (_inviter?['displayName'] as String?)?.trim();
    return (raw == null || raw.isEmpty) ? 'your friend' : raw;
  }

  Future<void> _join() async {
    final raceId = (_race?['id'] ?? _race?['raceId']) as String?;
    if (raceId == null || raceId.isEmpty || _joining) return;
    setState(() => _joining = true);
    await widget.onJoinInviterRace?.call(raceId);
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) => OnboardingTheme(builder: _buildStep);

  // Pinned to the daytime palette: this step's scene args are built here,
  // above OnboardingScene's own Theme, so they must read the palette the
  // scene renders under rather than the device's.
  Widget _buildStep(BuildContext context) {
    if (widget.skipForPendingShare || _loading) {
      return const OnboardingSceneLoading();
    }

    final race = _race;
    if (race == null) {
      return OnboardingDailyIntroStep(
        displayName: widget.displayName,
        skipForPendingShare: false,
        onSkipForShare: widget.onSkipForShare,
        onFetchDaily: widget.onFetchDaily,
        onEnterDaily: widget.onEnterDaily,
        onFindRace: widget.onFindRace,
      );
    }

    final colors = AppColors.of(context);
    final name = _inviterName;
    final steps = (_inviter?['steps'] as num?)?.toInt();
    final alreadyJoined = race['alreadyJoined'] == true;
    final raceName = (race['name'] as String?) ?? 'their race';

    return OnboardingScene(
      headline: 'Race $name',
      emblem: AppAvatar(
        name: name,
        imageUrl: _inviter?['profilePhotoUrl'] as String?,
        size: 96,
        borderColor: colors.textLight,
        borderWidth: 3,
      ),
      dockLabel: alreadyJoined ? 'YOU’RE BOTH IN' : 'YOUR FIRST RACE',
      dockBody: alreadyJoined
          ? 'You’re both in $raceName. Start walking. Every step counts from now.'
          : steps != null && steps > 0
          ? '$name is ${_formatSteps(steps)} steps into $raceName. Jump in and start closing the gap.'
          : '$name is racing in $raceName. Jump in and start closing the gap.',
      actions: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: PillButton(
            key: const Key('onboarding-inviter-race-primary'),
            label: _joining
                ? 'OPENING...'
                : alreadyJoined
                ? 'OPEN THE RACE'
                : "JOIN ${name.toUpperCase()}'S RACE",
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            fontSize: 14,
            padding: EdgeInsets.zero,
            onPressed: _joining ? null : _join,
          ),
        ),
      ],
    );
  }
}

String _formatSteps(int steps) {
  final digits = steps.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
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
  // Additive per batch 2026-07-27 §4.3. Absent on an older backend, in which
  // case the body states no figure at all rather than a hardcoded one.
  int? _referrerCoins;
  int? _refereeCoins;

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
        _referrerCoins = (preview['referrerCoins'] as num?)?.toInt();
        _refereeCoins = (preview['refereeCoins'] as num?)?.toInt();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => OnboardingTheme(builder: _buildStep);

  // Pinned to the daytime palette: this step's scene args are built here,
  // above OnboardingScene's own Theme, so they must read the palette the
  // scene renders under rather than the device's.
  Widget _buildStep(BuildContext context) {
    final inviter = _inviterName;
    final headline = inviter != null && inviter.isNotEmpty
        ? '${atName(inviter)} invited you to Bara'
        : 'A friend invited you to Bara';
    // The referee's figure: prefer the explicit field, fall back to the older
    // `rewardCoins` key, and accept that both may be missing.
    final mine = _refereeCoins ?? _rewardCoins;
    final theirs = _referrerCoins;
    final String body;
    // Batch 2026-08-09 item 2: an auto-enrolled daily challenge is a "first
    // race" but no longer completes the referral, so the qualifying action is
    // named explicitly here too.
    if (mine == null || mine <= 0) {
      body = 'Coins start landing after you qualify. '
          '$kReferralQualificationCopy';
    } else if (theirs != null && theirs == mine) {
      body = 'You each pocket $mine coins. Yours to spend right away. '
          '$kReferralQualificationCopy';
    } else {
      body = '$mine coins are yours. $kReferralQualificationCopy';
    }

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
    this.mandatory = false,
  });

  final VoidCallback onStart;
  final VoidCallback onSkip;

  /// Batch 2026-08-09 item 9. Defaults FALSE so every existing call site —
  /// and every backend that doesn't serve `tutorialMandatoryEnabled` — keeps
  /// the skip affordance exactly as it ships today.
  final bool mandatory;

  @override
  Widget build(BuildContext context) => OnboardingTheme(builder: _buildStep);

  // Pinned to the daytime palette: this step's scene args are built here,
  // above OnboardingScene's own Theme, so they must read the palette the
  // scene renders under rather than the device's.
  Widget _buildStep(BuildContext context) {
    final colors = AppColors.of(context);
    return OnboardingScene(
      headline: 'Earn your first 100 coins',
      emblem: Container(
        width: 112,
        height: 112,
        decoration: onboardingSkyRing(context, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          '100',
          style: PixelText.title(size: 38, color: colors.textLight),
        ),
      ),
      dockLabel: 'FIRST 100 COINS',
      // Item 9 mirror of the v3 copy: when the step can't be skipped, the
      // body has to answer "how long is this?" before the user goes looking
      // for a way out.
      dockBody:
          'A quick tour of how Bara works. We promise it’s fast, '
          'and you keep the 100 coins.',
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
        // Item 9: under mandatory mode the escape hatch is not rendered at
        // all — a disabled-looking control invites tapping at it.
        if (!mandatory) const SizedBox(height: 2),
        if (!mandatory)
          TextButton(
            key: const Key('onboarding-tutorial-skip'),
            onPressed: onSkip,
            child: Text(
              'Skip for now',
              // textMid is a dark ink meant for parchment; on the dock's green
              // checkers it was near-invisible. Cream + the same sky outline the
              // headline uses makes it legible without turning a deliberately
              // quiet escape hatch into a second button.
              style:
                  PixelText.body(
                    size: 15,
                    color: colors.textLight.withValues(alpha: 0.92),
                  ).copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.textLight.withValues(alpha: 0.55),
                    shadows: PixelText.skyOutline(1.4),
                  ),
            ),
          ),
      ],
    );
  }
}

/// The v3 teaching step: a playable 90-second demo race the user wins.
///
/// The old step sold a tour ("take the quick tour"). This one sells a race,
/// because that is what it is — and the promise on the button has to match what
/// the tap actually opens.
class OnboardingDemoRaceStep extends StatelessWidget {
  const OnboardingDemoRaceStep({
    super.key,
    required this.onStart,
    required this.onSkip,
    this.mandatory = false,
  });

  final VoidCallback onStart;
  final VoidCallback onSkip;

  /// Batch 2026-08-09 item 9. Defaults FALSE — see [OnboardingTutorialStep].
  final bool mandatory;

  @override
  Widget build(BuildContext context) => OnboardingTheme(builder: _buildStep);

  // Pinned to the daytime palette: this step's scene args are built here,
  // above OnboardingScene's own Theme, so they must read the palette the
  // scene renders under rather than the device's.
  Widget _buildStep(BuildContext context) {
    final colors = AppColors.of(context);
    return OnboardingScene(
      // Framed as learning, not winning. "Win your first race" reads like a
      // challenge you can decline — and the whole problem with this step is
      // people skipping it. A practice run against bots asks for 90 seconds of
      // curiosity instead of a commitment to compete.
      headline: 'Learn how to race',
      // No emblem. A flag in a ring said nothing the headline and the dock
      // don't already say, and it cut the sky in half. Without it the scene is
      // the wordmark, the capybara and the sky — the title screen's own
      // composition.
      dockLabel: '90 SECONDS · 100 COINS',
      // One line. The label above already carries "90 SECONDS · 100 COINS", so
      // repeating the duration or the payout here just adds words to skim past.
      //
      // Item 9 reframes it around the objection instead of the content: with
      // no "Skip for now" underneath, the sentence has to do the reassuring
      // the escape hatch used to do. The dock label keeps the numbers.
      dockBody:
          'A quick 90-second practice race against three bots. We promise '
          'it’s fast, and you keep the 100 coins.',
      actions: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: PillButton(
            key: const Key('onboarding-demo-race-start'),
            // "START THE RACE" over-promised: what opens is a guided practice
            // run, and a user who taps expecting their real race reads the
            // coach marks as an interruption.
            label: 'START THE TUTORIAL',
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            padding: EdgeInsets.zero,
            icon: Icons.play_arrow_rounded,
            onPressed: onStart,
          ),
        ),
        // Item 9: same treatment as the v1/v2 mirror above.
        if (!mandatory) const SizedBox(height: 2),
        if (!mandatory)
          TextButton(
            key: const Key('onboarding-demo-race-skip'),
            onPressed: onSkip,
            child: Text(
              'Skip for now',
              // textMid is a dark ink meant for parchment; on the dock's green
              // checkers it was near-invisible. Cream + the same sky outline the
              // headline uses makes it legible without turning a deliberately
              // quiet escape hatch into a second button.
              style:
                  PixelText.body(
                    size: 15,
                    color: colors.textLight.withValues(alpha: 0.92),
                  ).copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.textLight.withValues(alpha: 0.55),
                    shadows: PixelText.skyOutline(1.4),
                  ),
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
      headline: 'The Daily and Weekly are yours to win',
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
          'We saved you a spot in both and dropped 3 mystery '
          'boxes in your bag. Turn auto-join off anytime on '
          'the Races page.',
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
          decoration: onboardingSkyRing(context, shape: BoxShape.circle),
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
      decoration: onboardingSkyRing(
        context,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(999),
        borderWidth: 1.5,
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
