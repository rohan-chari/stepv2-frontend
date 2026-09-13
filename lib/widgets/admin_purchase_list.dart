import 'dart:async';

import 'package:flutter/material.dart';

import '../models/admin_purchase.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import 'admin_metric_widgets.dart';

class AdminPurchaseList extends StatefulWidget {
  const AdminPurchaseList({super.key, required this.api, required this.auth});
  final BackendApiService api;
  final AuthService auth;
  @override
  State<AdminPurchaseList> createState() => AdminPurchaseListState();
}

class AdminPurchaseListState extends State<AdminPurchaseList> {
  String _kind = 'all';
  String? _cursor;
  final List<AdminPurchase> _items = [];
  bool _loading = true;
  String? _error;
  bool _malformedRows = false;
  bool _retryAppend = false;
  int _generation = 0;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    final kind = _kind;
    final cursor = reset ? null : _cursor;
    setState(() {
      _loading = true;
      _error = null;
      _retryAppend = !reset;
      if (reset) {
        _items.clear();
        _cursor = null;
        _malformedRows = false;
        _start = null;
        _end = null;
      }
    });
    try {
      final token = widget.auth.authToken;
      if (token == null || token.isEmpty) {
        throw const ApiException('Sign in again.', statusCode: 401);
      }
      final response = await widget.api.fetchAdminPurchases(
        identityToken: token,
        kind: kind,
        environment: 'production',
        limit: 20,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      final page = AdminPurchasePage.from(response);
      if (page == null) throw const FormatException('Missing purchase page');
      final known = _items.map((item) => item.id).toSet();
      setState(() {
        _items.addAll(page.items.where((item) => known.add(item.id)));
        // A malformed server must not send the client around an endless cursor loop.
        _cursor = page.nextCursor == cursor ? null : page.nextCursor;
        _malformedRows = _malformedRows || page.malformedRows;
        _start = page.start ?? _start;
        _end = page.end ?? _end;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = switch (error.statusCode) {
          401 => 'Your session has expired. Sign in again.',
          403 => 'Admin access is required.',
          404 => 'Purchase history is unavailable on this server.',
          _ => 'Couldn’t load purchase history.',
        },
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'Couldn’t load purchase history.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent purchases',
                  style: adminText(context, size: 17, strong: true),
                ),
              ),
              IconButton(
                tooltip: 'About recorded purchases',
                onPressed: () => adminDefinition(
                  context,
                  'Recorded purchases',
                  'Available recorded transactions · current usernames.\n\n'
                      'Last 30 days. Production billing records only; in-game transactions use their recorded funding. '
                      'Coin packs, subscriptions and permanent memberships are receipt activity, including trials, unpaid activity and refunds. '
                      'They are not financial totals. Cash amounts are shown only when recorded; today’s prices are never substituted. '
                      'Deleted in-game request history cannot be reconstructed. Credit-funded rerolls and recurring membership benefit grants are excluded.'
                      '${_start == null || _end == null ? '' : '\n\nWindow: ${adminTimestamp(_start ?? DateTime.now())} to ${adminTimestamp(_end ?? DateTime.now())}.'}',
                ),
                icon: const Icon(Icons.info_outline, size: 17),
              ),
            ],
          ),
          Text(
            'Last 30 days · Production billing records',
            style: adminText(context, size: 11, muted: true),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final filter in const [
                ('all', 'All'),
                ('coin_pack', 'Coin packs'),
                ('subscription', 'Subscriptions'),
                ('in_game', 'In-game purchases'),
              ])
                ChoiceChip(
                  label: Text(filter.$2, style: adminText(context, size: 12)),
                  selected: _kind == filter.$1,
                  showCheckmark: false,
                  selectedColor: AppColors.of(
                    context,
                  ).successText.withValues(alpha: .13),
                  onSelected: (_) {
                    if (_kind == filter.$1) return;
                    setState(() => _kind = filter.$1);
                    unawaited(refresh());
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in _items)
            _PurchaseRow(key: ValueKey(item.id), item: item),
          if (_malformedRows)
            Text(
              'Some records are unavailable because their data is incomplete.',
              style: adminText(context, size: 12, muted: true),
            ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.of(context).successText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Loading purchases…',
                      style: adminText(context, size: 12, muted: true),
                    ),
                  ),
                ],
              ),
            )
          else if (_error != null) ...[
            Text(
              _error ?? '',
              style: adminText(context, size: 12, muted: true),
            ),
            TextButton(
              onPressed: () => _load(reset: !_retryAppend),
              child: Text(
                'Retry purchases',
                style: adminText(context, size: 12, strong: true),
              ),
            ),
          ] else if (_items.isEmpty && !_malformedRows)
            Text(
              'No recorded purchases in this period.',
              style: adminText(context, size: 12, muted: true),
            ),
          if (!_loading && _error == null && _cursor != null)
            TextButton(
              onPressed: _load,
              child: Text(
                'Load more',
                style: adminText(context, size: 13, strong: true),
              ),
            ),
        ],
      ),
    ),
  );
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({super.key, required this.item});
  final AdminPurchase item;
  @override
  Widget build(BuildContext context) {
    final at = item.occurredAt;
    final refundedAt = item.refundedAt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.of(context).textMid.withValues(alpha: .16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.username,
            style: adminText(context, size: 14, strong: true),
          ),
          const SizedBox(height: 3),
          Text(item.product, style: adminText(context, size: 13)),
          const SizedBox(height: 6),
          Text(
            '${item.kind} · ${item.status} · ${item.funding}',
            style: adminText(context, size: 11, muted: true),
          ),
          Text(item.amount, style: adminText(context, size: 13, strong: true)),
          const SizedBox(height: 3),
          Text(
            at == null ? 'Date unavailable' : adminTimestamp(at),
            style: adminText(context, size: 11, muted: true),
          ),
          if (refundedAt != null)
            Text(
              'Refunded ${adminTimestamp(refundedAt)}',
              style: adminText(context, size: 11, muted: true),
            ),
        ],
      ),
    );
  }
}
