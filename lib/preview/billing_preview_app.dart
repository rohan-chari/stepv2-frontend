import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/case_opening_screen.dart';
import '../screens/multi_case_opening_screen.dart';
import '../screens/race_detail_screen.dart';
import '../screens/tabs/profile_tab.dart';
import '../screens/tabs/shop_tab.dart';
import '../services/ad_service.dart';
import '../services/activation_analytics_service.dart';
import '../styles.dart';
import '../widgets/billing_scope.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/reroll_payment_sheet.dart';
import 'preview_billing_api.dart';
import 'preview_billing_controller.dart';

/// No SDK, network requests, or native ads in this standalone example app.
class PreviewUnsupportedAds implements ExtraSpinAdController {
  @override
  bool get isSupported => false;
  @override
  bool get isReady => false;
  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {}
  @override
  Future<bool> showAndAwaitReward() async => false;
  @override
  void dispose() {}
}

class _PreviewAnalytics extends ActivationAnalyticsService {
  _PreviewAnalytics(PreviewBillingApi api) : super(backendApiService: api);
  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async {}
  @override
  Future<void> flush(String? authToken, {String? userId}) async {}
}

class BillingPreviewApp extends StatefulWidget {
  const BillingPreviewApp({super.key, this.controller});
  final PreviewBillingController? controller;
  @override
  State<BillingPreviewApp> createState() => _BillingPreviewAppState();
}

class _BillingPreviewAppState extends State<BillingPreviewApp> {
  late final PreviewBillingController controller =
      widget.controller ?? PreviewBillingController();
  late final PreviewBillingApi api = PreviewBillingApi(controller);
  bool night = false;
  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BillingScope(
    controller: controller,
    child: MaterialApp(
      title: 'Bara billing preview',
      debugShowCheckedModeBanner: false,
      theme: AppThemeData.light(),
      darkTheme: AppThemeData.night(),
      themeMode: night ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          color: AppColors.of(context).roofDark,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.of(context).pillGold,
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 12,
                  ),
                  child: Text(
                    'PREVIEW · NO REAL PAYMENTS',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 12,
                      color: const Color(0xFF213128),
                    ),
                  ),
                ),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
      home: _PreviewHome(
        controller: controller,
        api: api,
        onTheme: () => setState(() => night = !night),
      ),
    ),
  );
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome({
    required this.controller,
    required this.api,
    required this.onTheme,
  });
  final PreviewBillingController controller;
  final PreviewBillingApi api;
  final VoidCallback onTheme;
  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  int page = 0;
  int generation = 0;
  final ads = PreviewUnsupportedAds();

  void _controls() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('PREVIEW CONTROLS', style: PixelText.title(size: 24)),
              const Text(
                'Sample account only. No real money, ads, or account changes.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scenario in PreviewBillingScenario.values)
                    ActionChip(
                      label: Text(
                        scenario == PreviewBillingScenario.permanentWithMonthly
                            ? 'PERMANENT + MONTHLY'
                            : scenario == PreviewBillingScenario.annual
                            ? 'LEGACY ANNUAL'
                            : scenario.name.toUpperCase(),
                      ),
                      onPressed: () {
                        widget.api.resetShopState();
                        widget.controller.setScenario(scenario);
                        setState(() => generation++);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  widget.controller.simulateNextFailure();
                  Navigator.pop(context);
                },
                child: const Text('Fail next purchase'),
              ),
              TextButton(
                onPressed: () {
                  widget.controller.simulateNextPending();
                  Navigator.pop(context);
                },
                child: const Text('Make next purchase pending'),
              ),
              TextButton(
                onPressed: () {
                  widget.controller.finishPending();
                  Navigator.pop(context);
                },
                child: const Text('Complete pending purchase'),
              ),
              TextButton(
                onPressed: () {
                  widget.onTheme();
                  Navigator.pop(context);
                },
                child: const Text('Switch day / night'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _openShop(int entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopTab(
          authService: widget.controller.auth,
          backendApiService: widget.api,
          initialFocus: entry == 1
              ? ShopFocus.coins
              : entry == 2
              ? ShopFocus.membership
              : ShopFocus.featured,
          adControllerBuilder: () => PreviewUnsupportedAds(),
          getCoinsAdController: ads,
        ),
      ),
    );
  }

  Widget _page() => switch (page) {
    0 || 1 || 2 => Center(
      child: PillButton(
        label: 'OPEN SHOP',
        icon: Icons.storefront_rounded,
        onPressed: () => _openShop(page),
      ),
    ),
    3 => ProfileTab(
      authService: widget.controller.auth,
      displayName: 'Rohan',
      onSettingsChanged: () {},
      backendApiService: widget.api,
      showBackButton: false,
    ),
    _ => _BoxExamples(controller: widget.controller, api: widget.api),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).roofDark,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Material(
            color: AppColors.of(context).pillGold,
            child: InkWell(
              onTap: _controls,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.science_outlined,
                      size: 18,
                      color: Color(0xFF213128),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SAMPLE ACCOUNT · CONTROLS',
                        style: PixelText.body(
                          size: 13,
                          color: const Color(0xFF213128),
                        ),
                      ),
                    ),
                    const Icon(Icons.tune, size: 18, color: Color(0xFF213128)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('$page-$generation'),
              child: _page(),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (value) {
        setState(() => page = value);
        if (value < 3) _openShop(value);
      },
      destinations: const [
        NavigationDestination(
          key: Key('preview-nav-shop'),
          icon: Icon(Icons.storefront),
          label: 'Shop',
        ),
        NavigationDestination(
          key: Key('preview-nav-coins'),
          icon: Icon(Icons.toll),
          label: 'Coins',
        ),
        NavigationDestination(
          key: Key('preview-nav-plus'),
          icon: Icon(Icons.stars_rounded),
          label: 'Bara+',
        ),
        NavigationDestination(
          key: Key('preview-nav-profile'),
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
        NavigationDestination(
          key: Key('preview-nav-boxes'),
          icon: Icon(Icons.inventory_2_outlined),
          label: 'Boxes',
        ),
      ],
    ),
  );
}

