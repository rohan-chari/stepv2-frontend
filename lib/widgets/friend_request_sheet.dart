import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import 'public_profile_sheet.dart';

/// Compatibility entry point for older callers. All profile and friendship
/// state now lives in [PublicProfilePanel]; this function intentionally opens
/// the dossier directly and does not create an intermediate menu.
Future<void> showFriendRequestSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
  required String userId,
  required String displayName,
  String? profilePhotoUrl,
  VoidCallback? onChanged,
}) {
  return showPublicProfileSheet(
    context: context,
    authService: authService,
    backendApiService: backendApiService,
    userId: userId,
    fallbackName: displayName,
    fallbackPhotoUrl: profilePhotoUrl,
    onChanged: onChanged,
  );
}
