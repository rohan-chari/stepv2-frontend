import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/admin_giveaway.dart';
import '../models/giveaway.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

class AdminGiveawayScreen extends StatefulWidget {
  const AdminGiveawayScreen({
    super.key,
    required this.authService,
    this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;

  @override
  State<AdminGiveawayScreen> createState() => _AdminGiveawayScreenState();
}

class _AdminGiveawayScreenState extends State<AdminGiveawayScreen> {
  late final BackendApiService _api =
      widget.backendApiService ?? BackendApiService();
  List<AdminGiveawayContest> _records = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _latestServerRequired = false;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final token = widget.authService.authToken;
    if (token == null) return;
    if (more) {
      if (_loadingMore || _nextCursor == null) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _latestServerRequired = false;
        _listError = null;
      });
    }
    try {
      final raw = await _api.fetchAdminGiveaways(
        identityToken: token,
        cursor: more ? _nextCursor : null,
      );
      final rawRecords = raw['records'];
      final rawCursor = raw['nextCursor'];
      if (rawRecords is! List || (rawCursor != null && rawCursor is! String)) {
        throw const FormatException();
      }
      final parsed = <AdminGiveawayContest>[];
      for (final item in rawRecords) {
        final contest = AdminGiveawayContest.tryParse(item);
        if (contest == null) throw const FormatException();
        parsed.add(contest);
      }
      if (!mounted) return;
      setState(() {
        _records = more ? [..._records, ...parsed] : parsed;
        _nextCursor = rawCursor as String?;
        _loading = false;
        _loadingMore = false;
        _listError = null;
      });
    } catch (error) {
      if (!mounted) return;
      final requiresLatest =
          error is FormatException ||
          (error is ApiException && error.statusCode == 404);
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_records.isEmpty) {
          _latestServerRequired = requiresLatest;
          _listError = requiresLatest
              ? null
              : 'Couldn’t load giveaway tools. Try again.';
        } else {
          _listError = 'Couldn’t refresh. Showing the last valid contest list.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('GIVEAWAY DASHBOARD'),
        backgroundColor: colors.parchment,
        foregroundColor: colors.textDark,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: GameBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _latestServerRequired
              ? _MessagePanel(
                  message: 'Giveaway tools require the latest server',
                  onRetry: _load,
                )
              : _records.isEmpty && _listError != null
              ? _MessagePanel(message: _listError!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
                  children: [
                    TrailSign(
                      width: MediaQuery.sizeOf(context).width - 32,
                      child: Text(
                        'REFERRAL CONTESTS',
                        textAlign: TextAlign.center,
                        style: PixelText.title(
                          size: 20,
                          color: colors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_listError != null) ...[
                      _board(
                        child: Text(
                          _listError!,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    PillButton(
                      label: 'CREATE CONTEST',
                      fullWidth: true,
                      onPressed: _openCreate,
                    ),
                    const SizedBox(height: 16),
                    if (_records.isEmpty)
                      _board(
                        child: Text(
                          'No contests yet.',
                          textAlign: TextAlign.center,
                          style: PixelText.body(
                            size: 14,
                            color: colors.textMid,
                          ),
                        ),
                      )
                    else
                      for (final contest in _records) ...[
                        _contestCard(contest),
                        const SizedBox(height: 12),
                      ],
                    if (_nextCursor != null)
                      PillButton(
                        label: _loadingMore ? 'LOADING…' : 'LOAD MORE',
                        onPressed: _loadingMore
                            ? null
                            : () => _load(more: true),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _contestCard(AdminGiveawayContest contest) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _AdminGiveawayDetailScreen(
            authService: widget.authService,
            api: _api,
            summary: contest,
          ),
        ),
      );
      if (mounted) await _load();
    },
    child: _board(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  contest.title,
                  style: PixelText.title(
                    size: 17,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              _status(contest.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${contest.startsAt.toLocal()} → ${contest.endsAt.toLocal()}',
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${contest.counts.entrants} entrants · ${contest.counts.reviewableFacts} reviews',
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textDark,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openCreate() async {
    String? idempotencyKey;
    String? requestFingerprint;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AdminDraftForm(
          onSave: (body) async {
            final token = widget.authService.authToken!;
            final fingerprint = jsonEncode(body);
            if (requestFingerprint != fingerprint) {
              requestFingerprint = fingerprint;
              idempotencyKey = _uuidV4();
            }
            late final Map<String, dynamic> raw;
            try {
              raw = await _api.createAdminGiveaway(
                identityToken: token,
                idempotencyKey: idempotencyKey!,
                body: body,
              );
            } on ApiException catch (error) {
              // A received 4xx is definitive. Unknown transport failures keep
              // the same key so a retry cannot create a second contest.
              final status = error.statusCode;
              if (status != null && status >= 400 && status < 500) {
                idempotencyKey = null;
                requestFingerprint = null;
              }
              rethrow;
            }
            final contest = AdminGiveawayContest.tryParse(raw['contest']);
            if (contest == null) throw const FormatException();
            return contest;
          },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _status(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.of(context).pillGold,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: PixelText.title(size: 10, color: AppColors.of(context).textDark),
    ),
  );

  Widget _board({required Widget child}) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).parchmentBorder,
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x66000000), offset: Offset(0, 4)),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _AdminGiveawayDetailScreen extends StatefulWidget {
  const _AdminGiveawayDetailScreen({
    required this.authService,
    required this.api,
    required this.summary,
  });
  final AuthService authService;
  final BackendApiService api;
  final AdminGiveawayContest summary;

  @override
  State<_AdminGiveawayDetailScreen> createState() =>
      _AdminGiveawayDetailScreenState();
}

class _AdminGiveawayDetailScreenState
    extends State<_AdminGiveawayDetailScreen> {
  late AdminGiveawayContest _contest = widget.summary;
  AdminGiveawayResult? _result;
  AdminGiveawayFulfillment? _fulfillment;
  List<AdminGiveawayCandidate> _candidates = const [];
  String? _candidateCursor;
  bool _loading = true;
  bool _busy = false;
  bool _loadingCandidates = false;
  bool _latestServerRequired = false;
  bool _conflict = false;
  String? _error;
  final _provider = TextEditingController(text: 'ACH');
  final _providerReference = TextEditingController();
  final _bannerCorrection = TextEditingController();
  final _bannerCorrectionReason = TextEditingController();
  final Map<String, String> _pendingMutationKeys = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _provider.dispose();
    _providerReference.dispose();
    _bannerCorrection.dispose();
    _bannerCorrectionReason.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _conflict = false;
      _latestServerRequired = false;
    });
    try {
      final raw = await widget.api.fetchAdminGiveawayDetail(
        identityToken: widget.authService.authToken!,
        contestId: _contest.id,
      );
      _consumeDetail(raw);
      if (!_contest.isDraft && _contest.status != 'ARCHIVED') {
        await _loadCandidates(reset: true);
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _latestServerRequired =
              error is FormatException ||
              (error is ApiException && error.statusCode == 404);
          _error = _latestServerRequired
              ? null
              : 'Couldn’t load contest details.';
        });
      }
    }
  }

  void _consumeDetail(Map<String, dynamic> raw) {
    final contest = AdminGiveawayContest.tryParse(raw['contest']);
    final result = AdminGiveawayResult.tryParse(raw['result']);
    AdminGiveawayFulfillment? fulfillment;
    if (raw['fulfillment'] != null) {
      fulfillment = AdminGiveawayFulfillment.tryParse(raw['fulfillment']);
    }
    if (contest == null ||
        result == null ||
        (raw['fulfillment'] != null && fulfillment == null) ||
        !_isAdminSnapshotCoherent(contest, result, fulfillment)) {
      throw const FormatException();
    }
    _contest = contest;
    _result = result;
    _fulfillment = fulfillment;
  }

  Future<void> _loadCandidates({bool reset = false}) async {
    if (_loadingCandidates || (!reset && _candidateCursor == null)) return;
    _loadingCandidates = true;
    try {
      final raw = await widget.api.fetchAdminGiveawayCandidates(
        identityToken: widget.authService.authToken!,
        contestId: _contest.id,
        cursor: reset ? null : _candidateCursor,
      );
      final records = raw['records'];
      final cursor = raw['nextCursor'];
      if (records is! List || (cursor != null && cursor is! String)) {
        throw const FormatException();
      }
      final parsed = <AdminGiveawayCandidate>[];
      for (final item in records) {
        final candidate = AdminGiveawayCandidate.tryParse(item);
        if (candidate == null) throw const FormatException();
        parsed.add(candidate);
      }
      if (!mounted) return;
      setState(() {
        _candidates = reset ? parsed : [..._candidates, ...parsed];
        _candidateCursor = cursor as String?;
        _loadingCandidates = false;
      });
    } catch (_) {
      _loadingCandidates = false;
      if (reset) rethrow;
      if (mounted) {
        setState(() {
          _error =
              'Couldn’t load more candidates. The existing list is unchanged.';
        });
      }
    }
  }

  Future<void> _mutation(
    String action,
    Map<String, dynamic> body, {
    Future<Map<String, dynamic>> Function(String idempotencyKey)? send,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _conflict = false;
    });
    final requestFingerprint = adminGiveawayRequestFingerprint(action, body);
    final idempotencyKey = _pendingMutationKeys.putIfAbsent(
      requestFingerprint,
      _uuidV4,
    );
    try {
      final raw = send == null
          ? await widget.api.mutateAdminGiveaway(
              identityToken: widget.authService.authToken!,
              contestId: _contest.id,
              action: action,
              idempotencyKey: idempotencyKey,
              body: body,
            )
          : await send(idempotencyKey);
      final contest = AdminGiveawayContest.tryParse(raw['contest']);
      if (contest == null) throw const FormatException();
      AdminGiveawayResult? nextResult = _result;
      AdminGiveawayFulfillment? nextFulfillment = _fulfillment;
      if (raw.containsKey('result')) {
        nextResult = AdminGiveawayResult.tryParse(raw['result']);
        if (nextResult == null) throw const FormatException();
      }
      if (raw.containsKey('fulfillment')) {
        nextFulfillment = AdminGiveawayFulfillment.tryParse(raw['fulfillment']);
        if (nextFulfillment == null) throw const FormatException();
      }
      if (nextResult == null ||
          !_isAdminSnapshotCoherent(contest, nextResult, nextFulfillment)) {
        throw const FormatException();
      }
      if (!mounted) return;
      _pendingMutationKeys.remove(requestFingerprint);
      setState(() {
        _contest = contest;
        _result = nextResult;
        _fulfillment = nextFulfillment;
        _busy = false;
      });
      if (action == 'reviews') await _loadCandidates(reset: true);
    } on ApiException catch (error) {
      final status = error.statusCode;
      if (status != null && status >= 400 && status < 500) {
        _pendingMutationKeys.remove(requestFingerprint);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _conflict = error.code == 'REVISION_CONFLICT';
        _error = _messageFor(error);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The server returned an invalid giveaway response.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_latestServerRequired) {
      return Scaffold(
        appBar: AppBar(title: Text(_contest.title)),
        body: _MessagePanel(
          message: 'Giveaway tools require the latest server',
          onRetry: _reload,
        ),
      );
    }
    if (_contest.isDraft) {
      return _AdminDraftForm(
        contest: _contest,
        onSave: (patch) async {
          try {
            final raw = await widget.api.updateAdminGiveaway(
              identityToken: widget.authService.authToken!,
              contestId: _contest.id,
              revision: _contest.revision,
              patch: patch,
            );
            final updated = AdminGiveawayContest.tryParse(raw['contest']);
            if (updated == null) throw const FormatException();
            if (mounted) setState(() => _contest = updated);
            return updated;
          } on ApiException catch (error) {
            if (error.code == 'REVISION_CONFLICT' && mounted) {
              setState(() => _conflict = true);
            }
            rethrow;
          }
        },
        onPublish: () => _confirm(
          title: 'Publish immutable contest?',
          detail:
              'Dates, territory, prize, scoring, eligibility, and rules become immutable.',
          confirmLabel: 'PUBLISH',
          action: () => _mutation('publish', {'revision': _contest.revision}),
        ),
        conflict: _conflict,
        serverError: _error,
        onReload: _reload,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_contest.title),
        backgroundColor: colors.parchment,
        foregroundColor: colors.textDark,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _panel('CONTEST', [
                  Text(
                    _contest.status,
                    style: PixelText.title(size: 17, color: colors.textDark),
                  ),
                  Text(
                    '${_contest.startsAt.toLocal()} → ${_contest.endsAt.toLocal()}',
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                  Text(
                    r'US$50 + 5,000 coins · 18+ · U.S. only',
                    style: PixelText.body(size: 13, color: colors.textDark),
                  ),
                  Text(
                    'Rules ${_contest.rules.version} · immutable',
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                  Text(
                    'Sponsor: ${_contest.sponsorLegalName} · ${_contest.sponsorMailingAddress}',
                    style: PixelText.body(size: 12, color: colors.textMid),
                  ),
                  for (final section in _contest.rules.sections) ...[
                    const SizedBox(height: 8),
                    Text(
                      section.heading,
                      style: PixelText.title(size: 13, color: colors.textDark),
                    ),
                    Text(
                      section.body,
                      style: PixelText.body(size: 12, color: colors.textDark),
                    ),
                  ],
                ]),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _panel('ACTION NEEDED', [
                    Text(_error!, style: TextStyle(color: colors.error)),
                    if (_conflict)
                      TextButton(
                        onPressed: _reload,
                        child: const Text('RELOAD LATEST'),
                      ),
                  ]),
                ],
                const SizedBox(height: 14),
                _candidatePanel(),
                const SizedBox(height: 14),
                _outcomePanel(),
                if (_result?.verifiedWinner != null) ...[
                  const SizedBox(height: 14),
                  _fulfillmentPanel(),
                ],
                if (_contest.isPublished) ...[
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'CANCEL CONTEST',
                    variant: PillButtonVariant.destructive,
                    fullWidth: true,
                    onPressed: _busy ? null : _cancelContest,
                  ),
                ],
                if (_contest.canArchive) ...[
                  const SizedBox(height: 14),
                  PillButton(
                    label: 'ARCHIVE',
                    variant: PillButtonVariant.destructive,
                    fullWidth: true,
                    onPressed: _busy
                        ? null
                        : () => _confirm(
                            title: 'Archive contest?',
                            detail:
                                'This removes it from current discovery but preserves its historical page.',
                            confirmLabel: 'ARCHIVE CONTEST',
                            action: () => _mutation('archive', {
                              'revision': _contest.revision,
                            }),
                          ),
                  ),
                ],
                if (_contest.isPublished) ...[
                  const SizedBox(height: 14),
                  _bannerCorrectionPanel(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _candidatePanel() => _panel('CANDIDATE REVIEW', [
    if (_candidates.isEmpty)
      const Text('No ranked candidates.')
    else
      for (final candidate in _candidates) ...[
        Text(
          '${candidate.provisionalRank == null ? '—' : '#${candidate.provisionalRank}'} ${candidate.displayName}',
          style: PixelText.title(
            size: 14,
            color: AppColors.of(context).textDark,
          ),
        ),
        Text(
          '${candidate.verifiedCount} verified · ${candidate.reviewableCount} reviewable · shared races ${candidate.sharedRaceCount}',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
        if (candidate.correlationFlags.isNotEmpty)
          Text(
            candidate.correlationFlags.join(', '),
            style: PixelText.body(size: 11, color: AppColors.of(context).error),
          ),
        for (final factId in candidate.flaggedReferralFactIds)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _review(factId, approve: true),
                child: const Text('APPROVE FACT'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _review(factId, approve: false),
                child: const Text('REJECT FACT'),
              ),
            ],
          ),
        const Divider(),
      ],
    if (_candidateCursor != null)
      TextButton(
        onPressed: _busy || _loadingCandidates ? null : _loadCandidates,
        child: Text(_loadingCandidates ? 'LOADING…' : 'LOAD MORE'),
      ),
  ]);

  bool get _bannerCorrectionValid {
    final message = _bannerCorrection.text.trim();
    final reason = _bannerCorrectionReason.text.trim();
    return message.isNotEmpty &&
        message.length <= 240 &&
        message != _contest.bannerMessage &&
        reason.length >= 10 &&
        reason.length <= 500;
  }

  Widget _bannerCorrectionPanel() {
    final colors = AppColors.of(context);
    return _panel('BANNER CORRECTION', [
      Text(
        'Current copy',
        style: PixelText.body(size: 11, color: colors.textMid),
      ),
      Text(
        _contest.bannerMessage,
        style: PixelText.body(size: 13, color: colors.textDark),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('giveaway-banner-correction'),
        controller: _bannerCorrection,
        enabled: !_busy,
        maxLength: 240,
        decoration: const InputDecoration(labelText: 'Corrected banner copy'),
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        key: const Key('giveaway-banner-correction-reason'),
        controller: _bannerCorrectionReason,
        enabled: !_busy,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Audit reason (required)',
          helperText: 'At least 10 characters. Never changes frozen terms.',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      PillButton(
        label: 'REVIEW CORRECTION',
        fullWidth: true,
        onPressed: _busy || !_bannerCorrectionValid
            ? null
            : _confirmBannerCorrection,
      ),
    ]);
  }

  Future<void> _confirmBannerCorrection() async {
    final message = _bannerCorrection.text.trim();
    final reason = _bannerCorrectionReason.text.trim();
    if (!_bannerCorrectionValid) return;
    await _confirm(
      title: 'Apply audited banner correction?',
      detail:
          'This correction and its reason are audited. Only banner copy changes; frozen prize, eligibility, dates, and rules remain unchanged.\n\nReason: $reason',
      confirmLabel: 'APPLY CORRECTION',
      action: () async {
        await _mutation(
          'banner-correction',
          {
            'revision': _contest.revision,
            'bannerMessage': message,
            'reason': reason,
          },
          send: (idempotencyKey) => widget.api.correctAdminGiveawayBanner(
            identityToken: widget.authService.authToken!,
            contestId: _contest.id,
            idempotencyKey: idempotencyKey,
            revision: _contest.revision,
            bannerMessage: message,
            reason: reason,
          ),
        );
        if (mounted && _contest.bannerMessage == message) {
          _bannerCorrection.clear();
          _bannerCorrectionReason.clear();
          setState(() {});
        }
      },
    );
  }

  Widget _outcomePanel() {
    final result = _result;
    return _panel('RESULTS & WINNER', [
      if (result?.noWinner == true)
        Text(
          'NO WINNER',
          style: PixelText.title(
            size: 16,
            color: AppColors.of(context).textDark,
          ),
        )
      else if (result?.verifiedWinner case final winner?)
        Text(
          'VERIFIED WINNER: ${winner.displayName.toUpperCase()}',
          style: PixelText.title(
            size: 15,
            color: AppColors.of(context).textDark,
          ),
        )
      else if (result?.potentialWinner case final winner?) ...[
        Text(
          'POTENTIAL WINNER: ${winner.displayName.toUpperCase()}',
          style: PixelText.title(
            size: 15,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 8),
        PillButton(
          label: 'VERIFY WINNER',
          fullWidth: true,
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Verify this winner?',
                  detail:
                      'This publishes the verified winner and makes the result final.',
                  confirmLabel: 'VERIFY',
                  action: () => _mutation('winner', {
                    'revision': _contest.revision,
                    'entrantId': winner.entrantId,
                    'decision': 'VERIFY',
                    'reasonCode': 'ELIGIBILITY_VERIFIED',
                  }),
                ),
        ),
        const SizedBox(height: 8),
        PillButton(
          label: 'REJECT WINNER',
          variant: PillButtonVariant.destructive,
          fullWidth: true,
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Reject this winner?',
                  detail:
                      'A reason is audited. Select the next candidate separately.',
                  confirmLabel: 'REJECT',
                  action: () => _mutation('winner', {
                    'revision': _contest.revision,
                    'entrantId': winner.entrantId,
                    'decision': 'REJECT',
                    'reasonCode': 'ELIGIBILITY_FAILED',
                  }),
                ),
        ),
      ] else if (_contest.status != 'VERIFYING')
        Text(
          'Results can be finalized after the contest window closes.',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        )
      else if (_contest.finalizedAt != null &&
          result != null &&
          result.rankedCount > 0)
        PillButton(
          label: 'SELECT NEXT',
          fullWidth: true,
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Select next candidate?',
                  detail: 'This advances to the next ranked eligible entrant.',
                  confirmLabel: 'SELECT NEXT',
                  action: () =>
                      _mutation('select-next', {'revision': _contest.revision}),
                ),
        )
      else
        PillButton(
          label: 'FINALIZE RESULTS',
          fullWidth: true,
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Finalize results?',
                  detail:
                      'All outcome-changing review facts must be resolved first.',
                  confirmLabel: 'FINALIZE',
                  action: () =>
                      _mutation('finalize', {'revision': _contest.revision}),
                ),
        ),
    ]);
  }

  Widget _fulfillmentPanel() {
    final status = _fulfillment?.status ?? 'UNCLAIMED';
    final next = switch (status) {
      'UNCLAIMED' => 'CLAIMED',
      'CLAIMED' => 'CASH_SENT',
      'CASH_SENT' => 'CASH_DELIVERED',
      _ => null,
    };
    final label = switch (next) {
      'CLAIMED' => 'MARK CLAIMED',
      'CASH_SENT' => 'MARK CASH SENT',
      'CASH_DELIVERED' => 'MARK CASH DELIVERED',
      _ => null,
    };
    return _panel('FULFILLMENT', [
      Text(
        status,
        style: PixelText.title(size: 15, color: AppColors.of(context).textDark),
      ),
      if (_fulfillment?.providerReferenceRedacted == true)
        Text(
          'Provider reference: REDACTED',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
      if (_fulfillment?.coinTransactionId != null)
        Text(
          'Coin transaction: ${_fulfillment!.coinTransactionId}',
          style: PixelText.body(size: 12, color: AppColors.of(context).textMid),
        ),
      if (label != null) ...[
        const SizedBox(height: 8),
        PillButton(
          label: label,
          fullWidth: true,
          onPressed: _busy ? null : () => _fulfillmentConfirm(next!),
        ),
      ],
      if (status == 'CASH_DELIVERED') ...[
        const SizedBox(height: 8),
        PillButton(
          label: 'AWARD 5,000 COINS',
          variant: PillButtonVariant.secondary,
          fullWidth: true,
          onPressed: _busy
              ? null
              : () => _confirm(
                  title: 'Award 5,000 coins?',
                  detail:
                      'The server mints this prize exactly once after verified cash delivery.',
                  confirmLabel: 'AWARD COINS',
                  action: () =>
                      _mutation('award-coins', {'revision': _contest.revision}),
                ),
        ),
      ],
    ]);
  }

  Future<void> _review(String factId, {required bool approve}) => _confirm(
    title: '${approve ? 'Approve' : 'Reject'} this referral fact?',
    detail: 'The decision, reason, actor, and time are permanently audited.',
    confirmLabel: approve ? 'APPROVE' : 'REJECT',
    action: () => _mutation('reviews', {
      'revision': _contest.revision,
      'referralFactId': factId,
      'decision': approve ? 'APPROVE' : 'REJECT',
      'reasonCode': approve ? 'LEGITIMATE' : 'FRAUD',
      'privateNote': '',
    }),
  );

  Future<void> _fulfillmentConfirm(String transition) async {
    final needsCash =
        transition == 'CASH_SENT' || transition == 'CASH_DELIVERED';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record $transition?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirm this only after the manual payout step actually occurred.',
            ),
            if (needsCash) ...[
              TextField(
                key: const Key('giveaway-provider'),
                controller: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
              ),
              TextField(
                key: const Key('giveaway-provider-reference'),
                controller: _providerReference,
                decoration: const InputDecoration(
                  labelText: 'Provider reference',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('BACK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final body = <String, dynamic>{
                'revision': _contest.revision,
                'transition': transition,
              };
              if (needsCash) {
                body['provider'] = _provider.text.trim();
                body['providerReference'] = _providerReference.text.trim();
              }
              await _mutation('fulfillment', body);
              // A payout reference is sensitive. Keep it only long enough to
              // submit this transition; the backend returns a redacted value.
              if (mounted) _providerReference.clear();
            },
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelContest() async {
    final reason = TextEditingController();
    final amendedVersion = TextEditingController();
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Cancel published contest?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cancellation is exceptional, public, and requires counsel-authorized amended rules.',
                    ),
                    TextField(
                      key: const Key('giveaway-cancel-public-reason'),
                      controller: reason,
                      decoration: const InputDecoration(
                        labelText: 'Public cancellation reason',
                      ),
                    ),
                    TextField(
                      key: const Key('giveaway-cancel-rules-version'),
                      controller: amendedVersion,
                      decoration: const InputDecoration(
                        labelText: 'Amended rules version',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('BACK'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('CANCEL CONTEST'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      await _mutation('cancel', {
        'revision': _contest.revision,
        'publicReason': reason.text.trim(),
        'amendedRulesVersion': amendedVersion.text.trim(),
      });
    } finally {
      reason.dispose();
      amendedVersion.dispose();
    }
  }

  Future<void> _confirm({
    required String title,
    required String detail,
    required String confirmLabel,
    required Future<void> Function() action,
  }) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(detail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('BACK'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) await action();
  }

  Widget _panel(String title, List<Widget> children) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).parchmentBorder,
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x66000000), offset: Offset(0, 4)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  static String _messageFor(ApiException error) => switch (error.code) {
    'REVISION_CONFLICT' =>
      'This contest changed on the server. Reload the latest revision.',
    'OUTCOME_REVIEW_REQUIRED' =>
      'Resolve every outcome-changing review before finalizing.',
    'QUALIFICATION_PROCESSING_PENDING' =>
      'Qualification processing is still finishing. Retry shortly.',
    'PUBLISH_VALIDATION_FAILED' =>
      'Publishing validation failed. Review every required legal field.',
    'INVALID_BANNER_CORRECTION' =>
      'Banner correction was rejected. Check the new copy and audit reason.',
    _ => error.message,
  };
}

class _AdminDraftForm extends StatefulWidget {
  const _AdminDraftForm({
    required this.onSave,
    this.contest,
    this.onPublish,
    this.conflict = false,
    this.serverError,
    this.onReload,
  });
  final AdminGiveawayContest? contest;
  final Future<AdminGiveawayContest> Function(Map<String, dynamic>) onSave;
  final Future<void> Function()? onPublish;
  final bool conflict;
  final String? serverError;
  final VoidCallback? onReload;

  @override
  State<_AdminDraftForm> createState() => _AdminDraftFormState();
}

class _AdminDraftFormState extends State<_AdminDraftForm> {
  late final _title = TextEditingController(
    text: widget.contest?.title ?? 'Bara Referral Contest',
  );
  late final _slug = TextEditingController(text: widget.contest?.slug ?? '');
  late final _zone = TextEditingController(
    text: widget.contest?.governingTimeZone ?? 'America/New_York',
  );
  late final _starts = TextEditingController(
    text: widget.contest?.startsAt.toIso8601String() ?? '',
  );
  late final _ends = TextEditingController(
    text: widget.contest?.endsAt.toIso8601String() ?? '',
  );
  late final _legalName = TextEditingController(
    text: widget.contest?.sponsorLegalName ?? '',
  );
  late final _address = TextEditingController(
    text: widget.contest?.sponsorMailingAddress ?? '',
  );
  late final _rulesVersion = TextEditingController(
    text: widget.contest?.rules.version ?? '',
  );
  late final List<_DraftRuleSection> _ruleSections =
      widget.contest?.rules.sections
          .map(
            (section) =>
                _DraftRuleSection(heading: section.heading, body: section.body),
          )
          .toList() ??
      [_DraftRuleSection(heading: 'Official Rules')];
  late final List<_DraftSocialLink> _socialLinks =
      widget.contest?.socialLinks
          .map(
            (link) => _DraftSocialLink(
              platform: link.platform,
              label: link.label,
              url: link.url.toString(),
            ),
          )
          .toList() ??
      [];
  late final _banner = TextEditingController(
    text:
        widget.contest?.bannerMessage ??
        r'Bara Referral Contest: win US$50 + 5,000 coins.',
  );
  late final _regions = TextEditingController(
    text:
        (widget.contest?.eligibleRegions ??
                (giveawayUsRegionsV1.toList()..sort()))
            .join(','),
  );
  bool _saving = false;
  bool _publishing = false;
  bool _dirty = false;
  String? _error;

  bool get _mutationLocked => _saving || _publishing;

  @override
  void dispose() {
    for (final c in [
      _title,
      _slug,
      _zone,
      _starts,
      _ends,
      _legalName,
      _address,
      _rulesVersion,
      _banner,
      _regions,
    ]) {
      c.dispose();
    }
    for (final section in _ruleSections) {
      section.dispose();
    }
    for (final link in _socialLinks) {
      link.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _body() => {
    'slug': _slug.text.trim(),
    'title': _title.text.trim(),
    'governingTimeZone': _zone.text.trim(),
    'startsAt': _starts.text.trim(),
    'endsAt': _ends.text.trim(),
    'cashCurrency': 'USD',
    'cashMinor': 5000,
    'coinPrize': 5000,
    'minimumAge': 18,
    'eligibleRegions': _regions.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(),
    'sponsor': {
      'legalName': _legalName.text.trim(),
      'mailingAddress': _address.text.trim(),
    },
    'rules': {
      'version': _rulesVersion.text.trim(),
      'sections': [
        for (final section in _ruleSections)
          {
            'heading': section.heading.text.trim(),
            'body': section.body.text.trim(),
          },
      ],
    },
    'socialLinks': [
      for (final link in _socialLinks)
        {
          'platform': link.platform.text.trim(),
          'label': link.label.text.trim(),
          'url': link.url.text.trim(),
        },
    ],
    'bannerMessage': _banner.text.trim(),
  };

  Future<void> _save() async {
    if (_mutationLocked) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_body());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      if (widget.contest == null) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.code == 'REVISION_CONFLICT'
              ? 'Revision conflict. Reload the latest contest.'
              : error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t save this draft.';
        });
      }
    }
  }

  Future<void> _publish() async {
    if (_mutationLocked || widget.onPublish == null) return;
    setState(() => _publishing = true);
    try {
      await widget.onPublish!();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.contest == null ? 'CREATE CONTEST' : 'EDIT DRAFT'),
      backgroundColor: AppColors.of(context).parchment,
      foregroundColor: AppColors.of(context).textDark,
    ),
    body: GameBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('Title', _title),
              _field('Slug', _slug),
              _field('Governing timezone', _zone),
              _field('Starts at (ISO-8601)', _starts),
              _field('Ends at (ISO-8601)', _ends),
              const ListTile(
                title: Text(r'US$50 (fixed)'),
                subtitle: Text('USD 5,000 minor units'),
              ),
              const ListTile(
                title: Text('5,000 coins (fixed)'),
                subtitle: Text(
                  'Prize values require a revised legal/economy spec to change',
                ),
              ),
              const ListTile(
                title: Text('18+ · United States only'),
                subtitle: Text('All 50 states and D.C.; no timezone gating'),
              ),
              _field('Eligible region codes', _regions, maxLines: 3),
              _field('Sponsor legal name', _legalName),
              _field('Sponsor mailing address', _address, maxLines: 2),
              _field('Rules version', _rulesVersion),
              for (var index = 0; index < _ruleSections.length; index++) ...[
                _editorHeader(
                  'RULE SECTION ${index + 1}',
                  canRemove: _ruleSections.length > 1,
                  onRemove: () {
                    final removed = _ruleSections.removeAt(index);
                    removed.dispose();
                    setState(() => _dirty = true);
                  },
                ),
                _field('Rules heading', _ruleSections[index].heading),
                _field('Rules body', _ruleSections[index].body, maxLines: 8),
              ],
              TextButton.icon(
                onPressed: _mutationLocked
                    ? null
                    : () => setState(() {
                        _ruleSections.add(_DraftRuleSection());
                        _dirty = true;
                      }),
                icon: const Icon(Icons.add),
                label: const Text('ADD RULE SECTION'),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _socialLinks.length; index++) ...[
                _editorHeader(
                  'SOCIAL LINK ${index + 1} (OPTIONAL, NON-SCORING)',
                  canRemove: true,
                  onRemove: () {
                    final removed = _socialLinks.removeAt(index);
                    removed.dispose();
                    setState(() => _dirty = true);
                  },
                ),
                _field('Platform', _socialLinks[index].platform),
                _field('Public label', _socialLinks[index].label),
                _field('HTTPS URL', _socialLinks[index].url),
              ],
              TextButton.icon(
                onPressed: _mutationLocked
                    ? null
                    : () => setState(() {
                        _socialLinks.add(_DraftSocialLink());
                        _dirty = true;
                      }),
                icon: const Icon(Icons.add),
                label: const Text('ADD OPTIONAL SOCIAL LINK'),
              ),
              _field('Home banner copy', _banner, maxLines: 3),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.of(context).error),
                ),
              if (widget.serverError != null)
                Text(
                  widget.serverError!,
                  style: TextStyle(color: AppColors.of(context).error),
                ),
              if (widget.conflict)
                TextButton(
                  onPressed: _mutationLocked ? null : widget.onReload,
                  child: const Text('RELOAD LATEST'),
                ),
              const SizedBox(height: 10),
              PillButton(
                label: _saving ? 'SAVING…' : 'SAVE DRAFT',
                fullWidth: true,
                onPressed: _mutationLocked ? null : _save,
              ),
              if (widget.onPublish != null) ...[
                const SizedBox(height: 10),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Save draft changes before publishing.',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  ),
                PillButton(
                  label: 'PUBLISH',
                  variant: PillButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: _mutationLocked || _dirty ? null : _publish,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_mutationLocked,
      maxLines: maxLines,
      onChanged: (_) => setState(() => _dirty = true),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.of(context).parchment,
      ),
    ),
  );

  Widget _editorHeader(
    String label, {
    required bool canRemove,
    required VoidCallback onRemove,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: PixelText.title(
            size: 12,
            color: AppColors.of(context).textDark,
          ),
        ),
      ),
      if (canRemove)
        IconButton(
          tooltip: 'Remove',
          onPressed: _mutationLocked ? null : onRemove,
          icon: const Icon(Icons.remove_circle_outline),
        ),
    ],
  );
}

