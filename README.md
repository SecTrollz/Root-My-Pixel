# Root My Pixel

**Root My Pixel** is an Android application designed to automate root access on **Google Pixel** devices leveraging the **NebuSec IonStack** exploit (CVE-2026-43499) and integrating **ReSukiSU / KernelSU**.

---

## How the Application Works

Root My Pixel lets you *temporarily* gain root access with ReSukiSU in just one tap.

### Installation Workflow

1. **Device Detection & Profiling**
   - At startup, the app uses native JNI (`NativeProbe`), `/proc/version` queries, and system properties to detect the device codename, kernel version, CPU ABI, memory page size, and build display ID.
   - Via `ResolveTargetUseCase`, it matches the device details against supported target profiles defined in `assets/profiles.json`.

2. **Shizuku Integration**
   - The app uses **Shizuku** (UID 2000) to acquire ADB shell privileges without needing initial root access, which is required to stage and execute payload binaries in `/data/local/tmp`.
   - A managed `ExploitService` is bound via Binder IPC to stream exploit execution logs to the UI in real time.

3. **Exploit Payload Extraction & Execution**
   - Precompiled binary payloads (`.so`) corresponding to each supported build and the native helper tool (`libcve43499root.so`) are extracted from APK assets to `/data/local/tmp`.
   - The IonStack exploit (CVE-2026-43499) is executed to establish a local root daemon socket (`temp_su.sock`), acquiring full `root` privileges.

4. **KernelSU / ReSukiSU Integration**
   - Staging of the `ksud` binary matching the device's Kernel Module Interface (KMI, e.g., `android15-6.6`).
   - The app triggers the KernelSU **late-load** mechanism (`ksud late-load --kmi <kmi>`).
   - Verifies KernelSU active status by probing kernel device nodes (`/dev/kernelsu`, `/sys/kernel/kernelsu`, `/data/adb/ksu`).

5. **User Interface & Management Tools**
   - Real-time live log progress monitoring.
   - Handy actions for **Soft Reboot** (restarting `system_server`) and **Log Exporting** for debugging purposes.

---

## Exploit Persistence & CVE Research Note

**Why CVE-2026-43499 is the Primary & Sufficient Exploit**

Initial development explored CVE-2026-0163 (VPU driver UAF) as a potential fallback for Pixel 8-10 devices, with the assumption that CVE-2026-43499 would be patched in the August 2026 security update (CP2A.260805.005+). However, research into Android Security Bulletins and device testing revealed:

- **CVE-2026-0163:** Patched August 5, 2026 on all affected Pixel 8-10 devices
- **CVE-2026-43499:** **STILL VULNERABLE** in August 2026 and beyond (CP2A.260805.005, tested through August 29)

