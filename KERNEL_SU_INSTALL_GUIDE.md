# KernelSU Installation — Self-Contained Script

**File:** `kernel_su_install.sh` (6.6 MB)

This is a complete, self-contained shell script for installing persistent KernelSU root on your Pixel device. All payloads are embedded directly in the script — **no network, no APK extraction, no external files needed**. Just copy and run.

## Supported Devices

Tested and ready for:
- **Pixel 9a (tegu)** — CP2A.260705.006, kernel 6.1.157

Also supports: panther, lynx, mustang (with appropriate builds)

## Quick Start

### Step 1: Copy Script to Your Phone

```bash
# From your computer:
adb push kernel_su_install.sh /sdcard/
```

Or manually:
1. Download `kernel_su_install.sh` to your computer
2. Use `adb push` or file manager to copy it to `/sdcard/`

### Step 2: Run via Shizuku

**Requirements:**
- Shizuku app installed and running (via Wireless ADB Debugging)
- `rish` command available

**Execution:**

Option A — Direct command:
```bash
rish sh /sdcard/kernel_su_install.sh
```

Option B — Interactive shell:
```bash
rish
# Inside rish shell:
cd /sdcard
sh kernel_su_install.sh
```

### Step 3: Approve and Monitor

1. Script detects your device (shows device name, kernel, build ID)
2. Verifies the profile is correct
3. Asks: `>>> Continue? [y/n]:` — Type **y** and press Enter
4. Extracts payloads from embedded base64 data
5. Asks: `>>> Ready to execute exploit? [y/n]:` — Type **y** again
6. Runs the CVE-2026-43499 exploit
7. Waits for completion (shows progress)
8. Installs KernelSU via late-load
9. Reports success

### Step 4: Grant Root to Apps

Once installation completes:

1. Open **ReSukiSU Manager** app
2. Go to **Super User** tab
3. Grant root to:
   - **Termux** (if using Termux shell)
   - **adb** (if using adb shell from PC)
   - Other apps as needed

### Step 5: Verify Root Works

```bash
# In Termux (or adb shell with root grant):
su -c 'id'
# Should return: uid=0(root) gid=0(root) groups=0(root)
```

## What the Script Does

1. **Device Detection** — Reads device codename, kernel version, build ID via `getprop`
2. **Profile Matching** — Verifies your device/kernel combo has a known exploit binary
3. **Payload Extraction** — Decodes embedded base64 payloads into temporary binaries:
   - Helper binary (libcve43499root.so)
   - Exploit binary (tegu-CP2A.260705.006.so)
   - ksud daemon
4. **Exploit Execution** — Runs CVE-2026-43499 to gain temporary root
5. **KernelSU Installation** — Installs persistent KernelSU kernel module
   - Creates `/data/adb/ksu` directory
   - Sets SELinux to permissive mode (KernelSU requirement)
   - Runs `ksud late-load --kmi <version>`
   - Waits for module to load
6. **Verification** — Checks that `/dev/kernelsu` exists
7. **Cleanup** — Removes temporary exploit binaries (keeps only KernelSU kernel module)

## Troubleshooting

### "Device not supported"

Your device/build combination isn't in the hardcoded profiles. This script is built for **tegu (Pixel 9a) with CP2A.260705.006**. For other devices, you need a different exploit binary.

### "Exploit failed"

The exploit either failed to execute or timed out. Check:

1. **Is your device actually tegu?**
   ```bash
   getprop ro.product.device
   ```
   Should return: `tegu`

2. **Is the kernel 6.1.157?**
   ```bash
   cat /proc/version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'
   ```

3. **Is the build correct?**
   ```bash
   getprop ro.build.display.id
   ```
   Should be: `CP2A.260705.006`

If any of these don't match, this script won't work for your specific device variant.

### "KernelSU verification inconclusive"

This warning is OK — the module might still be loading. Wait 5-10 seconds and try:

```bash
rish su -c 'id'
```

If that shows `uid=0`, root is working.

### Script crashes or freezes

The exploit has a 30-minute timeout. If it hangs longer than that, it will kill itself. Otherwise:

1. Try rebooting your device
2. Run the script again
3. The exploit might need a fresh device state

## What Gets Installed

- **KernelSU kernel module** — Loaded at boot, provides persistent root
- **ksud daemon** — Manages root permissions and app grants
- **/data/adb/ksu/** — Configuration and log directory

## What Gets Cleaned Up

- Helper binary (no longer needed after exploit)
- Exploit binary (one-time use, temporary root)
- Exploit logs

## What's NOT Installed

- The Root My Pixel app (not needed after this)
- Temporary files (cleaned up automatically)

## Safety Notes

1. **Self-contained** — All code and binaries are in this one script
2. **No network calls** — Cannot be remotely triggered
3. **Transparent** — Every step is logged with timestamps
4. **One-time** — The exploit is extracted, used once, and deleted
5. **Persistent** — KernelSU survives reboots (unlike temporary root)

## After Root: Using It

### Via Termux Shell

Grant Termux root in ReSukiSU Manager, then:

```bash
su
# Now you're root
id
```

### Via adb Shell (from PC)

```bash
# Grant adb root in ReSukiSU Manager first
adb shell
su -c 'id'
```

### Via Python/Scripts

```python
import subprocess
result = subprocess.run("su -c 'id'", shell=True, capture_output=True, text=True)
print(result.stdout)  # uid=0(root) gid=0(root) groups=0(root)
```

## Uninstalling Root

If you need to remove KernelSU:

```bash
# Via Termux with root:
su -c 'rm -rf /data/adb/ksu'
su -c 'setenforce 1'  # Restore SELinux enforcing
reboot
```

Then the kernel module will be gone on next boot.

## Questions?

- Check the [main README.md](README.md) for more on Root My Pixel
- See [original project](https://github.com/alex193a/Root-My-Pixel) for exploit details
- Join discussions at [KernelSU GitHub](https://github.com/tiann/KernelSU)

---

**This script provides complete transparency. Every command is shown, every step is logged. You control when the exploit runs. No background processes, no hidden operations.**
