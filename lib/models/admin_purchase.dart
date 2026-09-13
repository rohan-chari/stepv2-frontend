import 'admin_metrics_dashboard.dart';

/// Read-only history: missing amounts stay unrecorded, never an inferred price.
class AdminPurchase {
  AdminPurchase._(this.data);
  final AdminMetricMap data;

  static AdminPurchase? from(Object? raw) {
    final data = AdminMetricMap.from(raw);
    if (data == null || data.text('id') == null) return null;
    return AdminPurchase._(data);
  }

  String get id => data.text('id') ?? '';
  String get username => data.text('userStatus') == 'deleted'
      ? 'Deleted account'
      : _text('username') ?? 'Username unavailable';
  String get product =>
      _text('productName') ?? _text('productId') ?? 'Unknown product';
  String? _text(String key) {
    final value = data.text(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  DateTime? get occurredAt =>
      DateTime.tryParse(data.text('occurredAt') ?? '')?.toLocal();
  DateTime? get refundedAt =>
      DateTime.tryParse(data.text('refundedAt') ?? '')?.toLocal();
  String get kind => switch (data.text('kind')) {
    'coin_pack' => 'Coin pack',
    'subscription' => 'Subscription / membership',
    'in_game' => 'In-game purchase',
    _ => 'Other activity',
  };
  String get status => switch (data.text('status')) {
    'purchased' => 'Purchased',
    'refunded' => 'Refunded',
    'pending' => 'Pending',
    'trial' => 'Trial',
    'unpaid' => 'Unpaid',
    'free' => 'Free',
    _ => 'Status unknown',
  };
  String get funding => switch (data.text('funding')) {
    'coins' => 'Coins',
    'coins_and_ads' => 'Coins + ads',
    'ads' => 'Ad-assisted',
    'cash' => 'Cash',
    'trial' => 'Trial',
    'free' => 'Free',
    _ => 'Funding unknown',
  };
  String get amount {
    final coins = data.integer('coinsSpent');
    if (coins != null && coins >= 0) return '$coins coins';
    final cash = data.decimal('cashAmount');
    final currency = _text('currency');
    if (cash != null &&
        cash >= 0 &&
        currency != null &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return '$currency ${cash.toStringAsFixed(2)}';
    }
    return 'Amount unrecorded';
  }
}

class AdminPurchasePage {
  AdminPurchasePage._({
    required this.items,
    required this.nextCursor,
    required this.malformedRows,
    this.start,
    this.end,
  });
  final List<AdminPurchase> items;
  final String? nextCursor;
  final bool malformedRows;
  final DateTime? start;
  final DateTime? end;

  static AdminPurchasePage? from(Object? raw) {
    final data = AdminMetricMap.from(raw);
    final rows = data?.raw('items');
    if (data == null || rows is! List) return null;
    final items = rows
        .map(AdminPurchase.from)
        .whereType<AdminPurchase>()
        .toList();
    final cursor = data.text('nextCursor');
    final window = data.map('window');
    return AdminPurchasePage._(
      items: items,
      nextCursor: cursor?.trim().isNotEmpty == true ? cursor : null,
      malformedRows: items.length != rows.length,
      start: DateTime.tryParse(window?.text('start') ?? '')?.toLocal(),
      end: DateTime.tryParse(window?.text('end') ?? '')?.toLocal(),
    );
  }
}
