package com.rohanchari.steptracker

import android.os.Bundle
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
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

        // Referral attribution — return the Play Install Referrer string (e.g.
        // "referrer=BARA-7F3K&..."), which Dart parses for the invite code. Only
        // meaningful on a genuine Play install; returns null otherwise. Reads
        // once on first launch (Dart gates with a SharedPreferences flag).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.steptracker/referral"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallReferrer" -> getInstallReferrer(result)
                else -> result.notImplemented()
            }
        }

        // UMP's IAB TCF/Additional Consent/GPP values live in the platform
        // default SharedPreferences store. Return only standardized CMP keys;
        // Dart treats absent or malformed values as unknown.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.steptracker/ad_privacy_signals"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getIabSignals") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val prefs = applicationContext.getSharedPreferences(
                "${applicationContext.packageName}_preferences",
                MODE_PRIVATE,
            )
            val values = mutableMapOf<String, Any>()
            iabPrivacySignalKeys.forEach { key ->
                when (val value = prefs.all[key]) {
                    is String, is Int, is Long, is Boolean -> values[key] = value
                }
            }
            result.success(values)
        }
    }

    // Connects to the Play Install Referrer service, hands the raw referrer
    // string back to Dart, then disconnects. Never throws into Flutter — any
    // failure (service unavailable, sideload, etc.) resolves to null so
    // attribution silently falls back to the deep-link / manual-code paths.
    private fun getInstallReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(applicationContext).build()
        var settled = false
        fun finish(value: String?) {
            if (settled) return
            settled = true
            try { client.endConnection() } catch (_: Exception) {}
            runOnUiThread { result.success(value) }
        }
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            finish(client.installReferrer.installReferrer)
                        } catch (_: Exception) {
                            finish(null)
                        }
                    } else {
                        finish(null)
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    finish(null)
                }
            })
        } catch (_: Exception) {
            finish(null)
        }
    }

    companion object {
        private val iabPrivacySignalKeys: List<String> = buildList {
            addAll(
                listOf(
                    "IABTCF_gdprApplies",
                    "IABTCF_PurposeConsents",
                    "IABTCF_VendorConsents",
                    "IABTCF_AddtlConsent",
                    "IABGPP_GppSID",
                    "IABGPP_HDR_GppString",
                    "IABGPP_TCFEU2_gdprApplies",
                    "IABGPP_TCFEU2_PurposesConsent",
                    "IABUSPrivacy_String",
                    "IABGPP_USP1_OptOut",
                )
            )
            listOf(
                "USNAT", "USCA", "USVA", "USCO", "USUT", "USCT", "USFL",
                "USMT", "USOR", "USTX", "USDE", "USIA", "USNE", "USNH",
                "USNJ", "USTN", "USMN", "USMD", "USIN", "USKY", "USRI",
            ).forEach { prefix ->
                add("IABGPP_${prefix}_SaleOptOut")
                add("IABGPP_${prefix}_SharingOptOut")
                add("IABGPP_${prefix}_TargetedAdvertisingOptOut")
                add("IABGPP_${prefix}_Gpc")
            }
        }
    }
}
