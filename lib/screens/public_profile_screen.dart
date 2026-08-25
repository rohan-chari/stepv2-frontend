import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../widgets/public_profile_sheet.dart';

class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    required this.userId,
    this.fallbackName,
    this.fallbackPhotoUrl,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final String userId;
  final String? fallbackName;
  final String? fallbackPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PublicProfilePanel(
        authService: authService,
        backendApiService: backendApiService,
        userId: userId,
        fallbackName: fallbackName ?? 'Runner',
        fallbackPhotoUrl: fallbackPhotoUrl,
      ),
    );
  }
}
