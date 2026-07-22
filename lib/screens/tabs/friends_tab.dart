import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../widgets/arcade_fx.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../utils/at_name.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';

enum _SearchResultState { addable, friends, pending }

class FriendsTab extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onFriendsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final String? displayName;
  final VoidCallback? onOpenProfile;
  // Optional tutorial spotlight anchor for the search field. Null in the
  // shipped app (transparent KeyedSubtree); the tutorial passes a key so its
  // overlay can measure the real search box.
  final GlobalKey? tutorialSearchKey;

  const FriendsTab({
    super.key,
    required this.authService,
    required this.onFriendsChanged,
    this.onRefresh,
    this.backendApiService,
    this.stepData,
    this.displayName,
    this.onOpenProfile,
    this.tutorialSearchKey,
  });

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  late final BackendApiService _backendApiService;
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
  Timer? _debounce;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _backendApiService = widget.backendApiService ?? BackendApiService();
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

      final data = await _backendApiService.fetchFriends(
        identityToken: identityToken,
      );

      if (!mounted) return;

      // Copied (not sorted in place — the response list may be unmodifiable)
      // and ordered alphabetically regardless of backend version (older
      // backends return insertion order).
      final friends =
          List<Map<String, dynamic>>.of(
            (data['friends'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          )..sort(
            (a, b) => (a['displayName'] as String? ?? '')
                .toLowerCase()
                .compareTo((b['displayName'] as String? ?? '').toLowerCase()),
          );
      final pending = data['pending'] as Map<String, dynamic>? ?? {};
      final incoming =
          (pending['incoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final outgoing =
          (pending['outgoing'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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
    await _loadFriends();
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
  }

  Future<void> _removeFriend(String friendshipId) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      await _backendApiService.removeFriend(
        identityToken: identityToken,
        friendshipId: friendshipId,
      );

      if (!mounted) return;
      await _loadFriends();
      widget.onFriendsChanged();
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Couldn\u2019t remove friend. Please try again.');
    }
  }

  void _showFriendMenu(String friendshipId, String displayName) {
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
              atName(displayName),
              style: PixelText.title(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'REMOVE FRIEND',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await _removeFriend(friendshipId);
              },
            ),
          ],
        ),
      ),
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
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: AppColors.of(context).accent,
                backgroundColor: AppColors.of(context).parchment,
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
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofDark, width: 1),
        ),
      ),
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
              const SizedBox(height: 5),
              Text(
                'Find your crew and watch them climb the leaderboard.',
                style: PixelText.body(
                  size: 15,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 14),
              _FriendsHeaderMetrics(
                friendCount: _friends.length,
                incomingCount: _incomingRequests.length,
                outgoingCount: _outgoingRequests.length,
              ),
              const SizedBox(height: 14),
              Material(
                key: widget.tutorialSearchKey,
                color: Colors.transparent,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: PixelText.body(
                    size: 16,
                    color: AppColors.of(context).textDark,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.of(context).parchmentLight,
                    hintText: 'Search by display name',
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
              if (_showDropdown) _buildSearchDropdown(),
            ],
          ),
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
            'No friends yet \u2014 search above to invite some.',
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
          Text(
            title,
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textLight,
            ).copyWith(shadows: _textShadows),
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
                AppAvatar(
                  name: _searchResults[i]['displayName'] as String? ?? '',
                  imageUrl: _searchResults[i]['profilePhotoUrl'] as String?,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    atName(_searchResults[i]['displayName'] as String? ?? ''),
                    style: PixelText.body(
                      size: 15,
                      color: AppColors.of(context).textDark,
                    ),
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
        return PillButton(
          label: 'ADD',
          variant: PillButtonVariant.primary,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onPressed: () => _sendRequest(user['id'] as String),
        );
    }
  }

  _SearchResultState _searchResultState(Map<String, dynamic> user) {
    if (_friends.any((friend) => _matchesSearchUser(friend, user))) {
      return _SearchResultState.friends;
    }

    final hasPendingRequest =
        _incomingRequests.any((request) => _matchesSearchUser(request, user)) ||
        _outgoingRequests.any((request) => _matchesSearchUser(request, user));

    return hasPendingRequest
        ? _SearchResultState.pending
        : _SearchResultState.addable;
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
    final displayName = friend['displayName'] as String? ?? '???';
    final profilePhotoUrl = friend['profilePhotoUrl'] as String?;
    final friendshipId = friend['friendshipId'] as String? ?? '';

    return Material(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _showFriendMenu(friendshipId, displayName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  atName(displayName),
                  style: PixelText.body(
                    size: 16,
                    color: AppColors.of(context).textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.more_horiz,
                size: 22,
                color: AppColors.of(context).textMid,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingRow(Map<String, dynamic> req, int index) {
    final user = (req['user'] as Map<String, dynamic>?) ?? const {};
    final displayName = user['displayName'] as String? ?? '';
    final profilePhotoUrl = user['profilePhotoUrl'] as String?;
    final friendshipId = req['friendshipId'] as String;

    return Container(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              atName(displayName),
              style: PixelText.body(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PulseGlow(
            child: PillButton(
              label: 'ACCEPT',
              variant: PillButtonVariant.primary,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              onPressed: () => _respond(friendshipId, true),
            ),
          ),
          const SizedBox(width: 6),
          PillButton(
            label: 'DECLINE',
            variant: PillButtonVariant.accent,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: () => _respond(friendshipId, false),
          ),
        ],
      ),
    );
  }

  Widget _buildOutgoingRow(Map<String, dynamic> req, int index) {
    final user = (req['user'] as Map<String, dynamic>?) ?? const {};
    final displayName = user['displayName'] as String? ?? '';
    final profilePhotoUrl = user['profilePhotoUrl'] as String?;
    final friendshipId = req['friendshipId'] as String;

    return Container(
      color: index.isOdd
          ? AppColors.of(context).parchmentDark.withValues(alpha: 0.45)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              atName(displayName),
              style: PixelText.body(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
              overflow: TextOverflow.ellipsis,
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
            onPressed: () => _showCancelOutgoingMenu(friendshipId, displayName),
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
      await _loadFriends();
      widget.onFriendsChanged();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(context, 'Couldn’t cancel request. Please try again.');
    }
  }
}

class _FriendsHeaderMetrics extends StatelessWidget {
  const _FriendsHeaderMetrics({
    required this.friendCount,
    required this.incomingCount,
    required this.outgoingCount,
  });

  final int friendCount;
  final int incomingCount;
  final int outgoingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.of(context).textLight.withValues(alpha: 0.2),
          ),
          bottom: BorderSide(
            color: AppColors.of(context).textLight.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          _FriendMetricText(label: 'FRIENDS', count: friendCount),
          _FriendMetricDivider(),
          _FriendMetricText(label: 'INCOMING', count: incomingCount),
          _FriendMetricDivider(),
          _FriendMetricText(label: 'SENT', count: outgoingCount),
        ],
      ),
    );
  }
}

class _FriendMetricText extends StatelessWidget {
  const _FriendMetricText({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: PixelText.title(
              size: 18,
              color: AppColors.of(context).textLight,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 10,
                color: AppColors.of(context).textLight.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendMetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      color: AppColors.of(context).textLight.withValues(alpha: 0.22),
    );
  }
}
