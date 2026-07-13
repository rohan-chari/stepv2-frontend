import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../widgets/wooden_tab_bar.dart';
import '../screens/tabs/home_tab.dart';
import '../screens/tabs/races_tab.dart';
import '../screens/tabs/leaderboard_tab.dart';
import '../screens/tabs/profile_tab.dart';
import '../screens/tabs/friends_tab.dart';
import '../screens/race_detail_screen.dart';
import 'tutorial_preview_data.dart';
import 'tutorial_screen.dart' show TutorialMockPage;

/// Hosts the REAL tab screens behind the tutorial spotlight, fed by seeded
/// offline data. Each page is the actual production widget (HomeTab, RacesTab,
/// …) so the walkthrough shows exactly what the user will see — not a mock.
///
/// Spotlight anchors are passed down as optional `GlobalKey`s that the real
/// screens expose; the overlay measures them by [keys]. The bottom
/// [WoodenTabBar] is reproduced (and wrapped in [AbsorbPointer]) so the framing
/// matches the live app and the Ranked tab can be spotlighted.
class TutorialRealHost extends StatelessWidget {
  const TutorialRealHost({
    super.key,
    required this.page,
    required this.keys,
    required this.authService,
    required this.api,
  });

  final TutorialMockPage page;
  final Map<String, GlobalKey> keys;
  final TutorialPreviewAuthService authService;
  final TutorialPreviewBackendApiService api;

  int? get _tabIndex => switch (page) {
    TutorialMockPage.home => 0,
    TutorialMockPage.races => 1,
    TutorialMockPage.friends => 2,
    TutorialMockPage.leaderboard => 3,
    TutorialMockPage.profile => 4,
    // Race detail is a pushed screen in the real app — no bottom bar.
    TutorialMockPage.raceDetail => null,
  };

  @override
  Widget build(BuildContext context) {
    final tabIndex = _tabIndex;
    // Freeze entrance/ambient animations (StaggerIn, PulseGlow, ShineSweep,
    // hero drift) inside the tutorial: the spotlight measures its target rect
    // right after a page mounts, and a mid-bounce element measures misaligned.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: _buildHost(tabIndex),
    );
  }

  Widget _buildHost(int? tabIndex) {
    return Stack(
      children: [
        Positioned.fill(child: _buildPage()),
        if (tabIndex != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AbsorbPointer(
              child: WoodenTabBar(
                currentIndex: tabIndex,
                onTap: (_) {},
                // Index 2 = Friends; keyed so the tutorial can spotlight the
                // real tab. Mirrors MainShell's live tab set.
                itemKeys: [null, null, keys['nav.friends'], null, null],
                items: const [
                  WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                  WoodenTabItem(
                    icon: Icons.directions_run_rounded,
                    label: 'Races',
                  ),
                  WoodenTabItem(icon: Icons.people_rounded, label: 'Friends'),
                  WoodenTabItem(
                    icon: Icons.leaderboard_rounded,
                    label: 'Boards',
                  ),
                  WoodenTabItem(icon: Icons.person_rounded, label: 'Profile'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPage() {
    switch (page) {
      case TutorialMockPage.home:
        return HomeTab(
          stepData: tutorialPreviewStepData(),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Rohan',
          authService: authService,
          backendApiService: api,
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          equippedAccessories: tutorialPreviewAccessories,
          incomingFriendRequests: 2,
          raceCard: tutorialPreviewHomeRaceCard(),
          tutorialStepsKey: keys['home.steps'],
          tutorialMilestonesKey: keys['home.milestones'],
          tutorialShopKey: keys['home.shop'],
          tutorialFriendsKey: keys['home.friends'],
        );
      case TutorialMockPage.races:
        return RacesTab(
          authService: authService,
          racesState: Loadable.success(tutorialPreviewRacesData()),
          friendsSteps: const [],
          featuredRaces: tutorialPreviewFeaturedRaces(),
          onRacesChanged: () async {},
          displayName: 'Rohan',
          tutorialPotKey: keys['races.pot'],
          tutorialCardKey: keys['races.card'],
          tutorialBoxKey: keys['races.box'],
        );
      case TutorialMockPage.raceDetail:
        // The REAL race-detail screen, self-fed by the seeded preview API
        // (fetchRaceDetails / fetchRaceProgress / messages are all overridden).
        return RaceDetailScreen(
          authService: authService,
          raceId: tutorialPreviewRaceId,
          backendApiService: api,
          tutorialPowerupsKey: keys['raceDetail.powerups'],
        );
      case TutorialMockPage.profile:
        return ProfileTab(
          authService: authService,
          backendApiService: api,
          displayName: 'Rohan',
          email: null,
          onSettingsChanged: () {},
          showBackButton: false,
          tutorialInviteKey: keys['profile.invite'],
        );
      case TutorialMockPage.leaderboard:
        return LeaderboardTab(
          authService: authService,
          backendApiService: api,
          displayName: 'Rohan',
          tutorialMyRowKey: keys['leaderboard.rank'],
        );
      case TutorialMockPage.friends:
        return FriendsTab(
          authService: authService,
          onFriendsChanged: () {},
          backendApiService: api,
          displayName: 'Rohan',
          tutorialSearchKey: keys['friends.search'],
        );
    }
  }
}