class _BoxExamples extends StatelessWidget {
  const _BoxExamples({required this.controller, required this.api});
  final PreviewBillingController controller;
  final PreviewBillingApi api;

  Future<List<Map<String, dynamic>>?> _reroll(
    BuildContext context,
    List<String> ids,
  ) async {
    final funding = await showRerollPaymentSheet(
      context,
      controller: controller,
      batch: ids.length > 1,
    );
    if (funding == null || !context.mounted) return null;
    final result = await controller.reroll(
      raceId: 'billing-preview-race',
      ids: ids,
      funding: funding,
    );
    if (!context.mounted) return null;
    if (!result.success) {
      showErrorToast(context, result.message);
      return null;
    }
    return result.rows;
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'A SECOND CHANCE',
        style: PixelText.title(size: 30, color: Colors.white),
      ),
      const SizedBox(height: 12),
      Text(
        'Try a single box, Reroll All, or a powerup in your stash. Each action costs one credit or 50 coins.',
        style: PixelText.body(size: 17, color: Colors.white),
      ),
      const SizedBox(height: 12),
      Text(
        'These sample results illustrate the screens; they do not simulate drop odds.',
        style: PixelText.body(size: 14, color: Colors.white70),
      ),
      const SizedBox(height: 24),
      PillButton(
        label: 'OPEN ONE BOX',
        onPressed: () {
          final id = controller.createBoxes(1).single;
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (routeContext) => CaseOpeningScreen(
                openMysteryBox: () async =>
                    Map<String, dynamic>.from(controller.raceItems[id] ?? {}),
                rerollLabel: 'REROLL',
                rerollIcon: Icons.casino_outlined,
                onReroll: (id) async =>
                    (await _reroll(routeContext, [id]))?.firstOrNull,
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      PillButton(
        label: 'OPEN THREE BOXES',
        onPressed: () {
          final ids = controller.createBoxes(3);
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (routeContext) => MultiCaseOpeningScreen(
                boxCount: 3,
                openAll: () async => ids
                    .map(
                      (id) => Map<String, dynamic>.from(
                        controller.raceItems[id] ?? {},
                      ),
                    )
                    .toList(),
                rerollLabel: 'REROLL ALL',
                rerollIcon: Icons.casino_outlined,
                onRerollAll: (ids) => _reroll(routeContext, ids),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      PillButton(
        label: 'VIEW RACE STASH',
        onPressed: () {
          api.seedRaceInventory();
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RaceDetailScreen(
                authService: controller.auth,
                raceId: 'billing-preview-race',
                backendApiService: api,
                boxRerollAdController: PreviewUnsupportedAds(),
                activationAnalyticsService: _PreviewAnalytics(api),
              ),
            ),
          );
        },
      ),
    ],
  );
}
