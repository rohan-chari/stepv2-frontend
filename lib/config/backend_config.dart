enum BackendEnvironment { local, staging, production }

class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  static const int minStepGoal = 5000;

  static BackendEnvironment get environment {
    if (baseUrl.contains('staging')) return BackendEnvironment.staging;
    if (baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('localhost') ||
        baseUrl.startsWith('http://10.') ||
        baseUrl.startsWith('http://172.') ||
        baseUrl.startsWith('http://192.')) {
      return BackendEnvironment.local;
    }
    return BackendEnvironment.production;
  }

  static bool get isStaging => environment == BackendEnvironment.staging;
  static bool get isLocal => environment == BackendEnvironment.local;
}
