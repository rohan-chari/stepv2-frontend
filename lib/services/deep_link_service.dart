import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// The app's custom URL scheme, registered in Info.plist (iOS) and
/// AndroidManifest (Android). Used by the landing page's "Open in app" button
/// (`bara://join/<token>`) as the reliable re-tap after install.
const String kAppUrlScheme = 'bara';

/// Captures race share links — both Universal/App Links
/// (`https://<host>/r/<token>`) and the custom-scheme deep link
/// (`bara://join/<token>`) — and turns them into a pending share token.
///
/// The token is persisted to [AuthService] immediately (so it survives a fresh
/// install's sign-in/onboarding gap) and surfaced via [pendingToken] so a live,
/// already-running app can react at once. The actual join happens at a single
/// drain point (MainShell), regardless of which path captured the token.
class DeepLinkService {
  DeepLinkService({required AuthService authService, AppLinks? appLinks})
    : _authService = authService,
      _appLinks = appLinks ?? AppLinks();

  final AuthService _authService;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  /// The most recently captured-but-undrained token. MainShell listens to this
  /// to join immediately when a link is tapped while the app is already open.
  final ValueNotifier<String?> pendingToken = ValueNotifier<String?>(null);

  /// Pure URI -> share-token extraction. Static + side-effect-free so it's
  /// trivially unit-testable. Returns null for any link that isn't a race
  /// share link, or whose token fails a basic sanity check.
  static String? parseShareToken(Uri uri) {
    // Token sanity guard: url-safe characters only, bounded length. The backend
    // is the source of truth (it 404s unknown tokens); this just stops us
    // persisting obvious garbage from a malformed link.
    bool isValid(String t) =>
        t.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(t);

    String? fromRPath(List<String> segments) {
      if (segments.length >= 2 && segments[0] == 'r' && isValid(segments[1])) {
        return segments[1];
      }
      return null;
    }

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      // Universal/App Link: https://<host>/r/<token>
      return fromRPath(uri.pathSegments);
    }

    if (uri.scheme == kAppUrlScheme) {
      // Custom scheme: bara://join/<token> or bara://race/<token>. The action
      // lands in `host`, the token in the first path segment.
      if ((uri.host == 'join' || uri.host == 'race') &&
          uri.pathSegments.isNotEmpty &&
          isValid(uri.pathSegments.first)) {
        return uri.pathSegments.first;
      }
      // Also tolerate bara:///r/<token>.
      return fromRPath(uri.pathSegments);
    }

    return null;
  }

  /// Begins listening for links: the cold-start link (if the app was launched
  /// by a link) plus the warm stream (links tapped while running). Safe to call
  /// once at startup. Never throws — a deep-link failure must not block launch.
  Future<void> initialize() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await handleLink(initial);
      }
    } catch (error) {
      debugPrint('DeepLinkService initial link error: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        // Fire-and-forget: the persistence is idempotent and order-independent.
        handleLink(uri);
      },
      onError: (Object error) {
        debugPrint('DeepLinkService stream error: $error');
      },
    );
  }

  /// Parses [uri], and if it carries a share token, persists it and pushes it
  /// onto [pendingToken]. Public so it can be unit-tested directly without the
  /// platform plugin.
  Future<void> handleLink(Uri uri) async {
    final token = parseShareToken(uri);
    if (token == null) return;
    await _authService.setPendingShareToken(token);
    pendingToken.value = token;
  }

  void dispose() {
    _subscription?.cancel();
    pendingToken.dispose();
  }
}
