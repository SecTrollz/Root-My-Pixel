package com.alex193a.rootmypixel.feature.main

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.alex193a.rootmypixel.R
import com.alex193a.rootmypixel.core.Result
import com.alex193a.rootmypixel.domain.model.DeviceSnapshot
import com.alex193a.rootmypixel.domain.model.InstallPhase
import com.alex193a.rootmypixel.domain.model.InstallUiState
import com.alex193a.rootmypixel.domain.usecase.ResolveTargetUseCase
import com.alex193a.rootmypixel.feature.install.InstallActivity
import com.alex193a.rootmypixel.shizuku.ExploitService
import com.alex193a.rootmypixel.shizuku.IExploitService
import com.alex193a.rootmypixel.utils.NativeProbe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.java.KoinJavaComponent.get
import rikka.shizuku.Shizuku
import java.io.File

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application
    private val resolveTargetUseCase: ResolveTargetUseCase by lazy {
        get(ResolveTargetUseCase::class.java)
    }

    private val mutableState = MutableStateFlow(InstallUiState())
    private val mutableShizukuAvailable = MutableStateFlow(false)
    private val mutableReSukiSuInstalled = MutableStateFlow(false)
    private val mutableUptimeExceeded = MutableStateFlow(false)
    private var refreshJob: Job? = null

    val state: StateFlow<InstallUiState> = mutableState.asStateFlow()
    val shizukuAvailable: StateFlow<Boolean> = mutableShizukuAvailable.asStateFlow()
    val reSukiSuInstalled: StateFlow<Boolean> = mutableReSukiSuInstalled.asStateFlow()
    val uptimeExceeded: StateFlow<Boolean> = mutableUptimeExceeded.asStateFlow()


    private val shizukuPermissionHandler = Handler(Looper.getMainLooper())
    private val shizukuListener = Shizuku.OnBinderReceivedListener {
        shizukuPermissionHandler.post { checkShizuku() }
    }
    private val shizukuDeadListener = Shizuku.OnBinderDeadListener {
        shizukuPermissionHandler.post { mutableShizukuAvailable.value = false }
    }
    private val shizukuPermissionListener = Shizuku.OnRequestPermissionResultListener { code, result ->
        if (code == SHIZUKU_PERMISSION_CODE) {
            shizukuPermissionHandler.post { checkShizuku() }
        }
    }

    init {
        refresh()
    }

    fun initShizuku() {
        Shizuku.addBinderReceivedListener(shizukuListener)
        Shizuku.addBinderDeadListener(shizukuDeadListener)
        Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)

        if (Shizuku.pingBinder()) {
            checkShizuku()
        }
    }

    private fun checkShizuku() {
        val available = try {
            Shizuku.pingBinder() &&
            Shizuku.isPreV11().not() &&
            Shizuku.getUid() == 2000 &&
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }

        if (!available && Shizuku.pingBinder() && Shizuku.isPreV11().not()) {
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                Shizuku.requestPermission(SHIZUKU_PERMISSION_CODE)
            }
        }

        mutableShizukuAvailable.value = available
    }

    override fun onCleared() {
        super.onCleared()
        Shizuku.removeBinderReceivedListener(shizukuListener)
        Shizuku.removeBinderDeadListener(shizukuDeadListener)
        Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
    }

    fun refresh() {
        if (refreshJob?.isActive == true) return
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch(Dispatchers.IO) {
            mutableState.value = InstallUiState(phase = InstallPhase.Checking)
            mutableUptimeExceeded.value = SystemClock.elapsedRealtime() > UPTIME_THRESHOLD_MS

            try {
                mutableReSukiSuInstalled.value = app.packageManager
                    .getLaunchIntentForPackage("com.resukisu.resukisu") != null
                val probe = NativeProbe.run()
                if (NativeProbe.isKernelSuActive(app)) {
                    mutableState.value = InstallUiState(
                        phase = InstallPhase.Installed,
                        message = app.getString(R.string.status_ksu_active),
                        probeOutput = probe,
                        log = probe,
                    )
                    return@launch
                }
                val deviceInfo = NativeProbe.readDeviceSnapshot()
                val snapshot = DeviceSnapshot(
                    kernelRelease = deviceInfo.kernelRelease,
                    kernelVersion = deviceInfo.kernelVersion,
                    buildDisplay = deviceInfo.buildDisplay,
                    sdkVersion = deviceInfo.sdkVersion,
                    abi = deviceInfo.abi,
                    pageSize = deviceInfo.pageSize,
                    model = deviceInfo.model,
                    device = deviceInfo.device,
                )

                when (val result = resolveTargetUseCase(snapshot)) {
                    is Result.Success -> {
                        val profile = result.data
                        mutableState.value = InstallUiState(
                            phase = InstallPhase.Ready,
                            message = app.getString(R.string.status_not_installed),
                            probeOutput = probe,
                            log = buildString {
                                appendLine(probe)
                                appendLine("Matched profile: ${profile.profileId}")
                                appendLine("Device: ${deviceInfo.model} (${deviceInfo.device})")
                                appendLine("Kernel: ${deviceInfo.kernelRelease}")
                                appendLine("Build: ${deviceInfo.buildDisplay}")
                                appendLine("SDK: ${deviceInfo.sdkVersion}  ABI: ${deviceInfo.abi}")
                            },
                        )
                    }
                    is Result.Error -> {
                        mutableState.value = InstallUiState(
                            phase = InstallPhase.Failed,
                            message = app.getString(R.string.status_support_failed),
                            probeOutput = probe,
                            log = "$probe\n[-] ${result.error.message}",
                        )
                    }
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                mutableState.value = InstallUiState(
                    phase = InstallPhase.Failed,
                    message = app.getString(R.string.status_support_failed),
                    log = "[-] ${error.message ?: error.javaClass.simpleName}",
                )
            }
        }
    }

    fun install() {
        val intent = Intent(app, InstallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        app.startActivity(intent)
    }

    fun softReboot() {
        viewModelScope.launch(Dispatchers.IO) {
            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            if (!helper.exists()) return@launch

            try {
                val result = runCatching {
                    val process = ProcessBuilder(
                        helper.absolutePath, "-c",
                        "killall -9 system_server 2>/dev/null; true"
                    ).redirectErrorStream(true).start()
                    process.inputStream.bufferedReader().use { it.readText() }
                    process.waitFor()
                }
                val output = result.getOrDefault("daemon unreachable")
                android.util.Log.i("RootMyPixel", "[softReboot] $output")
            } catch (_: Exception) { }
        }
    }

    fun exportLog() {
        val logFile = File(app.filesDir, "exploit.log")
        if (!logFile.exists()) return

        val uri = FileProvider.getUriForFile(app, "${app.packageName}.provider", logFile)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooserIntent = Intent.createChooser(shareIntent, "Export exploit.log").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        app.startActivity(chooserIntent)
    }

    private data class ShizukuServiceHandle(
        val service: IExploitService,
        val conn: ServiceConnection,
    )

    @Suppress("PLATFORM_CLASS_MAPPED_TO_KOTLIN")
    private fun bindExploitService(): ShizukuServiceHandle? {
        val args = Shizuku.UserServiceArgs(
            ComponentName(app.packageName, ExploitService::class.java.name)
        )
            .daemon(false)
            .processNameSuffix("exploit_service")
            .version(1)

        var service: IExploitService? = null
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                service = IExploitService.Stub.asInterface(binder)
                synchronized(this) {
                    (this as Object).notifyAll()
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                service = null
            }
        }

        Shizuku.bindUserService(args, conn)

        synchronized(conn as Object) {
            if (service == null) {
                try {
                    (conn as Object).wait(5000)
                } catch (_: InterruptedException) {
                }
            }
        }

        val svc = service ?: run {
            Shizuku.unbindUserService(args, conn, true)
            return null
        }
        return ShizukuServiceHandle(svc, conn)
    }

    private fun unbindExploitService(handle: ShizukuServiceHandle) {
        val args = Shizuku.UserServiceArgs(
            ComponentName(app.packageName, ExploitService::class.java.name)
        )
            .daemon(false)
            .processNameSuffix("exploit_service")
            .version(1)
        Shizuku.unbindUserService(args, handle.conn, true)
    }

    fun unrootAndReboot() {
        viewModelScope.launch(Dispatchers.IO) {
            val logBuilder = StringBuilder(mutableState.value.log)
            fun logStep(msg: String) {
                android.util.Log.i("RootMyPixel", "[unrootAndReboot] $msg")
                logBuilder.appendLine(msg)
                mutableState.value = mutableState.value.copy(
                    phase = InstallPhase.Checking,
                    message = app.getString(R.string.status_unrooting),
                    log = logBuilder.toString(),
                )
            }

            logStep("\n[*] Starting unroot and reboot process...")

            // 1. Root cleanup through the app's own UID. A ReSukiSU Manager grant
            // applies to this UID, not to the Shizuku UserService (UID shell).
            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            var rootCleaned = false
            val rootCleanup = ROOT_CLEANUP_COMMAND

            // Try direct su from app process
            try {
                val suProcess = ProcessBuilder(
                    "su", "-c",
                    rootCleanup
                ).redirectErrorStream(true).start()
                val suOut = suProcess.inputStream.bufferedReader().use { it.readText().trim() }
                val suCode = suProcess.waitFor()
                if (suCode == 0) {
                    logStep("[+] Direct su cleanup successful: ${suOut.ifBlank { "OK" }}")
                    rootCleaned = true
                }
            } catch (_: Exception) {
            }

            // Fallback to helper binary if su wasn't available
            if (!rootCleaned && helper.exists()) {
                logStep("[*] Attempting cleanup via local helper binary...")
                try {
                    val process = ProcessBuilder(
                        helper.absolutePath, "-c",
                        rootCleanup
                    ).redirectErrorStream(true).start()
                    val out = process.inputStream.bufferedReader().use { it.readText().trim() }
                    val code = process.waitFor()
                    if (code == 0) {
                        rootCleaned = true
                        logStep("[+] Helper cleanup successful: ${out.ifBlank { "OK" }}")
                    } else {
                        logStep("[-] Helper cleanup failed (exit=$code): ${out.ifBlank { "no output" }}")
                    }
                } catch (e: Exception) {
                    logStep("[-] Helper cleanup error: ${e.message}")
                }
            }

            // 2. Shizuku UserService cleanup and reboot
            val shizukuActive = try {
                Shizuku.pingBinder() &&
                        Shizuku.isPreV11().not() &&
                        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED &&
                        Shizuku.getUid() == 2000
            } catch (_: Exception) {
                false
            }

            var rebootRequested = false
            if (shizukuActive) {
                logStep("[*] Binding Shizuku UserService...")
                val handle = bindExploitService()
                if (handle != null) {
                    try {
                        val unrootScript = runCatching {
                            app.assets.open("unroot.sh").bufferedReader().use { it.readText() }
                        }.getOrDefault("")

                        if (unrootScript.isNotBlank()) {
                            logStep("[*] Executing unroot.sh via Shizuku...")
                            val scriptOutput = handle.service.exec(unrootScript)
                            logStep("[+] unroot.sh output:\n$scriptOutput")
                            rebootRequested = scriptOutput.contains("Reboot requested")
                        } else {
                            logStep("[-] unroot.sh asset is missing or empty")
                        }
                    } catch (e: Exception) {
                        logStep("[-] Shizuku unroot execution error: ${e.message}")
                    } finally {
                        unbindExploitService(handle)
                    }
                } else {
                    logStep("[-] Failed to bind Shizuku UserService")
                }
            } else {
                logStep("[!] Shizuku is not active or permission not granted")
            }

            // 3. Direct cleanup of tmp files if accessible.
            try {
                File("/data/local/tmp/temp_su.sock").delete()
                File("/data/local/tmp/su_daemon.log").delete()
                File("/data/local/tmp/exploit.log").delete()
            } catch (_: Exception) {
            }

            // 4. If Shizuku was unavailable or did not submit a reboot request,
            // use the same transport that performed privileged cleanup. This
            // covers both a Manager grant for the app and the local CVE daemon.
            if (!rebootRequested) {
                val rebootCommand =
                    "$ROOT_CLEANUP_COMMAND; $TMP_CLEANUP_COMMAND; sync; svc power reboot || reboot"
                logStep("[*] Triggering privileged fallback reboot...")
                try {
                    val p = ProcessBuilder(
                        "su", "-c", rebootCommand
                    ).redirectErrorStream(true).start()
                    val out = p.inputStream.bufferedReader().use { it.readText().trim() }
                    val code = p.waitFor()
                    rebootRequested = code == 0
                    logStep("[*] Direct su reboot exit=$code ${out.ifBlank { "OK" }}")
                } catch (e: Exception) {
                    logStep("[-] Direct su reboot error: ${e.message}")
                }

                if (!rebootRequested && helper.exists()) {
                    try {
                        val p = ProcessBuilder(
                            helper.absolutePath, "-c", rebootCommand
                        ).redirectErrorStream(true).start()
                        val out = p.inputStream.bufferedReader().use { it.readText().trim() }
                        val code = p.waitFor()
                        logStep("[*] CVE fallback reboot exit=$code ${out.ifBlank { "OK" }}")
                    } catch (e: Exception) {
                        logStep("[-] CVE fallback reboot error: ${e.message}")
                    }
                }
            }

            delay(2000)
            refresh()
        }
    }

    companion object {
        private const val SHIZUKU_PERMISSION_CODE = 101
        private const val UPTIME_THRESHOLD_MS = 5 * 60 * 1000L // 5 minutes
        private const val ROOT_CLEANUP_COMMAND =
            "rm -rf /data/adb || exit 1; " +
                    "umount /apex/com.android.virt/bin 2>/dev/null || true; " +
                    "setenforce 1 2>/dev/null || true"
        private const val TMP_CLEANUP_COMMAND =
            "rm -f /data/local/tmp/cve-2026-43499-app.so " +
                    "/data/local/tmp/cve-2026-43499-root " +
                    "/data/local/tmp/ksud-pixel /data/local/tmp/su " +
                    "/data/local/tmp/.su.new.* /data/local/tmp/temp_su.sock " +
                    "/data/local/tmp/exploit.log /data/local/tmp/su_daemon.log"
    }
}