class _DraftRuleSection {
  _DraftRuleSection({String heading = '', String body = ''})
    : heading = TextEditingController(text: heading),
      body = TextEditingController(text: body);

  final TextEditingController heading;
  final TextEditingController body;

  void dispose() {
    heading.dispose();
    body.dispose();
  }
}

class _DraftSocialLink {
  _DraftSocialLink({String platform = '', String label = '', String url = ''})
    : platform = TextEditingController(text: platform),
      label = TextEditingController(text: label),
      url = TextEditingController(text: url);

  final TextEditingController platform;
  final TextEditingController label;
  final TextEditingController url;

  void dispose() {
    platform.dispose();
    label.dispose();
    url.dispose();
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: PixelText.title(
              size: 17,
              color: AppColors.of(context).textLight,
            ),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'RETRY', onPressed: onRetry),
        ],
      ),
    ),
  );
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final value = bytes.map(hex).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}

bool _isAdminSnapshotCoherent(
  AdminGiveawayContest contest,
  AdminGiveawayResult result,
  AdminGiveawayFulfillment? fulfillment,
) {
  final potential = result.potentialWinner;
  final verified = result.verifiedWinner;
  final emptyResult =
      result.rankedCount == 0 &&
      !result.noWinner &&
      potential == null &&
      verified == null;
  if (fulfillment != null && verified == null) return false;

  return switch (contest.status) {
    'DRAFT' || 'SCHEDULED' || 'ACTIVE' => emptyResult && fulfillment == null,
    'VERIFYING' =>
      !result.noWinner &&
          verified == null &&
          fulfillment == null &&
          (contest.finalizedAt == null ? emptyResult : result.rankedCount > 0),
    'FINAL' =>
      potential == null &&
          (result.noWinner || verified != null) &&
          (result.noWinner ? fulfillment == null : true),
    'CANCELLED' => emptyResult && fulfillment == null,
    'ARCHIVED' =>
      contest.cancelledAt != null
          ? emptyResult && fulfillment == null
          : potential == null &&
                (result.noWinner || verified != null) &&
                (result.noWinner ? fulfillment == null : true),
    _ => false,
  };
}

String adminGiveawayRequestFingerprint(
  String action,
  Map<String, dynamic> body,
) => '$action:${sha256.convert(utf8.encode(jsonEncode(body)))}';
