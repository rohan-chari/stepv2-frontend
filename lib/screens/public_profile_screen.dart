import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/app_avatar.dart';
import '../widgets/home_course_track.dart' show CapybaraCustomizationPreview;

class PublicProfileScreen extends StatefulWidget {
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
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _error = 'Not signed in');
      return;
    }
    try {
      final data = await widget.backendApiService.fetchPublicProfile(
        identityToken: token,
        userId: widget.userId,
      );
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? <String, dynamic>{
          for (final entry in value.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : <String, dynamic>{};

  static List<Map<String, dynamic>> _accessories(Object? value) => value is List
      ? value.whereType<Map>().map(_map).toList(growable: false)
      : const <Map<String, dynamic>>[];

  static int _count(Map<String, dynamic> values, String key) {
    final value = values[key];
    return value is num && value.isFinite ? value.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final payload = _data;
    final user = _map(payload?['user']);
    final stats = _map(payload?['stats']);
    final podiums = _map(stats['racePodiums']);
    final name = user['displayName'] is String &&
            (user['displayName'] as String).isNotEmpty
        ? user['displayName'] as String
        : (widget.fallbackName ?? 'Runner');
    final photo = user['profilePhotoUrl'] is String
        ? user['profilePhotoUrl'] as String
        : widget.fallbackPhotoUrl;
    final average = stats['avgStepsPerDay'] is num
        ? (stats['avgStepsPerDay'] as num).round()
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _error != null
          ? const Center(child: Text('Profile unavailable'))
          : payload == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(child: AppAvatar(name: name, imageUrl: photo, size: 76)),
                    const SizedBox(height: 8),
                    Center(child: Text(name, style: PixelText.title(size: 22))),
                    const SizedBox(height: 18),
                    Center(
                      child: CapybaraCustomizationPreview(
                        accessories: _accessories(user['equippedAccessories']),
                        animal: user['equippedAnimal'] is String
                            ? user['equippedAnimal'] as String
                            : null,
                        size: 150,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('RACE TROPHIES', style: PixelText.title(size: 16)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('🥇 ${_count(podiums, 'first')}'),
                        Text('🥈 ${_count(podiums, 'second')}'),
                        Text('🥉 ${_count(podiums, 'third')}'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('AVERAGE STEPS', style: PixelText.title(size: 16)),
                    Text('$average per day', style: PixelText.body(size: 18)),
                  ],
                ),
    );
  }
}
