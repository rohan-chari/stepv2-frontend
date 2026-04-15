import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/game_container.dart';
import '../../widgets/info_board_card.dart';
import '../../widgets/pill_button.dart';

class FriendsTab extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onFriendsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final int? stepGoal;
  final String? displayName;
  final VoidCallback? onOpenProfile;

  const FriendsTab({
    super.key,
    required this.authService,
    required this.onFriendsChanged,
    this.onRefresh,
    this.backendApiService,
    this.stepData,
    this.stepGoal,
    this.displayName,
    this.onOpenProfile,
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
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final data = await _backendApiService.fetchFriends(
        identityToken: identityToken,
      );

      if (!mounted) return;

      final friends =
          (data['friends'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final pending = data['pending'] as Map<String, dynamic>? ?? {};
      final incoming =
          (pending['incoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final outgoing =
          (pending['outgoing'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _friends = friends;
        _incomingRequests = incoming;
        _outgoingRequests = outgoing;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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

      final results = await _backendApiService.searchUsers(
        identityToken: identityToken,
        query: query,
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
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayName,
              style: PixelText.title(size: 18, color: AppColors.textDark),
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
    final tabBarHeight = 77.5 + bottomInset;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final searchBorderRadius = _showDropdown
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : BorderRadius.circular(8);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(top: topInset + 12, bottom: tabBarHeight),
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppColors.accent,
          backgroundColor: AppColors.parchment,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildTopStatusBar(),
                      const SizedBox(height: 12),

                      _buildFriendsHeader(),
                      const SizedBox(height: 12),

                      // Search bar
                      Column(
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            textAlign: TextAlign.center,
                            style: PixelText.body(
                              size: 16,
                              color: AppColors.textDark,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.parchmentLight,
                              hintText: 'Search by display name',
                              hintStyle: PixelText.body(
                                size: 16,
                                color: AppColors.parchmentBorder,
                              ),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.parchmentBorder,
                                ),
                                borderRadius: searchBorderRadius,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.parchmentBorder,
                                ),
                                borderRadius: searchBorderRadius,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.accent,
                                  width: 2,
                                ),
                                borderRadius: searchBorderRadius,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                          if (_showDropdown) _buildSearchDropdown(),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Incoming requests
                      if (_incomingRequests.isNotEmpty) ...[
                        _buildSectionHeader('INCOMING REQUESTS'),
                        const SizedBox(height: 8),
                        _buildIncomingList(),
                        const SizedBox(height: 16),
                      ],

                      // Outgoing requests
                      if (_outgoingRequests.isNotEmpty) ...[
                        _buildSectionHeader('SENT REQUESTS'),
                        const SizedBox(height: 8),
                        _buildOutgoingList(),
                        const SizedBox(height: 16),
                      ],

                      // Friends list
                      if (_friends.isEmpty)
                        _buildFriendsEmptyState()
                      else
                        _buildFriendsList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsHeader() {
    final count = _friends.length;
    final hasFriends = count > 0;
    final subtitle = hasFriends
        ? (count == 1
              ? '1 adventurer in your crew'
              : '$count adventurers in your crew')
        : 'Search above to start your crew.';

    return InfoBoardCard(
      badgeLabel: 'YOUR FRIENDS',
      title: hasFriends ? 'Tap a friend for options.' : 'No friends yet',
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    );
  }

  Widget _buildFriendsEmptyState() {
    return GameContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Column(
        children: [
          Icon(
            Icons.group_add,
            size: 32,
            color: AppColors.textMid.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'No adventurers yet \u2014 invite some friends!',
            style: PixelText.body(
              color: AppColors.textMid,
            ).copyWith(shadows: _textShadows),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Column(
        children: [
          for (int i = 0; i < _friends.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.parchmentBorder.withValues(alpha: 0.45),
              ),
            _buildFriendRow(_friends[i], i),
          ],
        ],
      ),
    );
  }

  Widget _buildIncomingList() {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Column(
        children: [
          for (int i = 0; i < _incomingRequests.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.parchmentBorder.withValues(alpha: 0.45),
              ),
            _buildIncomingRow(_incomingRequests[i], i),
          ],
        ],
      ),
    );
  }

  Widget _buildOutgoingList() {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Column(
        children: [
          for (int i = 0; i < _outgoingRequests.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.parchmentBorder.withValues(alpha: 0.45),
              ),
            _buildOutgoingRow(_outgoingRequests[i], i),
          ],
        ],
      ),
    );
  }

  Widget _buildTopStatusBar() {
    final steps = widget.stepData?.steps ?? 0;
    final goal = widget.stepGoal ?? 0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.displayName != null)
                    Flexible(
                      child: Text(
                        widget.displayName!,
                        style: PixelText.title(
                          size: 26,
                          color: AppColors.textDark,
                        ).copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  CoinBalanceBadge(
                    coins: widget.authService.coins,
                    heldCoins: widget.authService.heldCoins,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (goalStr != null)
                Text(
                  '$stepsStr / $goalStr',
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                )
              else
                Text(
                  stepsStr,
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                ),
            ],
          ),
        ),
        ProfileAvatarButton(
          name: widget.displayName ?? 'You',
          imageUrl: widget.authService.profilePhotoUrl,
          onPressed: widget.onOpenProfile,
        ),
      ],
    );
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatCompact(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: PixelText.title(
        size: 18,
        color: AppColors.textMid,
      ).copyWith(shadows: _textShadows),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSearchDropdown() {
    final List<Widget> items;
    if (_isSearching) {
      items = [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: AppColors.accent,
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
            style: PixelText.body(size: 14, color: AppColors.textMid),
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
                        color: AppColors.parchmentBorder.withValues(alpha: 0.4),
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
                    _searchResults[i]['displayName'] as String? ?? '',
                    style: PixelText.body(size: 15, color: AppColors.textDark),
                  ),
                ),
                PillButton(
                  label: 'ADD',
                  variant: PillButtonVariant.primary,
                  fontSize: 11,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  onPressed: () =>
                      _sendRequest(_searchResults[i]['id'] as String),
                ),
              ],
            ),
          ),
      ];
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: AppColors.parchmentBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _buildFriendRow(Map<String, dynamic> friend, int index) {
    final displayName = friend['displayName'] as String? ?? '???';
    final profilePhotoUrl = friend['profilePhotoUrl'] as String?;
    final friendshipId = friend['friendshipId'] as String? ?? '';

    return Material(
      color: index.isOdd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
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
                  displayName,
                  style: PixelText.body(size: 16, color: AppColors.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.more_horiz, size: 22, color: AppColors.textMid),
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
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              style: PixelText.body(size: 16, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PillButton(
            label: 'ACCEPT',
            variant: PillButtonVariant.primary,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: () => _respond(friendshipId, true),
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

    return Container(
      color: index.isOdd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppAvatar(name: displayName, imageUrl: profilePhotoUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              style: PixelText.body(size: 16, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'PENDING',
            style: PixelText.title(size: 13, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}
