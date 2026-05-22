import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../config/backend_config.dart';
import '../models/loadable.dart';
import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/background_sync_bootstrap_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/sync_stale_chip.dart';
import '../widgets/trail_sign.dart';
import '../widgets/wooden_tab_bar.dart';
import 'start_screen.dart';
import 'tabs/friends_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/leaderboard_tab.dart';
import 'tabs/profile_tab.dart';
import 'create_race_screen.dart';
import 'race_detail_screen.dart';
import 'tabs/races_tab.dart';
import 'tabs/shop_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.authService,
    this.healthService,
    this.backendApiService,
    this.backgroundSyncBootstrapService,
    this.notificationService,
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final BackgroundSyncBootstrapService? backgroundSyncBootstrapService;
  final NotificationService? notificationService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final HealthService _healthService;
  late final BackendApiService _backendApiService;
  late final BackgroundSyncBootstrapService _backgroundSyncBootstrapService;

  int _currentTab = 0;
  late final PageController _pageController;
  bool _healthAuthorized = false;
  bool?
  _notificationsState; // null = not prompted, true = granted, false = denied
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;
  bool _syncStale = false;
  int? _stepGoal;
  int _incomingFriendRequests = 0;
  String? _displayName;
  String? _email;
  List<Map<String, dynamic>> _friendsSteps = [];
  Loadable<List<Map<String, dynamic>>> _friendsStepsState =
      const Loadable.initial();
  Map<String, dynamic>? _racesData;
  Loadable<Map<String, dynamic>> _racesState = const Loadable.initial();
  List<Map<String, dynamic>> _equippedAccessories = const [];
  Loadable<Map<String, dynamic>> _shopCatalogState = const Loadable.initial();
  List<Map<String, dynamic>> _leaderboardHighlights = const [];
  Loadable<List<Map<String, dynamic>>> _leaderboardHighlightsState =
      const Loadable.loading();
  bool _leaderboardHighlightsLoading = true;
  Map<String, dynamic>? _raceCard;
  String _requestedLeaderboardType = 'steps';
  String _requestedLeaderboardPeriod = 'today';
  int _leaderboardSelectionNonce = 0;
  Timer? _foregroundPollTimer;
  static const Duration _foregroundPollInterval = Duration(minutes: 5);

  void _handleAuthServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _healthService = widget.healthService ?? HealthService();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _backgroundSyncBootstrapService =
        widget.backgroundSyncBootstrapService ??
        BackgroundSyncBootstrapService();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthServiceChanged);
    widget.notificationService?.pendingAction.addListener(
      _onNotificationAction,
    );
    _restoreAndFetch();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService == widget.authService) return;
    oldWidget.authService.removeListener(_handleAuthServiceChanged);
    widget.authService.addListener(_handleAuthServiceChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleAuthServiceChanged);
    widget.notificationService?.pendingAction.removeListener(
      _onNotificationAction,
    );
    _foregroundPollTimer?.cancel();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onNotificationAction() {
    final action = widget.notificationService?.pendingAction.value;
    if (action == null) return;
    widget.notificationService?.pendingAction.value = null;

    switch (action.route) {
      case NotificationRoute.raceDetail:
        final raceId = action.params['raceId'];
        if (raceId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RaceDetailScreen(
                authService: widget.authService,
                raceId: raceId,
                friends: _friendsSteps,
              ),
            ),
          );
        }
        break;
      case NotificationRoute.races:
        _pageController.jumpToPage(1);
        break;
      case NotificationRoute.friends:
        _openFriendsTab();
        break;
      case NotificationRoute.home:
        _pageController.jumpToPage(0);
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAuthorized) {
      _fetchSteps();
      _refreshStepGoal();
      _fetchFriendsSteps();
      _fetchRaces();
      _fetchShopCatalog();
      _fetchLeaderboardHighlights();
      _fetchRaceCard();
      _startForegroundPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopForegroundPolling();
    }
  }

  void _startForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = Timer.periodic(_foregroundPollInterval, (_) {
      if (_healthAuthorized) {
        _fetchSteps();
        _refreshStepGoal();
      }
    });
  }

  void _stopForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = null;
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });

    final sessionIsValid = await _refreshSessionToken();
    if (!sessionIsValid || !mounted) return;

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
    await _checkNotificationState();
    _fetchLeaderboardHighlights();
    _fetchRaceCard();
    await _fetchSteps();
    _refreshStepGoal();
    _fetchFriendsSteps();
    _fetchRaces();
    _fetchShopCatalog();
    _startForegroundPolling();
  }

  Future<bool> _refreshSessionToken() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return false;

      final data = await _backendApiService.refreshSessionToken(
        authToken: token,
      );
      final newToken = data['sessionToken'] as String?;
      final user = data['user'] as Map<String, dynamic>?;
      if (newToken != null) {
        await widget.authService.updateSessionToken(newToken);
      }
      if (user != null) {
        await widget.authService.syncFromBackendUser(user);
      }
      return true;
    } catch (error) {
      if (isAuthenticationFailure(error)) {
        await widget.authService.signOut();
        if (!mounted) return false;

        showErrorToast(context, 'Session expired. Please sign in again.');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const StartScreen()),
          (route) => false,
        );
        return false;
      }
      return true;
    }
  }

  Future<void> _enableHealthData() async {
    setState(() => _isLoading = true);

    try {
      final authorized = await _healthService.requestAuthorization();
      if (!authorized) {
        setState(() {
          _isLoading = false;
          _error =
              'Health data access not granted.\nPlease allow access in Settings.';
        });
        return;
      }

      setState(() => _healthAuthorized = true);
      await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
      await _checkNotificationState();
      _fetchLeaderboardHighlights();
      _fetchRaceCard();
      await _fetchSteps();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to request health access:\n$e';
      });
    }
  }

  Future<void> _checkNotificationState() async {
    final ns = widget.notificationService;
    if (ns == null) {
      if (mounted) {
        setState(() => _notificationsState = true);
      }
      return;
    }

    final state = await ns.getPermissionState();
    if (!mounted) return;

    if (state == true) {
      // Already granted — silently re-register token for this session
      ns.requestPermission(widget.authService.authToken);
      setState(() => _notificationsState = true);
    } else if (state == false) {
      // Previously denied — don't nag
      setState(() => _notificationsState = false);
    } else {
      // Never prompted — show the opt-in screen
      setState(() => _notificationsState = null);
    }
  }

  Future<void> _enableNotifications() async {
    final ns = widget.notificationService;
    if (ns == null) return;

    final granted = await ns.requestPermission(widget.authService.authToken);
    if (!mounted) return;
    setState(() => _notificationsState = granted);
  }

  Future<void> _fetchSteps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final identityToken = widget.authService.authToken;
      final stepEntries = [await _healthService.getStepsToday()];
      final stepData = stepEntries.last;
      bool syncFailed = false;

      if (identityToken != null && identityToken.isNotEmpty) {
        Future<void> pushSteps() async {
          for (final dailyStep in stepEntries) {
            await _backendApiService.recordSteps(
              identityToken: identityToken,
              stepData: dailyStep,
            );
          }
        }

        try {
          await pushSteps();
        } catch (_) {
          // Cold-start blip from background → foreground is common.
          // Silently retry once before flagging the sync as stale.
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
            await pushSteps();
          } catch (_) {
            syncFailed = true;
          }
        }

        if (!syncFailed) {
          try {
            final now = DateTime.now();
            final hourlySamples = await _healthService.getHourlySteps(
              startTime: DateTime(now.year, now.month, now.day),
              endTime: now,
            );
            if (hourlySamples.isNotEmpty) {
              await _backendApiService.recordStepSamples(
                identityToken: identityToken,
                samples: hourlySamples,
              );
            }
          } catch (_) {
            // Don't fail the main sync if hourly samples fail
          }
        }
      }

      setState(() {
        _stepData = stepData;
        _isLoading = false;
        _error = null;
        _syncStale = syncFailed;
      });

      _fetchFriendsSteps();
      _refreshStepGoal();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to fetch steps:\n$e';
      });
    }
  }

  Future<void> _fetchFriendsSteps() async {
    final previous = _friendsSteps;
    if (mounted) {
      setState(() {
        _friendsStepsState = previous.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _friendsStepsState = Loadable.error(
              'Not signed in.',
              data: previous,
            );
          });
        }
        return;
      }

      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final friends = await _backendApiService.fetchFriendsSteps(
        identityToken: identityToken,
        date: date,
      );

      if (mounted) {
        setState(() {
          _friendsSteps = friends;
          _friendsStepsState = Loadable.success(friends);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _friendsStepsState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  Future<void> _fetchRaces() async {
    final previous = _racesData;
    if (mounted) {
      setState(() {
        _racesState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _racesState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      final data = await _backendApiService.fetchRaces(
        identityToken: identityToken,
      );

      if (mounted) {
        setState(() {
          _racesData = data;
          _racesState = Loadable.success(data);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _racesState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  Future<void> _fetchShopCatalog() async {
    final previous = _shopCatalogState.data;
    if (mounted) {
      setState(() {
        _shopCatalogState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _shopCatalogState = Loadable.error(
              'Not signed in.',
              data: previous,
            );
          });
        }
        return;
      }

      final data = await _backendApiService.fetchShopCatalog(
        identityToken: identityToken,
      );
      _applyShopCatalog(data);
      if (mounted) {
        setState(() => _shopCatalogState = Loadable.success(data));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shopCatalogState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  void _applyShopCatalog(Map<String, dynamic> catalog) {
    final equipped = catalog['equipped'] as Map<String, dynamic>? ?? {};
    final accessories = equipped.values
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final coins = catalog['coins'] as int?;

    if (coins != null) {
      widget.authService.updateCoins(coins);
    }

    if (mounted) {
      setState(() => _equippedAccessories = accessories);
    }
  }

  Future<void> _refreshRacesTab() async {
    await Future.wait([_fetchRaces(), _fetchFriendsSteps()]);
  }

  Future<void> _refreshHomeTab() async {
    await Future.wait([
      _fetchSteps(),
      _fetchLeaderboardHighlights(),
      _fetchShopCatalog(),
      _fetchRaceCard(),
    ]);
  }

  Future<void> _fetchRaceCard() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      final data = await _backendApiService.fetchHomeRaceCard(
        identityToken: identityToken,
      );
      if (mounted) {
        setState(() => _raceCard = data);
      }
    } catch (_) {
      // Card is non-critical; ignore fetch errors and keep last value.
    }
  }

  void _openRaceFromCard(String raceId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RaceDetailScreen(
          authService: widget.authService,
          raceId: raceId,
          friends: _friendsSteps,
        ),
      ),
    );
  }

  Future<void> _joinRaceFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.joinPublicRace(
        identityToken: identityToken,
        raceId: raceId,
      );
      if (mounted) {
        showInfoToast(context, 'Joined the race.');
      }
      await _fetchRaceCard();
      _openRaceFromCard(raceId);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Could not join: $e');
      }
    }
  }

  Future<void> _acceptRaceInviteFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.respondToRaceInvite(
        identityToken: identityToken,
        raceId: raceId,
        accept: true,
      );
      if (mounted) showInfoToast(context, 'Accepted.');
      await _fetchRaceCard();
      _openRaceFromCard(raceId);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not accept: $e');
    }
  }

  Future<void> _declineRaceInviteFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.respondToRaceInvite(
        identityToken: identityToken,
        raceId: raceId,
        accept: false,
      );
      if (mounted) showInfoToast(context, 'Declined.');
      await _fetchRaceCard();
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not decline: $e');
    }
  }

  void _challengeFriendBack(String friendUserId) {
    // v1: just opens create-race; friend pre-selection can be wired up later.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateRaceScreen(
          authService: widget.authService,
          backendApiService: _backendApiService,
        ),
      ),
    );
  }

  Future<void> _refreshFriendsTab() async {
    await _refreshStepGoal();
  }

  Future<void> _refreshProfileTab() async {
    await _refreshStepGoal();
  }

  void _openFriendsTab() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FriendsTab(
          authService: widget.authService,
          onFriendsChanged: () {
            _refreshStepGoal();
            _fetchFriendsSteps();
          },
          onRefresh: _refreshFriendsTab,
          backendApiService: _backendApiService,
          stepData: _stepData,
          stepGoal: _stepGoal,
          displayName: _displayName,
          onOpenProfile: _openProfile,
        ),
      ),
    );
  }

  void _openLeaderboardTab() {
    _pageController.animateToPage(
      3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _openLeaderboardHighlight(String leaderboardType, String period) {
    setState(() {
      _requestedLeaderboardType = leaderboardType;
      _requestedLeaderboardPeriod = period;
      _leaderboardSelectionNonce += 1;
    });
    _openLeaderboardTab();
  }

  Future<ImageSource?> _showProfilePhotoSourceSheet() async {
    return showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Add a profile photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _addOrChangeProfilePhoto() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    final source = await _showProfilePhotoSourceSheet();
    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      const contentType = 'image/jpeg';
      final upload = await _backendApiService.requestProfilePhotoUpload(
        identityToken: token,
        contentType: contentType,
      );

      await _backendApiService.uploadProfilePhotoBytes(
        uploadUrl: upload['uploadUrl'] as String,
        bytes: bytes,
        contentType: contentType,
      );

      final user = await _backendApiService.saveProfilePhoto(
        identityToken: token,
        key: upload['key'] as String,
        url: upload['publicUrl'] as String,
      );

      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      await _refreshProfileSurfaces();

      if (mounted) {
        showInfoToast(context, 'Profile photo updated.');
      }
    } on PlatformException {
      if (!mounted) return;
      final message = source == ImageSource.camera
          ? 'Camera access is off. Enable it in Settings to take a profile photo.'
          : 'Photo access is off. Enable it in Settings to choose a profile photo.';
      showErrorToast(context, message);
    } on ApiException catch (error) {
      if (!mounted) return;
      showErrorToast(context, error.message);
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn’t update your profile photo. Please try again.',
      );
    }
  }

  Future<void> _removeProfilePhoto() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    try {
      final user = await _backendApiService.removeProfilePhoto(
        identityToken: token,
      );
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      await _refreshProfileSurfaces();

      if (mounted) {
        showInfoToast(context, 'Profile photo removed.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showErrorToast(context, error.message);
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn’t remove your profile photo. Please try again.',
      );
    }
  }

  Future<bool> _dismissProfilePhotoPrompt() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return false;

    try {
      final user = await _backendApiService.dismissProfilePhotoPrompt(
        identityToken: token,
      );
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      showErrorToast(
        context,
        'Couldn’t save that preference. Please try again.',
      );
      return false;
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileTab(
          authService: widget.authService,
          displayName: _displayName,
          stepGoal: _stepGoal,
          email: _email,
          onSettingsChanged: _syncSettingsState,
          onRefresh: _refreshProfileTab,
          backendApiService: _backendApiService,
          notificationService: widget.notificationService,
          stepData: _stepData,
          onAddProfilePhoto: _addOrChangeProfilePhoto,
          onRemoveProfilePhoto: _removeProfilePhoto,
          onOpenFriends: _openFriendsTab,
          incomingFriendRequests: _incomingFriendRequests,
        ),
      ),
    );
  }

  Future<void> _fetchLeaderboardHighlights() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) {
      if (mounted) {
        setState(() {
          _leaderboardHighlightsLoading = false;
          _leaderboardHighlightsState = Loadable.error(
            'Not signed in.',
            data: _leaderboardHighlights.isEmpty
                ? null
                : _leaderboardHighlights,
          );
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _leaderboardHighlightsLoading = true;
        _leaderboardHighlightsState = _leaderboardHighlights.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(_leaderboardHighlights);
      });
    }

    try {
      final data = await _backendApiService.fetchLeaderboardHighlights(
        identityToken: identityToken,
      );
      final cards = (data['cards'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .take(3)
          .toList(growable: false);

      if (mounted) {
        setState(() {
          _leaderboardHighlights = cards;
          _leaderboardHighlightsLoading = false;
          _leaderboardHighlightsState = Loadable.success(cards);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _leaderboardHighlightsLoading = false;
          _leaderboardHighlightsState = Loadable.error(
            e.toString(),
            data: _leaderboardHighlights.isEmpty
                ? null
                : _leaderboardHighlights,
          );
        });
      }
    }
  }

  Future<void> _refreshStepGoal() async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final user = await _backendApiService.fetchMe(
        identityToken: identityToken,
      );
      final goal = user['stepGoal'] as int?;
      final incoming = user['incomingFriendRequests'] as int? ?? 0;
      final displayName = user['displayName'] as String?;
      final email = user['email'] as String?;
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {
          _stepGoal = goal;
          _incomingFriendRequests = incoming;
          _displayName = displayName;
          _email = email;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshProfileSurfaces() async {
    await Future.wait([
      _refreshStepGoal(),
      _fetchFriendsSteps(),
      _fetchRaces(),
    ]);

    if (mounted) {
      setState(() {
        _leaderboardSelectionNonce += 1;
      });
    }
  }

  Future<void> _showStepGoalDialog() async {
    final controller = TextEditingController(text: _stepGoal?.toString() ?? '');

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SingleChildScrollView(
            child: TrailSign(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'STEP GOAL',
                    style: PixelText.title(size: 18, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'How many steps per day?',
                    style: PixelText.body(size: 14, color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: PixelText.number(
                      size: 24,
                      color: AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.parchmentLight,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.parchmentBorder,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.parchmentBorder,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.accent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Minimum: 5,000 steps',
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: 'CANCEL',
                          variant: PillButtonVariant.secondary,
                          fontSize: 13,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PillButton(
                          label: 'SAVE',
                          variant: PillButtonVariant.primary,
                          fontSize: 13,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          onPressed: () {
                            final value = int.tryParse(controller.text);
                            if (value != null &&
                                value >= BackendConfig.minStepGoal) {
                              Navigator.of(context).pop(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() => _stepGoal = result);
    await widget.authService.updateStepGoal(result);

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken != null && identityToken.isNotEmpty) {
        await _backendApiService.setStepGoal(
          identityToken: identityToken,
          stepGoal: result,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Couldn\u2019t save your step goal. Please try again.',
        );
      }
    }
  }

  void _syncSettingsState() {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: const ArcadePageBackground(showHeader: false)),

          if (_syncStale)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: SyncStaleChip(onTap: _refreshHomeTab),
                ),
              ),
            ),

          Positioned.fill(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentTab = index);
                if (index == 1) _fetchRaces();
              },
              children: [
                HomeTab(
                  incomingFriendRequests: _incomingFriendRequests,
                  stepData: _stepData,
                  isLoading: _isLoading,
                  error: _error,
                  stepGoal: _stepGoal,
                  backendApiService: _backendApiService,
                  healthAuthorized: _healthAuthorized,
                  notificationsState: _notificationsState,
                  displayName: _displayName,
                  authService: widget.authService,
                  onRefresh: _refreshHomeTab,
                  onEnableHealth: _enableHealthData,
                  onEnableNotifications: _enableNotifications,
                  onSetStepGoal: _showStepGoalDialog,
                  onDisplayNameChanged: _syncSettingsState,
                  friendsSteps: _friendsSteps,
                  friendsStepsState: _friendsStepsState,
                  equippedAccessories: _equippedAccessories,
                  shopCatalogState: _shopCatalogState,
                  leaderboardHighlights: _leaderboardHighlights,
                  leaderboardHighlightsState: _leaderboardHighlightsState,
                  leaderboardHighlightsLoading: _leaderboardHighlightsLoading,
                  onOpenFriendsTab: _openFriendsTab,
                  onOpenLeaderboardTab: _openLeaderboardTab,
                  onOpenLeaderboardHighlight: _openLeaderboardHighlight,
                  onOpenProfile: _openProfile,
                  onAddProfilePhoto: _addOrChangeProfilePhoto,
                  onDismissProfilePhotoPrompt: _dismissProfilePhotoPrompt,
                  raceCard: _raceCard,
                  onOpenRace: _openRaceFromCard,
                  onJoinRaceFromCard: _joinRaceFromCard,
                  onAcceptRaceInvite: _acceptRaceInviteFromCard,
                  onDeclineRaceInvite: _declineRaceInviteFromCard,
                  onChallengeFriendBack: _challengeFriendBack,
                ),
                RacesTab(
                  authService: widget.authService,
                  racesData: _racesData,
                  racesState: _racesState,
                  friendsSteps: _friendsSteps,
                  onRacesChanged: _fetchRaces,
                  onRefresh: _refreshRacesTab,
                  displayName: _displayName,
                  onOpenProfile: _openProfile,
                ),
                ShopTab(
                  authService: widget.authService,
                  backendApiService: _backendApiService,
                  onShopChanged: _applyShopCatalog,
                ),
                LeaderboardTab(
                  authService: widget.authService,
                  backendApiService: _backendApiService,
                  stepData: _stepData,
                  stepGoal: _stepGoal,
                  displayName: _displayName,
                  requestedType: _requestedLeaderboardType,
                  requestedPeriod: _requestedLeaderboardPeriod,
                  selectionNonce: _leaderboardSelectionNonce,
                  onOpenProfile: _openProfile,
                ),
              ],
            ),
          ),

          // Bottom tab bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WoodenTabBar(
              currentIndex: _currentTab,
              onTap: (index) {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              },
              items: [
                const WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                const WoodenTabItem(
                  icon: Icons.directions_run_rounded,
                  label: 'Races',
                ),
                const WoodenTabItem(
                  icon: Icons.storefront_rounded,
                  label: 'Shop',
                ),
                const WoodenTabItem(
                  icon: Icons.leaderboard_rounded,
                  label: 'Leaderboard',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
