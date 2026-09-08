package com.rohanchari.steptracker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings

internal class PlatformSettingsLauncher(
    private val packageName: String,
    private val sdk: Int,
    private val launch: (Intent) -> Unit,
) {
    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:$packageName"))

    fun openHealthSettings(): Boolean = open(listOf(
        Intent(if (sdk >= 34) "android.health.connect.action.HEALTH_HOME_SETTINGS"
               else "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"),
        appDetails(),
    ))

    fun openNotificationSettings(): Boolean = open(listOf(
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
        appDetails(),
    ))

    private fun open(intents: List<Intent>): Boolean {
        for (intent in intents) {
            try {
                launch(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the actual app-details screen when provider UI is absent.
            } catch (_: SecurityException) {
                // OEM/profile restrictions may make the preferred action unavailable.
            }
        }
        return false
    }
}
