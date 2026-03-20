import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/tab_layout.dart';

class FriendsTab extends StatefulWidget {
  final AuthService authService;
  final List<Map<String, dynamic>> friendsSteps;
  final Map<String, dynamic>? currentChallenge;
  final VoidCallback onFriendsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;

  const FriendsTab({
    super.key,
    required this.authService,
    required this.friendsSteps,
    required this.currentChallenge,
    required this.onFriendsChanged,
    this.onRefresh,
    this.backendApiService,
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


  /// Sort friends by goal progress percentage descending.
  List<Map<String, dynamic>> _sortedFriends() {
    final sorted = List<Map<String, dynamic>>.from(_friends);
    sorted.sort((a, b) {
      final aId = a['id'] as String? ?? '';
      final bId = b['id'] as String? ?? '';
      int aSteps = 0, bSteps = 0;
      int? aGoal, bGoal;
      for (final fs in widget.friendsSteps) {
        if (fs['id'] == aId) {
          aSteps = fs['steps'] as int? ?? 0;
          aGoal = fs['stepGoal'] as int?;
        }
        if (fs['id'] == bId) {
          bSteps = fs['steps'] as int? ?? 0;
          bGoal = fs['stepGoal'] as int?;
        }
      }
      final aPct = (aGoal != null && aGoal > 0)
          ? aSteps / aGoal
          : aSteps / 10000.0;
      final bPct = (bGoal != null && bGoal > 0)
          ? bSteps / bGoal
          : bSteps / 10000.0;
      return bPct.compareTo(aPct);
    });
    return sorted;
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title,
        style: PixelText.title(size: 13, color: AppColors.textMid),
      ),
    );
  }

  Widget _buildRequestRow({required String displayName, Widget? trailing}) {
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


  Widget _buildFriendRow(Map<String, dynamic> friend, int rank) {
    final friendId = friend['id'] as String? ?? '';

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

    final progress = (friendStepGoal != null && friendStepGoal > 0)
        ? (steps / friendStepGoal).clamp(0.0, 1.0)
        : 0.0;
    final pct = (progress * 100).round();
    final displayName = friend['displayName'] as String? ?? '???';

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
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: PixelText.title(size: 13, color: AppColors.textMid),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.pillGreen,
                                  AppColors.pillGreenDark,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      friendStepGoal != null && friendStepGoal > 0
                          ? '$pct%'
                          : '$steps',
                      style: PixelText.body(size: 12, color: AppColors.textMid),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final searchBorderRadius = _showDropdown
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : BorderRadius.circular(8);

    final sortedFriends = _sortedFriends();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: TabLayout(
        title: 'FRIENDS',
        onRefresh: _handleRefresh,
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
                          contentPadding: const EdgeInsets.symmetric(
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
                PillIconButton(
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
                  displayName:
                      (req['user'] as Map<String, dynamic>?)?['displayName']
                          as String? ??
                      '',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PillButton(
                        label: 'ACCEPT',
                        variant: PillButtonVariant.primary,
                        fontSize: 11,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        onPressed: () =>
                            _respond(req['friendshipId'] as String, true),
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
                        onPressed: () =>
                            _respond(req['friendshipId'] as String, false),
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
                  displayName:
                      (req['user'] as Map<String, dynamic>?)?['displayName']
                          as String? ??
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

            // Friends leaderboard
            _buildSectionHeader('LEADERBOARD'),
            if (sortedFriends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No friends yet \u2014 search above to add some!',
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
              ),
            for (int i = 0; i < sortedFriends.length; i++)
              _buildFriendRow(sortedFriends[i], i + 1),
          ],
        ),
      ),
    );
  }
}
