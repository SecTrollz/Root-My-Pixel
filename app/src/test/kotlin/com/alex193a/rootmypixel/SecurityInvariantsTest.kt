package com.alex193a.rootmypixel

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Root My Pixel's whole trust model rests on root only ever being obtainable
 * by someone physically holding (or already ADB-paired with) the device:
 * the exploit chain runs through a local Shizuku Binder session, never a
 * network call. These checks fail the build the moment that stops being
 * true in the manifest, rather than relying on it staying true by habit.
 */
class SecurityInvariantsTest {

    private fun readManifest(): String {
        val candidates = listOf(
            File("src/main/AndroidManifest.xml"),
            File("app/src/main/AndroidManifest.xml"),
        )
        val manifest = candidates.firstOrNull { it.isFile }
            ?: error("Could not locate AndroidManifest.xml from ${File(".").absolutePath}")
        return manifest.readText()
    }

    @Test
    fun `manifest never requests network permissions`() {
        val manifest = readManifest()
        val networkPermissions = listOf(
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.ACCESS_WIFI_STATE",
            "android.permission.CHANGE_NETWORK_STATE",
        )
        for (permission in networkPermissions) {
            assertFalse(
                "Root My Pixel must never request $permission: root must only ever be " +
                    "reachable by someone physically present at (or already ADB-paired " +
                    "with) the device, never over the network.",
                manifest.contains(permission),
            )
        }
    }

    @Test
    fun `only the launcher activity is exported`() {
        val manifest = readManifest()
        val exportedTrueCount = Regex("android:exported=\"true\"").findAll(manifest).count()
        assertTrue(
            "Expected exactly two android:exported=\"true\" declarations (MainActivity's " +
                "launcher intent-filter and the Shizuku provider it depends on); found " +
                "$exportedTrueCount. A new exported component widens what other apps on the " +
                "device can invoke and must be reviewed deliberately, not added incidentally.",
            exportedTrueCount == 2,
        )
    }
}
