import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/content_board.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/game_button.dart';
import '../../widgets/game_icon_button.dart';
import '../../widgets/trail_sign.dart';
import '../challenge_detail_screen.dart';
import '../stake_picker_screen.dart';

class FriendsTab extends StatefulWidget {
  final AuthService authService;
  final List<Map<String, dynamic>> friendsSteps;
  final Map<String, dynamic>? currentChallenge;
  final VoidCallback onFriendsChanged;
  final VoidCallback onChallengeChanged;

  const FriendsTab({
    super.key,
    required this.authService,
    required this.friendsSteps,
    required this.currentChallenge,
    required this.onFriendsChanged,
    required this.onChallengeChanged,
  });

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final BackendApiService _backendApiService = BackendApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _showDropdown = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveChallenge =>
      widget.currentChallenge != null &&
      widget.currentChallenge!['challenge'] != null;

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
            context, 'Couldn\u2019t send friend request. Please try again.');
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
          context, 'Couldn\u2019t respond to request. Please try again.');
    }
  }

  Map<String, dynamic>? _getInstanceForFriend(String friendId) {
    final instances = widget.currentChallenge?['instances'] as List? ?? [];
    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final aId = inst['userAId'] as String? ??
          (inst['userA'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      final bId = inst['userBId'] as String? ??
          (inst['userB'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      if (aId == friendId || bId == friendId) return inst;
    }
    return null;
  }

  Future<void> _challengeFriend(String friendId, String friendName) async {
    // Pick a stake first (selection-only mode — no instanceId)
    final stakeId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          friendName: friendName,
        ),
      ),
    );

    if (stakeId == null || !mounted) return;

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      await _backendApiService.initiateChallenge(
        identityToken: identityToken,
        friendUserId: friendId,
        stakeId: stakeId,
      );

      if (mounted) widget.onChallengeChanged();
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    }
  }

  void _openChallengeDetail(Map<String, dynamic> instance) {
    final challenge =
        widget.currentChallenge?['challenge'] as Map<String, dynamic>? ?? {};
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) => ChallengeDetailScreen(
              authService: widget.authService,
              instance: instance,
              challenge: challenge,
            ),
          ),
        )
        .then((_) {
          if (mounted) widget.onChallengeChanged();
        });
  }

  Widget _buildChallengeAction(String friendId, String displayName) {
    final instance = _getInstanceForFriend(friendId);
    if (instance == null) {
      return GameButton(
        label: 'CHALLENGE',
        fontSize: 11,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        onPressed: () => _challengeFriend(friendId, displayName),
      );
    }

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';

    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      return GestureDetector(
        onTap: () => _openChallengeDetail(instance),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'ACTIVE',
            style: PixelText.button(size: 11, color: AppColors.accent),
          ),
        ),
      );
    }

    final proposedById = instance['proposedById'] as String? ?? '';
    final myUserId = widget.authService.userId ?? '';
    final isIncoming = proposedById.isNotEmpty && proposedById != myUserId;

    return GestureDetector(
      onTap: () => _openChallengeDetail(instance),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isIncoming
              ? const Color(0xFFE05040).withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isIncoming ? 'RESPOND' : 'WAITING',
          style: PixelText.button(
            size: 11,
            color: isIncoming
                ? const Color(0xFFE05040)
                : Colors.orange.shade800,
          ),
        ),
      ),
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
                        color:
                            AppColors.parchmentBorder.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _searchResults[i]['displayName'] as String? ?? '',
                    style:
                        PixelText.body(size: 15, color: AppColors.textDark),
                  ),
                ),
                GameButton(
                  label: 'ADD',
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
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: AppColors.parchmentBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title,
        style: PixelText.title(size: 13, color: AppColors.textMid),
      ),
    );
  }

  Widget _buildRequestRow({
    required String displayName,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border.all(color: AppColors.parchmentBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: PixelText.title(size: 14, color: AppColors.textDark),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildFriendRow(Map<String, dynamic> friend) {
    final friendId = friend['id'] as String? ?? '';
    final displayName = friend['displayName'] as String? ?? '???';

    // Find step data from shared friendsSteps
    int steps = 0;
    int? friendStepGoal;
    for (final fs in widget.friendsSteps) {
      if (fs['id'] == friendId) {
        steps = fs['steps'] as int? ?? 0;
        friendStepGoal = fs['stepGoal'] as int?;
        break;
      }
    }

    String progressText;
    if (friendStepGoal != null && friendStepGoal > 0) {
      final pct = ((steps / friendStepGoal) * 100).round();
      progressText = '$steps / $friendStepGoal  ($pct%)';
    } else {
      progressText = '$steps steps';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border.all(color: AppColors.parchmentBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  progressText,
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          if (_hasActiveChallenge && widget.authService.displayName != null)
            _buildChallengeAction(friendId, displayName),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;
    final searchBorderRadius = _showDropdown
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : BorderRadius.circular(8);

    return SafeArea(
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 120),
                child: Center(
                  child: Column(
                    children: [
                      TrailSign(
                        width: boardWidth,
                        child: Text(
                          'FRIENDS',
                          style: PixelText.title(
                            size: 24,
                            color: AppColors.textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ContentBoard(
                        width: boardWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Search + refresh
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                      if (_showDropdown) _buildSearchDropdown(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GameIconButton(
                                  icon: Icons.refresh,
                                  size: 50,
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          _loadFriends();
                                          widget.onFriendsChanged();
                                        },
                                ),
                              ],
                            ),

                            // Incoming requests
                            if (_incomingRequests.isNotEmpty) ...[
                              _buildSectionHeader('INCOMING REQUESTS'),
                              for (final req in _incomingRequests)
                                _buildRequestRow(
                                  displayName: (req['user']
                                              as Map<String, dynamic>?)?[
                                          'displayName'] as String? ??
                                      '',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GameButton(
                                        label: 'ACCEPT',
                                        fontSize: 11,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        onPressed: () => _respond(
                                          req['friendshipId'] as String,
                                          true,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GameButton(
                                        label: 'DECLINE',
                                        fontSize: 11,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        onPressed: () => _respond(
                                          req['friendshipId'] as String,
                                          false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],

                            // Outgoing requests
                            if (_outgoingRequests.isNotEmpty) ...[
                              _buildSectionHeader('SENT REQUESTS'),
                              for (final req in _outgoingRequests)
                                _buildRequestRow(
                                  displayName: (req['user']
                                              as Map<String, dynamic>?)?[
                                          'displayName'] as String? ??
                                      '',
                                  trailing: Text(
                                    'PENDING',
                                    style: PixelText.button(
                                      size: 11,
                                      color: AppColors.textAccent,
                                    ),
                                  ),
                                ),
                            ],

                            // Friends list with steps
                            _buildSectionHeader('YOUR FRIENDS'),
                            if (_friends.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'No friends yet \u2014 search above to add some!',
                                  style: PixelText.body(
                                    size: 14,
                                    color: AppColors.textMid,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            for (final friend in _friends)
                              _buildFriendRow(friend),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
