package com.alex193a.rootmypixel.feature.install

import android.app.Application
import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.alex193a.rootmypixel.R
import com.alex193a.rootmypixel.core.Result
import com.alex193a.rootmypixel.domain.model.DeviceSnapshot
import com.alex193a.rootmypixel.domain.model.InstallPhase
import com.alex193a.rootmypixel.domain.model.InstallUiState
import com.alex193a.rootmypixel.domain.model.TargetProfile
import com.alex193a.rootmypixel.domain.model.UnrootWarningUi
import com.alex193a.rootmypixel.domain.model.VerifiedPayloads
import com.alex193a.rootmypixel.domain.usecase.DownloadPayloadsUseCase
import com.alex193a.rootmypixel.domain.usecase.ResolveTargetUseCase
import com.alex193a.rootmypixel.shizuku.ExploitService
import com.alex193a.rootmypixel.shizuku.IExploitService
import com.alex193a.rootmypixel.utils.NativeProbe
import com.alex193a.rootmypixel.utils.UnrootCommandOutcome
import com.alex193a.rootmypixel.utils.UnrootIssue
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
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.milliseconds

data class TargetCatalogUiState(
    val loading: Boolean = false,
    val profiles: List<TargetProfile> = emptyList(),
    val error: String? = null,
)

class InstallViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application
    private val resolveTargetUseCase: ResolveTargetUseCase by lazy {
        get(ResolveTargetUseCase::class.java)
    }
    private val downloadPayloadsUseCase: DownloadPayloadsUseCase by lazy {
        get(DownloadPayloadsUseCase::class.java)
    }

    private val mutableState = MutableStateFlow(InstallUiState())
    private val mutableTargetCatalog = MutableStateFlow(TargetCatalogUiState())
    private var discoveryJob: Job? = null
    private var installJob: Job? = null
    private var isInstalling = false
    private var watchdogJob: Job? = null

    val state: StateFlow<InstallUiState> = mutableState.asStateFlow()
    val targetCatalog: StateFlow<TargetCatalogUiState> = mutableTargetCatalog.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        if (installJob?.isActive == true) return
        discoveryJob?.cancel()
        discoveryJob = viewModelScope.launch(Dispatchers.IO) {
            try {
                val probe = NativeProbe.run()
                val deviceInfo = NativeProbe.readDeviceSnapshot()
                if (NativeProbe.isKernelSuActive()) {
                    mutableState.value = InstallUiState(
                        phase = InstallPhase.Installed,
                        message = app.getString(R.string.status_ksu_active),
                        probeOutput = probe,
                        log = probe,
                    )
                    return@launch
                }
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
                val result = resolveTargetUseCase(snapshot)
                when (result) {
                    is Result.Success -> {
                        val profile = result.data
                        mutableState.value = InstallUiState(
                            phase = InstallPhase.Ready,
                            message = app.getString(R.string.status_not_installed),
                            probeOutput = probe,
                            log = "$probe\n${app.getString(
                                R.string.log_profile, profile.profileId)}",
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

    fun install(profileId: String? = null, permissiveOnly: Boolean = false) {
        if (installJob?.isActive == true ||
            mutableState.value.phase == InstallPhase.Installed) return
        discoveryJob?.cancel()

        installJob = viewModelScope.launch(Dispatchers.IO) {
            isInstalling = true
            mutableState.value = InstallUiState(
                phase = InstallPhase.Checking,
                probeOutput = mutableState.value.probeOutput,
            )
            try {
                setPhase(InstallPhase.Checking, app.getString(R.string.status_checking))
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

                val profile = when {
                    profileId != null -> {
                        when (val r = resolveTargetUseCase(profileId)) {
                            is Result.Success -> r.data
                            is Result.Error ->
                                throw IllegalStateException(r.error.message)
                        }
                    }
                    else -> {
                        when (val r = resolveTargetUseCase(snapshot)) {
                            is Result.Success -> r.data
                            is Result.Error ->
                                throw IllegalStateException(r.error.message)
                        }
                    }
                }
                appendLog(app.getString(R.string.log_profile, profile.profileId))

                setPhase(InstallPhase.Downloading, "Preparing payloads…")
                val payloads = when (
                    val r = downloadPayloadsUseCase(profile) { appendLog("[*] $it") }
                ) {
                    is Result.Success -> r.data
                    is Result.Error ->
                        throw IllegalStateException(r.error.message)
                }
                appendLog("Payloads extracted from APK")

                val useShizuku = hasShizukuPermission()
                require(useShizuku) {
                    app.getString(R.string.error_shizuku_required)
                }
                appendLog("[*] Using Shizuku shell access: $useShizuku")

                runPreflightSafetyCheck()

                setPhase(InstallPhase.Exploiting, app.getString(R.string.status_exploit))
                executeExploit(payloads)

                if (permissiveOnly) {
                    setPhase(InstallPhase.Installed, "SELinux permissive + root shell ready")
                    appendLog("Install complete — permissive mode, KernelSU skipped")
                } else {
                    setPhase(InstallPhase.LoadingKernelSu, app.getString(R.string.status_loading_ksu))
                    installKernelSu(payloads)

                    setPhase(InstallPhase.Installed, app.getString(R.string.status_ksu_active))
                    appendLog(app.getString(R.string.log_install_complete))
                    val cveRootAvailable = hasCveRootTransport()
                    mutableState.value = mutableState.value.copy(
                        canUnrootCurrentSession = cveRootAvailable,
                    )
                    appendLog(
                        if (cveRootAvailable) {
                            "[+] Current-session CVE root transport verified; Unroot is available"
                        } else {
                            "[!] Current-session CVE root transport is unavailable; use the main Unroot flow"
                        },
                    )
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                appendLog("[-] ${error.message ?: error.javaClass.simpleName}")
                setPhase(InstallPhase.Failed, app.getString(R.string.status_install_failed))
            } finally {
                isInstalling = false
                watchdogJob?.cancel()
            }
        }
    }

    // --- Shizuku UserService helpers ---

    private data class ShizukuServiceHandle(
        val service: IExploitService,
        val conn: ServiceConnection,
    )

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

        // Wait up to 5 seconds for connection
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

    // --- System Stability & Crash Prevention ---

    private suspend fun testRootStability(helper: File): Boolean {
        appendLog("[*] Testing root transport stability...")
        for (attempt in 1..3) {
            val result = runHelper(helper, "-c", "id -u")
            if (result.code == 0 && result.output.trim() == "0") {
                appendLog("[+] Root verified (attempt $attempt): uid=0")
                return true
            }
            appendLog("[!] Root test failed (attempt $attempt): code=${result.code} output=${result.output.take(50)}")
            delay(500)
        }
        return false
    }

    private suspend fun checkSystemHealth(helper: File): Boolean {
        val result = runHelper(helper, "-c", "echo heartbeat")
        return result.code == 0 && result.output.contains("heartbeat")
    }

    private fun startWatchdog(timeout: Long = 30_000) {
        watchdogJob?.cancel()
        watchdogJob = viewModelScope.launch(Dispatchers.Default) {
            delay(timeout)
            if (isInstalling) {
                appendLog("[-] WATCHDOG: System unresponsive for ${timeout / 1000}s, aborting")
                isInstalling = false
                setPhase(InstallPhase.Failed, "System became unresponsive (crash prevented)")
            }
        }
    }

    // --- Exploit execution ---

    private suspend fun executeExploit(payloads: VerifiedPayloads) {
        executeExploitViaShizuku(payloads)
        appendLog(app.getString(R.string.log_bootstrap_root))

        val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
        if (!testRootStability(helper)) {
            throw IllegalStateException("Exploit succeeded but root transport is unstable")
        }
    }

    private suspend fun executeExploitViaShizuku(payloads: VerifiedPayloads) {
        val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
        require(helper.exists()) { app.getString(R.string.error_helper_unavailable) }

        val handle = bindExploitService()
            ?: throw IllegalStateException("Failed to bind Shizuku UserService")

        try {
            val logPrefix = mutableState.value.log
            handle.service.startExploit(
                payloads.exploit.readBytes(),
                helper.readBytes(),
                "/data/local/tmp/exploit.log",
            )

            val startedAt = SystemClock.elapsedRealtime()
            var lastProgressAt = startedAt
            var lastRawLog = ""

            while (handle.service.isRunning) {
                val remoteLog = handle.service.getLog()
                val fileLog = handle.service.exec("cat /data/local/tmp/exploit.log 2>/dev/null || true")
                val currentLog = if (fileLog.length > remoteLog.length) fileLog else remoteLog

                if (currentLog != lastRawLog) {
                    publishLog(logPrefix, currentLog)
                    lastRawLog = currentLog
                    lastProgressAt = SystemClock.elapsedRealtime()
                }
                val now = SystemClock.elapsedRealtime()
                require(now - lastProgressAt < EXPLOIT_STALL_MILLIS) {
                    app.getString(R.string.error_exploit_stalled)
                }
                require(now - startedAt < EXPLOIT_TOTAL_MILLIS) {
                    app.getString(R.string.error_exploit_timeout)
                }
                delay(LOG_POLL_INTERVAL)
            }

            val exitCode = handle.service.waitFor()
            val finalLog = handle.service.exec("cat /data/local/tmp/exploit.log 2>/dev/null || true")
            if (finalLog.isNotBlank()) {
                publishLog(logPrefix, finalLog)
            }

            require(exitCode == 0) {
                app.getString(R.string.error_payload_exit, exitCode, "")
            }
            require(finalLog.contains("done=1") && finalLog.contains("root=1")) {
                app.getString(R.string.error_success_marker)
            }
        } finally {
            unbindExploitService(handle)
        }
    }

    // Shizuku helpers

    private fun hasShizukuPermission(): Boolean {
        return try {
            Shizuku.pingBinder() &&
            Shizuku.isPreV11().not() &&
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED &&
            Shizuku.getUid() == 2000
        } catch (_: Exception) {
            false
        }
    }

    // --- Pre-root check: warn about signals from outside the phone, never about MDM status ---
    //
    // Root My Pixel is for a device's owner, physically holding it, rooting their own
    // phone. Whether the device is enrolled in an MDM/enterprise Device Policy Controller
    // (Device Owner, Profile Owner, or any other Device Admin app) is irrelevant to that —
    // a corporate-managed phone's legitimate holder can root it exactly like anyone else,
    // and this app never checks or blocks on that status. The actual guarantee that only
    // the physical holder can ever reach root here is structural, not a runtime check:
    // Root My Pixel has no INTERNET permission and no networking code anywhere (enforced
    // by SecurityInvariantsTest), so there is no network path for a signal from outside
    // the phone to reach it at all — root only ever comes from a local Shizuku Binder
    // session that itself requires physical/local pairing.
    //
    // What this function does check, as non-blocking warnings, are two things that
    // genuinely could let someone other than the phone's holder influence what happens
    // right now: Wireless debugging left on (a standing local-network ADB surface) and a
    // known remote-screen-control app being installed (a literal outside input channel).
    // Neither blocks rooting on its own — both are heuristics worth a glance, not proof of
    // a problem. Mirrors scripts/preflight-check.sh, which runs the same checks standalone
    // via `rish` before the app is even opened.

    private suspend fun runPreflightSafetyCheck() {
        appendLog("[*] Checking for signals from outside the phone...")
        val handle = bindExploitService()
            ?: throw IllegalStateException("Failed to bind Shizuku UserService for preflight checks")
        try {
            val adbWifi = handle.service.exec("settings get global adb_wifi_enabled")
                .lineSequence().firstOrNull()?.trim().orEmpty()
            if (adbWifi == "1") {
                appendLog(
                    "[!] Wireless debugging is currently ON. If you only enabled it to pair " +
                        "Shizuku, turn it back off (Settings > Developer options > Wireless " +
                        "debugging) once you're done — leaving it on is a standing " +
                        "local-network attack surface."
                )
            }

            val installedPackages = handle.service.exec("pm list packages")
            val foundRemoteApps = KNOWN_REMOTE_CONTROL_PACKAGES.filter { pkg ->
                installedPackages.contains("package:$pkg")
            }
            if (foundRemoteApps.isNotEmpty()) {
                appendLog(
                    "[!] Known remote-screen-control app(s) installed: " +
                        "${foundRemoteApps.joinToString(", ")}. These let someone else drive " +
                        "the screen remotely — if you didn't install one yourself, remove it " +
                        "before rooting."
                )
            }
        } finally {
            unbindExploitService(handle)
        }
    }

    // --- KernelSU ---

    private fun installKernelSu(payloads: VerifiedPayloads) {
        val ksudSource = payloads.kernelSu.absolutePath
        val ksudDest = "/data/local/tmp/ksud-pixel"
        val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")

        // Validate paths contain no shell metacharacters (command injection prevention)
        validateShellPath(ksudSource)
        validateShellPath(ksudDest)

        startWatchdog(60_000)

        try {
            // 1. Wait for daemon to be ready
            awaitDaemonSocket()
            diagnoseDaemon()

        // 2. Stage ksud via daemon root (cp + chmod + chown)
        appendLog("[*] Staging ReSukiSU binary...")
        val stageCmd = "cp '$ksudSource' $ksudDest && chmod 755 $ksudDest && " +
            "chown root:root $ksudDest"
        var stageSuccess = false
        for (attempt in 1..5) {
            val result = runHelper(helper, "-c", stageCmd)
            if (result.code == 0) {
                val verify = runHelper(helper, "-c", "ls -la $ksudDest")
                if (verify.output.contains("rwxr-xr-x") ||
                    verify.output.contains("-rwxr-xr-x")) {
                    appendLog("ReSukiSU staged: ${verify.output.trim()}")
                    stageSuccess = true
                    break
                }
            }
            appendLog("[!] Stage attempt $attempt: code=${result.code} ${result.output.take(120)}")
            Thread.sleep(1000)
        }
        require(stageSuccess) {
            app.getString(R.string.error_ksu_stage, "stage failed after 5 attempts")
        }

        // 3. Execute late-load via daemon root
        appendLog("[*] Triggering KernelSU late-load (kmi=${payloads.kmi})...")
        val lateResult = runHelper(helper, "-c",
            "$ksudDest late-load --kmi ${payloads.kmi}")
        if (lateResult.output.isNotBlank()) {
            appendLog(lateResult.output.take(2000))
        }

        // 4. Verify KSU is actually loaded (check multiple paths)
        var ksuActive = false
        for (i in 1..10) {
            val check = runHelper(helper, "-c",
                "test -e /dev/kernelsu && echo KSU_OK || " +
                "test -e /sys/kernel/kernelsu && echo KSU_OK || " +
                "test -e /data/adb/ksu && echo KSU_OK || " +
                "echo KSU_NOT_FOUND")
            if (check.output.contains("KSU_OK")) {
                appendLog("[+] KernelSU verified (attempt $i): ${check.output.take(60)}")
                ksuActive = true
                break
            }
            Thread.sleep(500)
            }
            require(ksuActive) {
                app.getString(
                    R.string.error_ksu_verify,
                    lateResult.code,
                    lateResult.output.take(200)
                )
            }
            appendLog(app.getString(R.string.log_ksu_control_verified))
        } finally {
            watchdogJob?.cancel()
        }
    }

    private fun runHelper(helper: File, vararg arguments: String): CommandResult {
        for (attempt in 1..5) {
            val process = ProcessBuilder(listOf(helper.absolutePath) + arguments)
                .redirectErrorStream(true)
                .start()
            val finished = process.waitFor(COMMAND_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                process.waitFor()
            }
            val output = process.inputStream.bufferedReader().use { it.readText() }
            val result = CommandResult(
                if (finished) process.exitValue() else COMMAND_TIMEOUT_CODE,
                output.trim(),
            )

            val transient = result.output.contains("No such file or directory") ||
                result.output.contains("Connection refused") ||
                result.code == 127
            if (!transient || attempt == 5) {
                return result
            }
            Thread.sleep(1500)
        }
        return CommandResult(1, "runHelper: exhausted retries")
    }

    private fun hasCveRootTransport(): Boolean {
        val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
        if (!helper.exists()) return false

        return runCatching {
            val result = runHelper(helper, "-c", "id -u")
            result.code == 0 && result.output.trim() == "0"
        }.getOrDefault(false)
    }

    fun unrootCurrentSession() {
        if (mutableState.value.phase != InstallPhase.Installed ||
            !mutableState.value.canUnrootCurrentSession
        ) return

        viewModelScope.launch(Dispatchers.IO) {
            mutableState.value = mutableState.value.copy(
                phase = InstallPhase.Checking,
                message = app.getString(R.string.status_unrooting),
                canUnrootCurrentSession = false,
            )
            appendLog("[*] Verifying current-session CVE root transport...")

            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            if (!hasCveRootTransport()) {
                appendLog("[-] CVE root transport is no longer available")
                showUnrootWarning(UnrootIssue.affectedByMissingTransport, canRetry = false)
                return@launch
            }

            val command = runCatching {
                app.assets.open("unroot.sh").bufferedReader().use { it.readText() }
            }.getOrElse {
                showUnrootWarning(listOf(UnrootIssue.Unknown))
                return@launch
            }
            appendLog("[*] Removing root state through the current CVE session...")
            val result = runHelper(helper, "-c", command)
            val outcome = UnrootCommandOutcome.parse(result.output)
            if (outcome.cleanupComplete && outcome.rebootRequested) {
                appendLog("[+] Cleanup complete; reboot requested")
            } else {
                appendLog("[!] Unroot output (exit=${result.code}):\n${result.output.ifBlank { "no output" }}")
                val issues = outcome.issues.toMutableList()
                if (outcome.cleanupComplete && !outcome.rebootRequested) {
                    issues += UnrootIssue.Reboot
                }
                if (!outcome.hasStructuredOutput) issues += UnrootIssue.Unknown
                showUnrootWarning(issues)
            }
        }
    }

    fun continueUnrootReboot() {
        if (mutableState.value.unrootWarning == null) return
        viewModelScope.launch(Dispatchers.IO) {
            mutableState.value = mutableState.value.copy(
                phase = InstallPhase.Checking,
                message = app.getString(R.string.status_unrooting),
                unrootWarning = null,
            )
            appendLog("[*] User requested reboot despite incomplete cleanup")

            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            val helperOutput = if (helper.exists()) {
                runCatching { runHelper(helper, "-c", REBOOT_COMMAND).output }.getOrDefault("")
            } else {
                ""
            }
            if (helperOutput.contains("UNROOT_REBOOT_REQUESTED")) return@launch

            val handle = runCatching { bindExploitService() }.getOrNull()
            val shizukuOutput = if (handle != null) {
                try {
                    handle.service.exec(REBOOT_COMMAND)
                } catch (_: Exception) {
                    ""
                } finally {
                    unbindExploitService(handle)
                }
            } else {
                ""
            }
            if (!shizukuOutput.contains("UNROOT_REBOOT_REQUESTED")) {
                showUnrootWarning(listOf(UnrootIssue.Reboot))
            }
        }
    }

    fun cancelUnrootReboot() {
        mutableState.value = mutableState.value.copy(
            phase = InstallPhase.Installed,
            message = app.getString(R.string.status_unroot_incomplete),
            unrootWarning = null,
        )
        appendLog("[*] Reboot cancelled by user")
    }

    private fun showUnrootWarning(
        issues: List<UnrootIssue>,
        canRetry: Boolean? = null,
    ) {
        val outcome = UnrootCommandOutcome(
            cleanupComplete = false,
            rebootRequested = false,
            transportUnavailable = UnrootIssue.RootTransport in issues,
            issues = issues.distinct(),
            hasStructuredOutput = true,
        )
        mutableState.value = mutableState.value.copy(
            phase = InstallPhase.Installed,
            message = app.getString(R.string.status_unroot_incomplete),
            canUnrootCurrentSession = canRetry ?: hasCveRootTransport(),
            unrootWarning = UnrootWarningUi(outcome.failedItemsText(app)),
        )
    }

    private fun awaitDaemonSocket() {
        val sock = File("/data/local/tmp/temp_su.sock")
        val deadline = SystemClock.elapsedRealtime() + 15_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            if (sock.exists()) return
            Thread.sleep(500)
        }
    }

    private fun diagnoseDaemon() {
        try {
            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            if (!helper.exists()) {
                appendLog("[diag] helper binary missing")
                return
            }
            val suCheck = runHelper(helper, "-c",
                "ls -la /apex/com.android.virt/bin/su /data/local/tmp/su 2>/dev/null || echo 'not found'")
            appendLog("[diag] su binaries: ${suCheck.output.take(200)}")

            val sockCheck = File("/data/local/tmp/temp_su.sock")
            appendLog("[diag] socket file: ${if (sockCheck.exists()) "present" else "NOT FOUND"}")

            val logCheck = runHelper(helper, "-c",
                "cat /data/local/tmp/su_daemon.log 2>/dev/null || echo 'empty'")
            appendLog("[diag] daemon log: ${logCheck.output.take(300)}")
        } catch (e: Exception) {
            appendLog("[diag] error: ${e.message}")
        }
    }

    fun softReboot() {
        if (isInstalling) {
            appendLog("[-] Cannot soft reboot during installation (crash prevention)")
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            val helper = File(app.applicationInfo.nativeLibraryDir, "libcve43499root.so")
            if (!helper.exists()) return@launch
            val result = runHelper(helper, "-c",
                "killall -9 system_server 2>/dev/null; true")
            appendLog("[*] Soft reboot triggered (exit ${result.code})")
        }
    }

    // --- Path Validation (Command Injection Prevention) ---

    private fun validateShellPath(path: String) {
        require(!path.contains(Regex("[;|&\$`\"'\\\\]"))) {
            "Path contains shell metacharacters and is unsafe: $path"
        }
    }

    // --- UI helpers ---

    private fun setPhase(phase: InstallPhase, message: String) {
        mutableState.value = mutableState.value.copy(phase = phase, message = message)
        appendLog("[*] $message")
    }

    private fun publishLog(prefix: String, rawLog: String) {
        mutableState.value = mutableState.value.copy(
            log = listOf(prefix, rawLog)
                .filter(String::isNotBlank)
                .joinToString("\n")
                .takeLast(MAX_LOG_CHARS),
        )
    }

    private fun appendLog(line: String) {
        val cleanLine = line.trim()
        if (cleanLine.isBlank()) return
        mutableState.value = mutableState.value.copy(
            log = (mutableState.value.log + "\n" + cleanLine)
                .trim()
                .takeLast(MAX_LOG_CHARS),
        )
    }

    data class CommandResult(val code: Int, val output: String)

    companion object {
        private const val EXPLOIT_STALL_MILLIS = 600_000L
        private const val EXPLOIT_TOTAL_MILLIS = 1_800_000L
        private const val MAX_LOG_CHARS = 5 * 1024 * 1024
        private const val COMMAND_TIMEOUT_SECONDS = 90L
        private const val COMMAND_TIMEOUT_CODE = 124
        private val LOG_POLL_INTERVAL = 250.milliseconds
        private const val REBOOT_COMMAND =
            "sync; if svc power reboot || reboot; then " +
                    "echo UNROOT_REBOOT_REQUESTED; else echo UNROOT_FAIL:reboot:${'$'}?; fi"

        // Remote-screen-control apps only — deliberately NOT MDM/DPC packages, since MDM
        // enrollment is irrelevant to whether the phone's physical holder can root it (see
        // the comment on runPreflightSafetyCheck). These are apps that let someone else
        // literally drive the screen remotely, a genuine outside-input channel. Non-
        // exhaustive on purpose: a hit here is a prompt to double-check the app is one you
        // actually intend to have installed, not proof of a problem — this list only warns
        // (see runPreflightSafetyCheck), it never blocks rooting.
        // Keep this in sync with scripts/preflight-check.sh's KNOWN_REMOTE_PKGS.
        private val KNOWN_REMOTE_CONTROL_PACKAGES = listOf(
            "com.teamviewer.host",
            "com.teamviewer.quicksupport.market",
            "com.teamviewer.quicksupport.addon",
            "com.anydesk.anydeskandroid",
            "com.sand.airdroid",
            "com.sand.airmirror",
            "com.rsupport.mobizen.mvagent",
            "com.splashtop.remote.pad.v2",
            "com.splashtop.streamer",
            "com.remotepc.android",
        )
    }
}
