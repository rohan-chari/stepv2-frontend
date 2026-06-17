package com.rohanchari.steptracker

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (an androidx ComponentActivity), NOT FlutterActivity:
// the health plugin's Health Connect permission flow uses the AndroidX Activity
// Result API, which requires a ComponentActivity. With plain FlutterActivity the
// plugin throws ClassCastException at registration and Health Connect never wires
// up. See ANDROID.md §C.
class MainActivity : FlutterFragmentActivity()
