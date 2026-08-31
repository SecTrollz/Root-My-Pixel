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

    @Test
    fun `manifest declares no service or broadcast receiver`() {
        val manifest = readManifest()
        // ExploitService is intentionally NOT declared here: it's hosted by Shizuku's own
        // UserService mechanism (Shizuku.bindUserService), reachable only through a Shizuku
        // Binder session that already requires physical/local ADB pairing. A <service> or
        // <receiver> element in the manifest would instead be a normal Android component any
        // other app (or, for a receiver registered on a system broadcast, the system itself)
        // could invoke directly -- a second entry point into this app that bypasses that
        // Shizuku gate entirely, which must never happen incidentally.
        assertFalse(
            "Manifest must declare no <service>: any component here is reachable by other " +
                "apps on the device without going through Shizuku's local-pairing gate.",
            Regex("<service[ >]").containsMatchIn(manifest),
        )
        assertFalse(
            "Manifest must declare no <receiver>: same reasoning as <service> above.",
            Regex("<receiver[ >]").containsMatchIn(manifest),
        )
    }

    @Test
    fun `the Shizuku provider still requires a privileged caller permission`() {
        val manifest = readManifest()
        // ShizukuProvider is exported=true (required for Shizuku's own manager app to reach
        // it), so this permission is the only thing standing between "any app on the device"
        // and this provider. INTERACT_ACROSS_USERS_FULL is a signature|privileged permission
        // ordinary third-party apps cannot hold -- only Shizuku's own already-privileged
        // process (uid 2000, started via the physical/local ADB pairing already covered
        // above) does. Losing this permission attribute would open the provider to any
        // installed app.
        // Split on each "<provider" occurrence rather than trying to regex-match a whole
        // element (self-closing vs. open/close tags make that fiddly to get right): the
        // chunk right after "<provider" for the one naming ShizukuProvider runs up to the
        // *next* "<provider" (or end of file), which is exactly that element's own content.
        val providerBlock = manifest.split("<provider").drop(1)
            .firstOrNull { it.contains("rikka.shizuku.ShizukuProvider") }
        assertTrue(
            "Could not find the ShizukuProvider <provider> declaration to check at all -- " +
                "manifest structure changed unexpectedly.",
            providerBlock != null,
        )
        assertTrue(
            "ShizukuProvider must require android.permission.INTERACT_ACROSS_USERS_FULL " +
                "(or an equally privileged, non-third-party-grantable permission) -- without " +
                "it, any app on the device (not just Shizuku itself) could call into it.",
            providerBlock!!.contains("android.permission.INTERACT_ACROSS_USERS_FULL"),
        )
    }
}
