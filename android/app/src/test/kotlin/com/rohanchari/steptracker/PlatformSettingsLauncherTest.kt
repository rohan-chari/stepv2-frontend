package com.rohanchari.steptracker

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class PlatformSettingsLauncherTest {
    @Test fun `health uses native action and app details fallback`() {
        val seen = mutableListOf<Intent>()
        val launcher = PlatformSettingsLauncher("com.example.staging", 34) {
            seen.add(it)
            if (seen.size == 1) throw ActivityNotFoundException()
        }
        assertTrue(launcher.openHealthSettings())
        assertEquals("android.health.connect.action.HEALTH_HOME_SETTINGS", seen[0].action)
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, seen[1].action)
        assertEquals("package:com.example.staging", seen[1].data.toString())
    }
    @Test fun `notifications target actual flavor and unavailable settings return false`() {
        val seen = mutableListOf<Intent>()
        val launcher = PlatformSettingsLauncher("com.example.staging", 33) {
            seen.add(it); throw ActivityNotFoundException()
        }
        assertFalse(launcher.openNotificationSettings())
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, seen[0].action)
        assertEquals("com.example.staging", seen[0].getStringExtra(Settings.EXTRA_APP_PACKAGE))
    }
    @Test fun `standalone Health Connect uses its settings action`() {
        var target: Intent? = null
        assertTrue(PlatformSettingsLauncher("com.example", 33) { target = it }.openHealthSettings())
        assertEquals("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS", target?.action)
    }
}
