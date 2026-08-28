import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../widgets/arcade_fx.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/friends_summary_repository.dart';
import '../../styles.dart';
import '../../widgets/coach_tip.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../utils/at_name.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/public_profile_sheet.dart';
import '../referral_screen.dart';

enum _SearchResultState { addable, friends, pending }

class FriendsTab extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onFriendsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final String? displayName;
  final VoidCallback? onOpenProfile;
  final FriendsSummaryRepository? friendsRepository;
  final ValueChanged<Map<String, dynamic>>? onSnapshot;
  // Optional tutorial spotlight anchor for the search field. Null in the
  // shipped app (transparent KeyedSubtree); the tutorial passes a key so its
  // overlay can measure the real search box.
  final GlobalKey? tutorialSearchKey;

  // Optional tutorial spotlight anchor for the invite-friends button (moved
  // here from Profile). Null in the shipped app.
  final GlobalKey? tutorialInviteKey;

  const FriendsTab({
    super.key,
    required this.authService,
    required this.onFriendsChanged,
    this.onRefresh,
    this.backendApiService,
    this.stepData,
    this.displayName,
    this.onOpenProfile,
    this.friendsRepository,
    this.onSnapshot,
    this.tutorialSearchKey,
    this.tutorialInviteKey,
  });

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  late final BackendApiService _backendApiService;
  late final FriendsSummaryRepository _friendsRepository;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];
  List<Map<String, dynamic>> _searchResults = [];
  Loadable<Map<String, List<Map<String, dynamic>>>> _friendsState =
      const Loadable.initial();
  bool _isLoading = true;
  bool _isSearching = false;
  bool _showDropdown = false;
  bool _legacyRaceNameSearch = false;
  bool _dossierRefreshInFlight = false;
  Timer? _debounce;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _friendsRepository =
        widget.friendsRepository ??
        FriendsSummaryRepository(_backendApiService);
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final previous = <String, List<Map<String, dynamic>>>{
      'friends': _friends,
      'incoming': _incomingRequests,
      'outgoing': _outgoingRequests,
    };
    final hasPreviousData =
        _friends.isNotEmpty ||
        _incomingRequests.isNotEmpty ||
        _outgoingRequests.isNotEmpty;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _friendsState = hasPreviousData
            ? Loadable.refreshing(previous)
            : const Loadable.loading();
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _friendsState = Loadable.error(
              'Not signed in.',
              data: hasPreviousData ? previous : null,
            );
          });
        }
        return;
      }

      final data = await _friendsRepository.fetch(identityToken: identityToken);

      if (!mounted) return;

      // Copied (not sorted in place — the response list may be unmodifiable)
      // and ordered alphabetically regardless of backend version (older
      // backends return insertion order).
      final friends = _safeRows(data['friends'])
        ..sort(
          (a, b) =>
              (a['displayName'] is String ? a['displayName'] as String : '')
                  .toLowerCase()
                  .compareTo(
                    (b['displayName'] is String
                            ? b['displayName'] as String
                            : '')
                        .toLowerCase(),
                  ),
        );
      final pending = _safeMap(data['pending']);
      final incoming = _safeRows(pending['incoming']);
      final outgoing = _safeRows(pending['outgoing']);

      setState(() {
        _friends = friends;
        _incomingRequests = incoming;
        _outgoingRequests = outgoing;
        _friendsState = Loadable.success({
          'friends': friends,
          'incoming': incoming,
          'outgoing': outgoing,
        });
        _isLoading = false;
      });
      widget.onSnapshot?.call(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _friendsState = Loadable.error(
          'Couldn’t load friends. Please try again.',
          data: hasPreviousData ? previous : null,
        );
      });
      showErrorToast(context, 'Couldn\u2019t load friends. Please try again.');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _showDropdown = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showDropdown = true;
    });

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchUsers(query.trim());
    });
  }

  Future<void> _searchUsers(String query) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      // Stored names are bare; strip a leading '@' the user may have typed.
      final bareQuery = query.startsWith('@') ? query.substring(1) : query;

      final results = await _backendApiService.searchUsers(
        identityToken: identityToken,
        query: bareQuery,
      );

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _showDropdown = true;
      });
    } on LegacyFriendSearchRequired {
      if (!mounted) return;
      _searchController.clear();
      setState(() {
        _legacyRaceNameSearch = true;
        _searchResults = [];
        _isSearching = false;
        _showDropdown = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<void> _sendRequest(String addresseeId) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      await _backendApiService.sendFriendRequest(
        identityToken: identityToken,
        addresseeId: addresseeId,
      );

      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _showDropdown = false;
      });
      _searchController.clear();
      _friendsRepository.invalidate();
      await _loadFriends();
      widget.onFriendsChanged();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('already') || raw.contains('existing')) {
        showErrorToast(context, 'You already have a request with this user.');
      } else {
        showErrorToast(
          context,
          'Couldn\u2019t send friend request. Please try again.',
        );
      }
    }
  }

  Future<void> _respond(String friendshipId, bool accept) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      await _backendApiService.respondToFriendRequest(
        identityToken: identityToken,
        friendshipId: friendshipId,
        accept: accept,
      );

      if (!mounted) return;
      _friendsRepository.invalidate();
      await _loadFriends();
      widget.onFriendsChanged();
    } catch (e) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn\u2019t respond to request. Please try again.',
      );
    }
  }

  Future<void> _handleRefresh() async {
    _friendsRepository.invalidate();
    await _loadFriends();
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
  }

  void _openPublicProfile({
    required String? userId,
    required String fallbackName,
    String? fallbackPhotoUrl,
    String? fallbackRealName,
    required PublicProfileRelationship relationship,
    String? friendshipId,
  }) {
    final id = userId?.trim();
    if (id == null || id.isEmpty || id == widget.authService.userId) return;
    showPublicProfileSheet(
      context: context,
      authService: widget.authService,
      backendApiService: _backendApiService,
      userId: id,
      fallbackName: fallbackName,
      fallbackPhotoUrl: fallbackPhotoUrl,
      fallbackRealName: fallbackRealName,
      initialRelationship: relationship,
      friendshipId: friendshipId,
      onChanged: () {
        _friendsRepository.invalidate();
        if (!_dossierRefreshInFlight) {
          _dossierRefreshInFlight = true;
          unawaited(
            _loadFriends().whenComplete(() {
              _dossierRefreshInFlight = false;
            }),
          );
        }
        widget.onFriendsChanged();
      },
    );
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final canPop = Navigator.of(context).canPop();
    final tabBarHeight = canPop ? bottomInset : 77.5 + bottomInset;
    final state = _friendsState;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight),
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: AppRefreshIndicator(
                onRefresh: _handleRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildFriendsHeader(showBackButton: canPop),
                    ),
                    SliverToBoxAdapter(child: _buildBody(state: state)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsHeader({required bool showBackButton}) {
    final searchBorderRadius = _showDropdown
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : BorderRadius.circular(8);

    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.of(context).roofLight),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (showBackButton) ...[
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppColors.of(context).textLight,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'FRIENDS',
                      style: PixelText.title(
                        size: 30,
                        color: AppColors.of(context).textLight,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Friend search is no longer taught by the tutorial (two of its
              // ten steps were near-duplicates about exactly this); it is
              // taught here, once, the first time the tab is actually opened.
              // This column already supplies the tab's gutters, so the tip must
              // not add its own — otherwise the card sits inset from the search
              // field it is pointing at. The bottom margin is the real gap to
              // the field below (it used to be 4, so the two touched).
              CoachTipHost(
                tip: CoachTipId.friendsAdd,
                store: coachTipStore,
                enabled: widget.authService.onboardingV3Enabled,
                margin: const EdgeInsets.only(bottom: 12),
                child: const SizedBox.shrink(),
              ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Material(
                        key: widget.tutorialSearchKey,
                        color: Colors.transparent,
                        child: TextField(
                          key: const Key('friends-search-control'),
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: PixelText.body(
                            size: 16,
                            color: AppColors.of(context).textDark,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.of(context).parchmentLight,
                            hintText: _legacyRaceNameSearch
                                ? 'Search race names'
                                : 'Search friends',
                            hintStyle: PixelText.body(
                              size: 16,
                              color: AppColors.of(context).parchmentBorder,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: AppColors.of(context).textMid,
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.of(context).parchmentBorder,
                              ),
                              borderRadius: searchBorderRadius,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.of(context).parchmentBorder,
                              ),
                              borderRadius: searchBorderRadius,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.of(context).accent,
                                width: 2,
                              ),
                              borderRadius: searchBorderRadius,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildInviteButton(),
                  ],
                ),
              ),
              if (_showDropdown)
                Padding(
                  padding: const EdgeInsets.only(right: 68),
                  child: _buildSearchDropdown(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact invite action beside search. It keeps referral discovery in the
  /// header without making a second full-width banner compete with search.
  Widget _buildInviteButton() {
    final colors = AppColors.of(context);
    return KeyedSubtree(
      key: widget.tutorialInviteKey,
      child: PulseGlow(
        child: Semantics(
          button: true,
          label: 'Invite friends and earn coins',
          onTap: _openReferral,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openReferral,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                key: const Key('friends-invite-action'),
                constraints: const BoxConstraints(
                  minWidth: 58,
                  maxWidth: 58,
                  minHeight: 48,
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    color: colors.pillGold,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.pillGoldDark, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: colors.pillGoldShadow.withValues(alpha: 0.65),
                        offset: const Offset(3, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_add_rounded,
                        size: 18,
                        color: colors.textDark,
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'INVITE',
                              maxLines: 1,
                              style: PixelText.pill(
                                size: 12,
                                color: colors.textDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openReferral() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReferralScreen(
          authService: widget.authService,
          backendApiService: _backendApiService,
        ),
      ),
    );
  }

  Widget _buildBody({
    required Loadable<Map<String, List<Map<String, dynamic>>>> state,
  }) {
    if (state.shouldShowInitialLoading || (_isLoading && !state.hasData)) {
      return Container(
        margin: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: _friendsCardDecoration(),
        child: const ListSkeleton(itemCount: 4, showAvatar: true),
      );
    }

    if (state.isError && !state.hasData) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: LoadErrorPanel(
          title: 'Couldn’t load friends',
          message: state.error ?? 'Check your connection and try again.',
          onRetry: _loadFriends,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isRefreshing)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.of(context).accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_incomingRequests.isNotEmpty)
            StaggerIn(
              index: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader('INCOMING REQUESTS'),
                  _buildSectionCard(_buildIncomingList()),
                ],
              ),
            ),
          if (_outgoingRequests.isNotEmpty)
            StaggerIn(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader('SENT REQUESTS'),
                  _buildSectionCard(_buildOutgoingList()),
                ],
              ),
            ),
          StaggerIn(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader('FRIENDS'),
                if (_friends.isEmpty)
                  _buildFriendsEmptyState()
                else
                  _buildSectionCard(_buildFriendsList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parchment game-piece card — same language as the home/races tabs.
  BoxDecoration _friendsCardDecoration() {
    return BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    );
  }

  Widget _buildSectionCard(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _friendsCardDecoration(),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }

  Widget _buildFriendsEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: _friendsCardDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.group_add,
            size: 32,
            color: AppColors.of(context).textMid.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            'No friends yet. Search above to invite some.',
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textMid,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    return Column(
      children: [
        for (int i = 0; i < _friends.length; i++)
          _buildFriendRow(_friends[i], i),
      ],
    );
  }

  Widget _buildIncomingList() {
    return Column(
      children: [
        for (int i = 0; i < _incomingRequests.length; i++)
          _buildIncomingRow(_incomingRequests[i], i),
      ],
    );
  }

  Widget _buildOutgoingList() {
    return Column(
      children: [
        for (int i = 0; i < _outgoingRequests.length; i++)
          _buildOutgoingRow(_outgoingRequests[i], i),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.of(context).pillGold,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.of(context).pillGoldDark),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.title(
                  size: 16,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchDropdown() {
    final List<Widget> items;
    if (_isSearching) {
      items = [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppColors.of(context).accent,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ];
    } else if (_searchResults.isEmpty) {
      items = [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Text(
            'No users found',
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textMid,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    } else {
      items = [
        for (int i = 0; i < _searchResults.length; i++)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: i < _searchResults.length - 1
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.of(
                          context,
                        ).parchmentBorder.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: _profileIdentity(
                    userId: _extractUserId(_searchResults[i]),
                    displayName:
                        _safeString(_searchResults[i]['discoverableName']) ??
                        _safeString(_searchResults[i]['displayName']) ??
                        'Runner',
                    profilePhotoUrl: _safeString(
                      _searchResults[i]['profilePhotoUrl'],
                    ),
                    relationship: _searchRelationship(_searchResults[i]),
                    friendshipId: _searchFriendshipId(_searchResults[i]),
                    child: _searchIdentity(_searchResults[i]),
                  ),
                ),
                _buildSearchResultAction(_searchResults[i]),
              ],
            ),
          ),
      ];
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: AppColors.of(context).parchmentBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _buildSearchResultAction(Map<String, dynamic> user) {
    final state = _searchResultState(user);

    switch (state) {
      case _SearchResultState.friends:
        return const PillButton(
          label: 'FRIENDS',
          variant: PillButtonVariant.secondary,
          fontSize: 11,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onPressed: null,
        );
      case _SearchResultState.pending:
        return const PillButton(
          label: 'PENDING',
          variant: PillButtonVariant.secondary,
          fontSize: 11,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onPressed: null,
        );
      case _SearchResultState.addable:
        final id = _safeString(user['id']);
        return PillButton(
          label: 'ADD',
          variant: PillButtonVariant.primary,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onPressed: id == null ? null : () => _sendRequest(id),
        );
    }
  }

  String? _safeString(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  String? _pendingRealName(Map<String, dynamic> user) {
    String? part(Object? raw) {
      final value = _safeString(raw);
      if (value == null) return null;
      return value.length <= 80 ? value : value.substring(0, 80);
    }

    final parts = [
      part(user['firstName']),
      part(user['lastName']),
    ].whereType<String>().toList(growable: false);
    return parts.isEmpty ? null : parts.join(' ');
  }

  Map<String, dynamic> _safeMap(Object? raw) => raw is Map
      ? <String, dynamic>{
          for (final entry in raw.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : const {};

  List<Map<String, dynamic>> _safeRows(Object? raw) => raw is List
      ? raw.whereType<Map>().map(_safeMap).toList()
      : <Map<String, dynamic>>[];

  Widget _searchIdentity(Map<String, dynamic> row) {
    final realName = _safeString(row['discoverableName']);
    final handle = _safeString(row['displayName']);
    if (realName != null && handle != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            realName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PixelText.title(
              size: 14,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            atName(handle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
      );
    }
    return Text(
      realName ?? (handle == null ? 'Runner' : atName(handle)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PixelText.body(size: 15, color: AppColors.of(context).textDark),
    );
  }

  Widget _profileIdentity({
    required String? userId,
    required String displayName,
    required String? profilePhotoUrl,
    required PublicProfileRelationship relationship,
    required String? friendshipId,
    String? realName,
    Widget? child,
  }) {
    final identity = Row(
      children: [
        AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child:
              child ??
              (realName == null
                  ? Text(
                      atName(displayName),
                      style: PixelText.body(
                        size: 16,
                        color: AppColors.of(context).textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          realName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.title(
                            size: 14,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          atName(displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.body(
                            size: 12,
                            color: AppColors.of(context).textMid,
                          ),
                        ),
                      ],
                    )),
        ),
      ],
    );
    final validId =
        userId != null &&
        userId.isNotEmpty &&
        userId != widget.authService.userId;
    if (!validId) return identity;
    return Semantics(
      button: true,
      label: 'View profile for ${atName(displayName)}',
      child: InkWell(
        key: ValueKey('friends-profile-$userId'),
        onTap: () => _openPublicProfile(
          userId: userId,
          fallbackName: displayName,
          fallbackPhotoUrl: profilePhotoUrl,
          fallbackRealName: realName,
          relationship: relationship,
          friendshipId: friendshipId,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: identity,
        ),
      ),
    );
  }

  _SearchResultState _searchResultState(Map<String, dynamic> user) {
    return switch (_searchRelationship(user)) {
      PublicProfileRelationship.friends => _SearchResultState.friends,
      PublicProfileRelationship.incoming ||
      PublicProfileRelationship.outgoing => _SearchResultState.pending,
      _ => _SearchResultState.addable,
    };
  }

  PublicProfileRelationship _searchRelationship(Map<String, dynamic> user) {
    // Match the dossier precedence exactly: accepted supersedes either
    // pending direction, then outgoing supersedes incoming for a duplicate
    // legacy row. This keeps the search action and opened dossier consistent.
    if (_friends.any((friend) => _matchesSearchUser(friend, user))) {
      return PublicProfileRelationship.friends;
    }
    if (_outgoingRequests.any((request) => _matchesSearchUser(request, user))) {
      return PublicProfileRelationship.outgoing;
    }
    if (_incomingRequests.any((request) => _matchesSearchUser(request, user))) {
      return PublicProfileRelationship.incoming;
    }
    return PublicProfileRelationship.none;
  }

  String? _searchFriendshipId(Map<String, dynamic> user) {
    final relation = _searchRelationship(user);
    final rows = switch (relation) {
      PublicProfileRelationship.friends => _friends,
      PublicProfileRelationship.incoming => _incomingRequests,
      PublicProfileRelationship.outgoing => _outgoingRequests,
      _ => const <Map<String, dynamic>>[],
    };
    for (final row in rows) {
      if (_matchesSearchUser(row, user)) {
        final id = _safeString(row['friendshipId']);
        if (id != null) return id;
      }
    }
    return _safeString(user['friendshipId']);
  }

  bool _matchesSearchUser(
    Map<String, dynamic> candidate,
    Map<String, dynamic> user,
  ) {
    final userId = _extractUserId(user);
    final candidateId = _extractUserId(candidate);

    if (userId != null && candidateId != null) {
      return userId == candidateId;
    }

    if (userId != null || candidateId != null) {
      return false;
    }

    final displayName = _extractDisplayName(user);
    return displayName != null &&
        displayName.isNotEmpty &&
        displayName == _extractDisplayName(candidate);
  }

  String? _extractUserId(Map<String, dynamic> data) {
    for (final key in const [
      'id',
      'userId',
      'friendId',
      'requesterId',
      'addresseeId',
    ]) {
      final value = data[key];
      if (value is String && value.isNotEmpty) return value;
    }

    for (final key in const ['user', 'friend', 'requester', 'addressee']) {
      final value = data[key];
      if (value is Map<String, dynamic>) {
        final nestedId = _extractUserId(value);
        if (nestedId != null) return nestedId;
      }
    }

    return null;
  }

  String? _extractDisplayName(Map<String, dynamic> data) {
    final displayName = data['displayName'];
    if (displayName is String && displayName.isNotEmpty) {
      return displayName;
    }

    for (final key in const ['user', 'friend', 'requester', 'addressee']) {
      final value = data[key];
      if (value is Map<String, dynamic>) {
        final nestedName = _extractDisplayName(value);
        if (nestedName != null) return nestedName;
      }
    }

    return null;
  }

  Widget _buildFriendRow(Map<String, dynamic> friend, int index) {
    final displayName = _safeString(friend['displayName']) ?? 'Runner';
    final profilePhotoUrl = _safeString(friend['profilePhotoUrl']);
    final friendshipId = _safeString(friend['friendshipId']) ?? '';

    return Material(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _profileIdentity(
                userId: _extractUserId(friend),
                displayName: displayName,
                profilePhotoUrl: profilePhotoUrl,
                relationship: PublicProfileRelationship.friends,
                friendshipId: friendshipId,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: AppColors.of(context).textMid,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRow(Map<String, dynamic> req, int index) {
    final user = _safeMap(req['user']);
    final displayName = _safeString(user['displayName']) ?? 'Runner';
    final profilePhotoUrl = _safeString(user['profilePhotoUrl']);
    final friendshipId = _safeString(req['friendshipId']);
    final realName = _pendingRealName(user);

    return Container(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = _profileIdentity(
            userId: _extractUserId(req),
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
            relationship: PublicProfileRelationship.incoming,
            friendshipId: friendshipId,
            realName: realName,
          );
          final actions = MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseGlow(
                  child: PillButton(
                    label: 'ACCEPT',
                    variant: PillButtonVariant.primary,
                    fontSize: 11,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    onPressed: friendshipId == null
                        ? null
                        : () => _respond(friendshipId, true),
                  ),
                ),
                const SizedBox(width: 6),
                PillButton(
                  label: 'DECLINE',
                  variant: PillButtonVariant.accent,
                  fontSize: 11,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  onPressed: friendshipId == null
                      ? null
                      : () => _respond(friendshipId, false),
                ),
              ],
            ),
          );
          final reflow =
              constraints.maxWidth < 370 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (reflow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildOutgoingRow(Map<String, dynamic> req, int index) {
    final user = _safeMap(req['user']);
    final displayName = _safeString(user['displayName']) ?? 'Runner';
    final profilePhotoUrl = _safeString(user['profilePhotoUrl']);
    final friendshipId = _safeString(req['friendshipId']);

    return Container(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _profileIdentity(
              userId: _extractUserId(req),
              displayName: displayName,
              profilePhotoUrl: profilePhotoUrl,
              relationship: PublicProfileRelationship.outgoing,
              friendshipId: friendshipId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'PENDING',
              style: PixelText.title(
                size: 11,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
          PillButton(
            label: 'CANCEL',
            variant: PillButtonVariant.accent,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: friendshipId == null
                ? null
                : () => _showCancelOutgoingMenu(friendshipId, displayName),
          ),
        ],
      ),
    );
  }

  void _showCancelOutgoingMenu(String friendshipId, String displayName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cancel request to ${atName(displayName)}?',
              textAlign: TextAlign.center,
              style: PixelText.title(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'CANCEL REQUEST',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await _cancelOutgoingRequest(friendshipId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelOutgoingRequest(String friendshipId) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      await _backendApiService.removeFriend(
        identityToken: identityToken,
        friendshipId: friendshipId,
      );

      if (!mounted) return;
      _friendsRepository.invalidate();
      await _loadFriends();
      widget.onFriendsChanged();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(context, 'Couldn’t cancel request. Please try again.');
    }
  }
}
