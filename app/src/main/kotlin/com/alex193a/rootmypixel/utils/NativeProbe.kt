package com.alex193a.rootmypixel.utils

import android.content.Context
import java.io.File

/**
 * Native probe companion. Uses JNI to read device information and check
 * KernelSU status. The actual native implementation is in src/main/cpp/.
 */
object NativeProbe {
    init {
        System.loadLibrary("pixel_native")
    }

    /**
     * Run the native probe: returns device information as a text dump.
     */
    external fun run(): String

    /**
     * Check if KernelSU/ReSukiSU is active via kernel driver syscall in a fork-isolated process.
     */
    external fun isKernelSuActiveNative(): Boolean

    /**
     * Check if KernelSU/ReSukiSU or local root daemon is currently active on the device.
     */
    fun isKernelSuActive(context: Context? = null): Boolean {
        return runCatching { isKernelSuActiveNative() }.getOrDefault(false) ||
                checkSuBinary() ||
                (context != null && checkExploitDaemon(context)) ||
                File("/dev/kernelsu").exists() ||
                File("/sys/kernel/kernelsu").exists()
    }

    private fun checkSuBinary(): Boolean {
        return runCatching {
            val p1 = ProcessBuilder("su", "-v").redirectErrorStream(true).start()
            val out1 = p1.inputStream.bufferedReader().use { it.readText().trim() }
            if (p1.waitFor() == 0 && out1.isNotBlank()) return true

            val p2 = ProcessBuilder("su", "-c", "id").redirectErrorStream(true).start()
            val out2 = p2.inputStream.bufferedReader().use { it.readText().trim() }
            if (p2.waitFor() == 0 && out2.contains("uid=0")) return true

            false
        }.getOrDefault(false)
    }

    private fun checkExploitDaemon(context: Context): Boolean {
        val helper = File(context.applicationInfo.nativeLibraryDir, "libcve43499root.so")
        if (!helper.exists()) return false
        return runCatching {
            val process = ProcessBuilder(helper.absolutePath, "-c", "id")
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText().trim() }
            process.waitFor() == 0 && output.contains("uid=0")
        }.getOrDefault(false)
    }

    /**
     * Read current device snapshot from /proc and system properties.
     */
    fun readDeviceSnapshot(): DeviceInfo {
        val kernelRelease = runCatching {
            File("/proc/version").readText().trim()
        }.getOrElse {
            System.getProperty("os.version") ?: ""
        }
        val versionParts = kernelRelease.split(" ")
        val release = if (versionParts.size >= 3) versionParts[2] else kernelRelease

        val buildDisplay = android.os.Build.DISPLAY.takeIf { it.isNotBlank() } ?: runCatching {
            Runtime.getRuntime().exec(arrayOf("getprop", "ro.build.display.id"))
                .inputStream.bufferedReader().readText().trim()
        }.getOrDefault("")

        val model = android.os.Build.MODEL.takeIf { it.isNotBlank() } ?: runCatching {
            Runtime.getRuntime().exec(arrayOf("getprop", "ro.product.model"))
                .inputStream.bufferedReader().readText().trim()
        }.getOrDefault("")

        val device = android.os.Build.DEVICE.takeIf { it.isNotBlank() } ?: runCatching {
            Runtime.getRuntime().exec(arrayOf("getprop", "ro.product.device"))
                .inputStream.bufferedReader().readText().trim()
        }.getOrDefault("")

        val sdkVersion = if (android.os.Build.VERSION.SDK_INT > 0) {
            android.os.Build.VERSION.SDK_INT
        } else {
            runCatching {
                Runtime.getRuntime().exec(arrayOf("getprop", "ro.build.version.sdk"))
                    .inputStream.bufferedReader().readText().trim().toInt()
            }.getOrDefault(0)
        }

        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: runCatching {
            Runtime.getRuntime().exec(arrayOf("getprop", "ro.product.cpu.abi"))
                .inputStream.bufferedReader().readText().trim()
        }.getOrDefault("arm64-v8a")

        val pageSize = runCatching {
            android.system.Os.sysconf(android.system.OsConstants._SC_PAGESIZE).toInt()
        }.getOrDefault(4096)

        return DeviceInfo(
            kernelRelease = release,
            kernelVersion = kernelRelease,
            buildDisplay = buildDisplay,
            sdkVersion = sdkVersion,
            abi = abi,
            pageSize = pageSize,
            model = model,
            device = device,
        )
    }
}

data class DeviceInfo(
    val kernelRelease: String,
    val kernelVersion: String,
    val buildDisplay: String,
    val sdkVersion: Int,
    val abi: String,
    val pageSize: Int,
    val model: String,
    val device: String,
)
