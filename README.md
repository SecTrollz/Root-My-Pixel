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

## Supported Devices & Build Profiles

| Device                | Codename   | Supported Builds   | Kernel KMI      | Tested |
|:----------------------|:-----------|:------------------|:----------------|:--------|
| **Pixel 10**          | `frankel`  | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro**      | `blazer`   | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro XL**   | `mustang`  | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10 Pro Fold** | `rango`    | `CP2A.260705.006` | `android15-6.6` | ✅      |
| **Pixel 10a**         | `stallion` | `CP2A.260805.005` | `android14-6.1` | ✅      |
| **Pixel 9 Pro Fold**  | `comet`    | `CP2A.260705.006` | `android15-6.1` | ✅      |
| **Pixel 9 Pro**       | `caiman`   | `CP2A.260705.006` | `android15-6.1` | ✅      |
| **Pixel 9 Pro XL**    | `komodo`   | `CP2A.260705.006` | `android15-6.1` | ✅      |
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

## Credits

- Exploit: [NebuSec IonStack](https://github.com/NebuSec/CyberMeowfia)
- App architecture: Inspired and adapted from [Root My Galaxy](https://github.com/BuSung-dev/Root-My-Galaxy)
- ReSukiSU (https://github.com/ReSukiSU/ReSukiSU)
