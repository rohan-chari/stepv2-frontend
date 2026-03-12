# Step Tracker

A minimal Flutter app that reads daily step count data from the user's device. Starting with iOS (Apple HealthKit), with plans to expand to Android (Health Connect) in the future.

## What This App Does

- Reads the user's daily step count from Apple HealthKit
- Displays steps in a clean, simple interface
- Requests health data permissions gracefully
- Serves as a foundation for more advanced health/fitness features down the road

## Directory Structure

```
step_tracker/
├── lib/
│   ├── main.dart                  # App entry point and MaterialApp config
│   ├── models/
│   │   └── step_data.dart         # Data model for step records
│   ├── services/
│   │   └── health_service.dart    # HealthKit integration via the health package
│   ├── screens/
│   │   └── home_screen.dart       # Main screen showing today's step count
│   └── widgets/
│       └── step_count_card.dart   # Reusable widget for displaying step data
├── ios/
│   └── Runner/
│       ├── Info.plist             # HealthKit usage descriptions
│       └── Runner.entitlements    # HealthKit entitlement
├── test/
│   └── widget_test.dart           # Widget tests
├── pubspec.yaml                   # Dependencies (includes health package)
└── README.md
```

## Key Dependencies

- [health](https://pub.dev/packages/health) — Cross-platform wrapper for Apple HealthKit and Google Health Connect

## Getting Started

1. Make sure Flutter is installed (`flutter doctor` to verify)
2. Clone this repo and run `flutter pub get`
3. Open `ios/Runner.xcworkspace` in Xcode and enable the **HealthKit** capability
4. Run the app with `flutter run`

## iOS Setup Notes

HealthKit requires two things to be configured manually in Xcode:

- **Entitlement**: Enable HealthKit under Signing & Capabilities
- **Info.plist**: Add `NSHealthShareUsageDescription` with a user-facing explanation of why the app needs access to health data

## Roadmap

- [x] Basic home screen with step count display
- [ ] HealthKit integration (read today's steps)
- [ ] Permission handling and error states
- [ ] Step history (daily/weekly view)
- [ ] Android support via Health Connect



flutter run --dart-define=BACKEND_BASE_URL=http://10.0.0.209:3000