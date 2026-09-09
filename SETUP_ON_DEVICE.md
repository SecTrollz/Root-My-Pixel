# On-Device KernelSU Setup (No Computer Needed)

This guide walks you through using `root_my_pixel.py` to get persistent KernelSU root on your Pixel device, entirely on-phone, with no PC required.

## Prerequisites

1. **Shizuku** installed and running via Wireless Debugging (see [README.md](README.md) for on-device setup)
2. **Python 3** available (usually via Termux or via Shizuku's built-in shell)
3. This repository cloned to `/sdcard/` or accessible to your shell

## Step 1: Clone This Repo (One-Time)

If you haven't already, clone the Root-My-Pixel repo to your phone:

```bash
# Via Termux:
cd ~
git clone https://github.com/SecTrollz/Root-My-Pixel.git
cd Root-My-Pixel
```

Or download as ZIP and extract to `/sdcard/Download/Root-My-Pixel/`.

## Step 2: Run the Setup Script

### Option A: Via Shizuku Shell (Recommended — Full ADB Privileges)

```bash
# In Termux or any terminal app:
rish python3 ~/Root-My-Pixel/root_my_pixel.py
```

**Why Shizuku?** It runs as UID 2000 with ADB shell privileges, so the exploit can stage binaries to `/data/local/tmp/` without needing root yet.

### Option B: Via Termux (If Shizuku Not Available)

```bash
# In Termux:
python3 ~/Root-My-Pixel/root_my_pixel.py
```

This should also work, but Shizuku is more reliable for the exploit execution.

## Step 3: What the Script Does

When you run it, the script will:

1. **Detect your device**
   - Reads codename, kernel version, build ID from `getprop`
   - Shows you what was detected

2. **Match against profiles**
   - Looks up your device in `profiles.json`
   - Shows the profile ID and exploit binary that will be used
   - **Allows you to review before proceeding**

3. **Ask for confirmation**
   - Lists the exact exploit `.so` file
   - Asks "Ready to execute exploit?" — say `y` to continue

4. **Run the exploit**
   - Executes CVE-2026-43499 to get temporary root
   - Monitors for success markers (`done=1 root=1`)
   - Watches for stalls/timeouts

5. **Install KernelSU**
   - Stages the `ksud` binary
   - Runs `ksud late-load --kmi <kmi>`
   - Waits for kernel module to load
   - Sets SELinux to permissive
   - Tests that root access works

6. **Cleanup**
   - Removes exploit binaries (no longer needed)
   - Leaves only KernelSU kernel module in place

7. **Verification**
   - Confirms `/dev/kernelsu` or `/sys/kernel/kernelsu` exists
   - Confirms `/data/adb/ksu` directory is set up
   - Reports success

## Step 4: Grant Root to Apps (After Setup)

Once the script succeeds:

1. **Open ReSukiSU Manager**
2. You'll see "Kernel SU" at the top (blue)
3. Go to **Super User** or **Apps**
4. Grant root to:
   - **Termux** (if using Termux shell)
   - **adb** (to use `adb shell` with root)
   - Any other apps you want root access in

## Troubleshooting

### "No profile found for \<device\> / \<kernel\>"

Your device isn't in the supported list. Check:
- Is your Pixel in the [README.md](README.md) device table?
- Run the script again and note the exact codename and kernel version shown
- Post an issue with that info

### "Exploit failed (non-zero exit)"

Check the exploit log:
```bash
cat /data/local/tmp/exploit.log
```

Common causes:
- **Device/kernel mismatch** — The `.so` binary doesn't match your kernel offsets
  - Verify the profile that was matched is correct for your device
  - If wrong, check your device codename via `getprop ro.product.device`

- **Kernel too different** — Even same device, different build might have different offsets
  - Check `getprop ro.build.display.id` and confirm it matches profiles.json

- **Memory-related** — Rare; try rebooting and running again

### "KernelSU module verification timeout"

The `ksud late-load` didn't load the kernel module. Try:

```bash
# Via Shizuku shell:
rish /data/local/tmp/ksud-pixel late-load --kmi android14-6.1
```

(Replace `android14-6.1` with the KMI shown in the script output.)

If that fails, the kernel might not support KernelSU for your device/build.

### "Root test inconclusive"

The script's root test might fail for permission reasons, but root could still work. Open ReSukiSU Manager and try granting root to Termux, then run:

```bash
su -c 'id'
```

If that returns `uid=0`, root is working.

## Using Root (After Setup)

### Via Termux

Grant Termux root in ReSukiSU Manager, then:

```bash
su
# You're now root
id  # uid=0
```

### Via adb (PC Required for This Step)

If you want to use `adb shell` with root:

1. Grant `adb` root in ReSukiSU Manager
2. From your PC:
   ```bash
   adb shell
   su
   id  # uid=0
   ```

### Via Python/Scripts

You can call system commands with root:

```python
import subprocess

# This will use KernelSU to run as root
result = subprocess.run(
    "su -c 'id'",
    shell=True,
    capture_output=True,
    text=True
)
print(result.stdout)  # uid=0(root) gid=0(root) groups=0(root)
```

## Safety Notes

- **No Internet Access** — The script has no network code; it can't be remotely triggered
- **On-Device Only** — No data leaves your phone
- **One-Way Exploit** — Once root is set up via KernelSU, the temporary CVE root is cleaned up
- **SELinux Permissive** — KernelSU works better in permissive mode; you can change it back with `setenforce 1` (but KernelSU might be less stable)

## Uninstalling Root

To remove KernelSU and go back to stock (if needed):

```bash
# Via Termux with root:
su -c 'rm -rf /data/adb/ksu'
su -c 'setenforce 1'  # Restore SELinux enforcing
reboot
```

Then the kernel module will unload on next boot.

## Next Steps

- Read [README.md](README.md) for more context on how Root My Pixel works
- Check [Root-My-Pixel-Payloads](https://github.com/alex193a/Root-My-Pixel-Payloads) for exploit details
- Join discussions about KernelSU at https://github.com/tiann/KernelSU

---

**This script automates what the Android app does, but on your phone with full transparency. Every step is shown, every command is logged, and you approve critical actions before they run.**
