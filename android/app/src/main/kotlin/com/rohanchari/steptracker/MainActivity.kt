package com.rohanchari.steptracker

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (an androidx ComponentActivity), NOT FlutterActivity:
// the health plugin's Health Connect permission flow uses the AndroidX Activity
// Result API, which requires a ComponentActivity. With plain FlutterActivity the
// plugin throws ClassCastException at registration and Health Connect never wires
// up. See ANDROID.md §C.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Phase 2 — schedule the background step-sync worker. Idempotent (KEEP policy),
        // so re-scheduling on every launch is cheap. The worker itself no-ops until the
        // user is logged in and has granted Health Connect (incl. background) access.
        StepSyncWorker.schedulePeriodic(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phase 3 — let Dart (FCM STEP_SYNC_REQUEST handling) request an immediate
        // background step sync. Reliable while the app process is alive; a fully
        // detached FCM background isolate falls back to the periodic worker.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.steptracker/background_sync"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueueExpeditedSync" -> {
                    StepSyncWorker.enqueueExpedited(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
