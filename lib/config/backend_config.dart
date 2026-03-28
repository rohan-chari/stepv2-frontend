class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  static const int minStepGoal = 5000;
}