**Timeline Verification:**
- All August 2026 builds (CP2A.260805.005) on all tested devices show CVE-2026-43499 remains exploitable
- The vulnerability persisted well past the initial security update window
- There is **no device/build combination** where CVE-2026-0163 would serve as a fallback (by the time it would be needed, it's already patched)

**Architectural Decision:**
Root My Pixel continues to rely on **CVE-2026-43499 (NebuSec IonStack)** as the sole exploit mechanism. No fallback exploit was integrated because the research confirmed the primary exploit remained viable across all tested builds, eliminating the need for complexity or additional payload management.

This approach maintains simplicity while ensuring broad device/build coverage without touching bootloader or firmware modification.

---

## Supported Devices & Build Profiles

| Device                | Codename   | Supported Builds   | Kernel KMI      | Tested |
|:----------------------|:-----------|:------------------|:----------------|:--------|
| **Pixel 10**          | `frankel`  | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro**      | `blazer`   | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro XL**   | `mustang`  | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro Fold** | `rango`    | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10a**         | `stallion` | `CP2A.260805.005` | `android14-6.1` | ✅      |
| **Pixel 9 Pro Fold**  | `comet`    | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 9 Pro**       | `caiman`   | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 9 Pro XL**    | `komodo`   | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 9**           | `tokay`    | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 9a**          | `tegu`     | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 8 Pro**       | `husky`    | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 8**           | `shiba`    | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 8a**          | `akita`    | `CP2A.260805.005` | `android14-6.1` | ✅      |
| **Pixel 7a**          | `lynx`     | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 7 Pro**       | `cheetah`  | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 7**           | `panther`  | `CP2A.260705.006`<br>`BP2A.250705.008` | `android14-6.1` | ✅      |
| **Pixel 6a**          | `bluejay`  | `CP2A.260705.006`<br>`CP1A.260405.005` | `android14-6.1` | ✅      |
| **Pixel 6**           | `oriole`   | `CP2A.260705.006` | `android14-6.1` | ✅      |
| **Pixel 6 Pro**       | `raven`    | `CP2A.260705.006` | `android14-6.1` | ✅      |

---

## Prerequisites

1. A supported Google Pixel device listed in the table above.
2. **Shizuku** installed and running via ADB (`adb shell sh /sdcard/Android/data/rikka.shizuku/starter.sh` or Wireless Debugging).
3. **ReSukiSU Manager** installed on the device to manage root permissions granted to apps.

---

## Starting Shizuku Without a Computer (On-Device Only)

Root My Pixel only needs Shizuku's Binder service to be up and running (UID 2000) — it doesn't care how you got there. Since Android 11, Shizuku can pair and start entirely through Android's built-in **Wireless debugging** ADB-over-Wi-Fi stack, so the whole setup can be done on the Pixel itself, with no PC, no cable, and no Termux/local ADB client involved.

1. **Enable Developer options.** Settings → About phone → tap **Build number** 7 times.
2. **Enable Wireless debugging.** Settings → System → Developer options → turn on **Wireless debugging** (keep the device on Wi-Fi; it doesn't need internet, just an active local network).
3. **Pair once.** Open the **Shizuku** app, scroll to the *Start via Wireless debugging* card, and tap **Pair device with pairing code**. This opens the system "Wireless debugging → Pair device with pairing code" screen showing a 6-digit code and host:port. Enter that code back in Shizuku's pairing dialog — you'll see "Pairing successful." This step only has to be done once per device (until you reset network settings).
4. **Start Shizuku.** Back on the *Start via Wireless debugging* card, tap **Start**. Shizuku briefly opens a system screen to grant itself the ADB shell, then reports as running.
5. Open **Root My Pixel** — the app will detect the active Shizuku binder (UID 2000) the same way it would over a USB/PC-tethered ADB session, and the exploit/root flow proceeds normally.

Caveats:
- Because there is no persistent daemon, Shizuku's wireless-debugging shell does **not** survive a reboot — repeat steps 4 (and occasionally 2–3, if pairing is dropped) after every restart.
- Some OEM battery/network optimizers kill background apps' local-network access; if Shizuku gets stuck on "Searching for pairing service," allow it unrestricted background activity and keep it in the foreground while pairing.
- If step 4 fails, toggle **Wireless debugging** off and back on, then retry.

---

## Pre-Root Safety Check: Only the Phone's Physical Holder Ever Gets Root

Root My Pixel is for a device's owner, physically holding it, rooting their own phone. Whether the device is enrolled in an MDM/enterprise Device Policy Controller (Device Owner, Profile Owner, or any other Device Admin app) is **irrelevant** to that — a corporate-managed phone's legitimate holder can root it exactly like anyone else, and nothing in this app checks or blocks on that status.

The actual guarantee here is structural, not a runtime check you have to trust: Root My Pixel has no `INTERNET` permission and no networking code anywhere (`SecurityInvariantsTest` fails the build if that ever changes), so there is no network path for a signal from outside the phone to reach it at all. Root only ever comes from a local Shizuku Binder session, which itself requires physical or already-locally-paired access — see the on-device setup above.

Two things genuinely could let someone other than the phone's holder influence what happens right now, and `scripts/preflight-check.sh` checks for both, automatically, as non-blocking informational warnings:

```bash
rish scripts/preflight-check.sh
```

(`rish` is Shizuku's own bundled shell client: once Shizuku is running — see the on-device setup above — open Shizuku → **Use Shizuku in terminal apps** and follow its steps to authorize your terminal. After that, `rish` is a drop-in replacement for `sh`, so the command above works from Termux or any terminal app with no computer involved.)

- **Wireless debugging left on** — a standing local-network ADB surface, worth turning back off once Shizuku pairing is done.
- **A known remote-screen-control app installed** (TeamViewer, AnyDesk, AirDroid, etc.) — these let someone else literally drive the screen remotely. If you didn't install one yourself, worth a look.

Root My Pixel's own install flow runs the same two checks itself, but nothing here — neither the script nor the app — ever fails or blocks on MDM/Device Owner/Device Admin status. That status is intentionally not part of the trust decision.

---

## Building from Source

To compile the entire project (native helper, exploit payloads for all targets, and the final debug APK):

### Build Requirements
- Android NDK r25+ (`ANDROID_NDK_HOME` set or present in Android SDK)
- macOS (arm64/x86_64) or Linux (x86_64) host
- Java 17+ and Gradle Wrapper

### Build Command
```bash
./build-all.sh
```

The compiled APK will be generated at:
`app/build/outputs/apk/debug/app-debug.apk`

To install it on a connected device via ADB:
```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

---

## Building On-Device in Termux (ARM64 Pixel, No PC)

The "Build Requirements" above ("macOS arm64/x86_64 or Linux x86_64 host") describe every machine Google ships official Android build binaries for. **A Pixel running Termux is Linux *aarch64*, which isn't on that list** — `build-all.sh` run unmodified inside Termux will get past the NDK-detection check and then fail deep into the build with an "Exec format error," because both the **NDK's prebuilt `clang`** and the **Android SDK's `aapt2`/`d8`/`aidl`** binaries are x86_64-only (or Darwin-only) executables that the ARM64 Android kernel simply can't run. Knowing that up front, before you sink an hour into `./build-all.sh` on-device, saves the debugging cycle — the failure isn't a bug in this repo, it's a gap in Termux/Pixel's compatibility with Google's own tooling. Note `build-all.sh` now fails immediately with a pointer to this section instead of running into that dead end blind (see below).

There are two workable paths, in order of effort vs. purity:

### Path A — Native ARM64 (fast, no emulation)

Use Termux's own trusted, ARM64-native `clang`, and swap in ARM64 builds of the SDK's packaging tools.

1. `pkg update && pkg install openjdk-21 gradle git clang` — check `pkg search aapt2 d8 aidl` for Termux-packaged ARM64 builds of those three; if your Termux repo doesn't carry them, use a community ARM64 drop-in such as [commit451's android-arm-build-tools](https://android-arm-build-tools.commit451.com/).
2. Download the **official** Android NDK zip (the linux-x86_64 build is fine — you're not going to execute its `clang`, only reuse its data) and unpack it somewhere, e.g. `~/ndk/`. You only need the **sysroot** — the headers and precompiled `bionic`/`libc++` libraries under `toolchains/llvm/prebuilt/linux-x86_64/sysroot/` are architecture-independent data, not host-arch binaries, so they work regardless of which machine unpacked them.
3. Compile with Termux's own `clang`, pointed at that sysroot, instead of the NDK's `clang`:
   ```bash
   clang --target=aarch64-linux-android35 \
     --sysroot=~/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot \
     -fPIE -pie -O2 -Wall -Wextra \
     Root-My-Pixel-Payloads/src/su_daemon.c -ldl \
     -o app/src/main/jniLibs/arm64-v8a/libcve43499root.so
   ```
   (This replaces `build-all.sh` Step 1; the same substitution applies to `make -C Root-My-Pixel-Payloads` if you're also rebuilding an exploit payload — pass this `clang`+`--sysroot` combination through `CC`.)
4. For the `./gradlew assembleDebug` step, tell Gradle to use an ARM64 `aapt2` instead of the x86_64 one it would otherwise fetch from Maven (AGP 9+): add to `gradle.properties`
   ```properties
   android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2
   ```
   pointing at wherever your ARM64 `aapt2` actually landed, and restart the Gradle daemon (`./gradlew --stop`) after changing it.

### Path B — Emulated x86_64 (slower, closer to "official")

Run Google's real, unmodified SDK/NDK binaries under x86_64 emulation instead of substituting anything:

```bash
pkg install proot-distro
proot-distro install ubuntu
proot-distro login ubuntu
# inside the Ubuntu chroot:
apt update && apt install -y box64 openjdk-21-jdk unzip
# install the real Android cmdline-tools + NDK as you would on any x86_64 Linux box, then:
box64 ./gradlew assembleDebug
```
Compiles run noticeably slower under emulation, but every tool that executes is Google's own binary, unmodified — the strongest trust story of the two paths.

### Why this matters more than usual here

We just audited this repo and removed an unreferenced, unverifiable exploit binary that had been silently committed (see git history around `grizzly-CD1A.260618.001.C2.so`). Compiling a local-privilege-escalation payload is exactly the kind of build where the *provenance of your compiler* matters — don't grab a random precompiled "termux-ndk-aarch64" binary off GitHub to sidestep this. Path A only ever runs Termux's own package-manager-installed `clang` against Google's unmodified sysroot *data*; Path B runs Google's unmodified NDK/SDK binaries directly, just emulated. Either keeps every executable in the chain traceable back to a source you can verify; a stranger's rebuilt toolchain binary doesn't.

**Caveat:** this section describes the current (2026) community-documented workarounds for building Android apps in Termux on ARM64 — exact package names and NDK layout can drift between Termux/AGP/NDK releases, and it hasn't been exercised end-to-end against this specific project's build (Compose + Koin + CMake) in a live Termux session. Treat it as a verified starting point, not a guarantee; if a step doesn't match what you see, that's the drift, not user error.

---

## Credits

- Exploit: [NebuSec IonStack](https://github.com/NebuSec/CyberMeowfia)
- App architecture: Inspired and adapted from [Root My Galaxy](https://github.com/BuSung-dev/Root-My-Galaxy)
- ReSukiSU (https://github.com/ReSukiSU/ReSukiSU)
