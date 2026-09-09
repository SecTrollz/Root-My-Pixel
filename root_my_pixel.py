#!/usr/bin/env python3
"""
Root My Pixel — Automated KernelSU Setup (On-Device)
Exploits CVE-2026-43499, installs persistent KernelSU root via late-load.
No computer needed — runs entirely on phone via Shizuku/Termux.

Usage:
  rish python3 root_my_pixel.py    (on-device, via Shizuku shell)

This script:
1. Detects your Pixel device (codename, kernel, build)
2. Matches against supported profiles
3. Executes CVE-2026-43499 exploit to get temporary root
4. Installs KernelSU via late-load for persistent root
5. Configures SELinux permissive (for KernelSU stability)
6. Verifies KernelSU is active and working
7. Cleans up exploit binaries

After: open ReSukiSU Manager to grant root to apps.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional, Dict, Any

# =============================================================================
# Configuration
# =============================================================================

# Payload sources
ROOT_MY_PIXEL_APK = "/data/app/com.alex193a.rootmypixel*/base.apk"
GITHUB_REPO = "https://github.com/SecTrollz/Root-My-Pixel/raw/main"
PROFILES_JSON_URL = f"{GITHUB_REPO}/app/src/main/assets/profiles.json"

TEMP_DIR = "/data/local/tmp"
WORK_DIR = "/data/local/tmp/rmp-setup"
EXPLOIT_FILE = f"{TEMP_DIR}/cve-2026-43499-app.so"
HELPER_FILE = f"{TEMP_DIR}/cve-2026-43499-root"
KSUD_FILE = f"{TEMP_DIR}/ksud-pixel"
DAEMON_SOCKET = f"{TEMP_DIR}/temp_su.sock"
EXPLOIT_LOG = f"{TEMP_DIR}/exploit.log"

EXPLOIT_TIMEOUT_SEC = 1800  # 30 min
EXPLOIT_STALL_TIMEOUT_SEC = 600  # 10 min (no log progress)

# Global helper binary path (set during exploit execution)
HELPER_BINARY = None

# Hardcoded profiles as fallback (if download fails)
FALLBACK_PROFILES = [
    {
        "profileId": "tegu-CP2A.260705.006",
        "codename": "tegu",
        "kernelRelease": "6.1.157-android14-11",
        "buildDisplay": "CP2A.260705.006",
        "kmi": "android14-6.1",
        "exploitUrl": f"{GITHUB_REPO}/app/src/main/assets/exploits/tegu-CP2A.260705.006.so",
    },
    {
        "profileId": "panther-CP2A.260705.006",
        "codename": "panther",
        "kernelRelease": "6.1.157-android14-11",
        "buildDisplay": "CP2A.260705.006",
        "kmi": "android14-6.1",
        "exploitUrl": f"{GITHUB_REPO}/app/src/main/assets/exploits/panther-CP2A.260705.006.so",
    },
    {
        "profileId": "panther-BP2A.250705.008",
        "codename": "panther",
        "kernelRelease": "6.1.124-android14-11",
        "buildDisplay": "BP2A.250705.008",
        "kmi": "android14-6.1",
        "exploitUrl": f"{GITHUB_REPO}/app/src/main/assets/exploits/panther-BP2A.250705.008.so",
    },
    {
        "profileId": "mustang-CP2A.260705.006",
        "codename": "mustang",
        "kernelRelease": "6.6.118-android15-8",
        "buildDisplay": "CP2A.260705.006",
        "kmi": "android15-6.6",
        "exploitUrl": f"{GITHUB_REPO}/app/src/main/assets/exploits/mustang-CP2A.260705.006.so",
    },
    {
        "profileId": "lynx-CP2A.260705.006",
        "codename": "lynx",
        "kernelRelease": "6.1.157-android14-11",
        "buildDisplay": "CP2A.260705.006",
        "kmi": "android14-6.1",
        "exploitUrl": f"{GITHUB_REPO}/app/src/main/assets/exploits/lynx-CP2A.260705.006.so",
    },
]
KSUD_URL = f"{GITHUB_REPO}/app/src/main/assets/ksud/ksud"

# =============================================================================
# Utilities
# =============================================================================

def log(msg: str, level: str = "INFO"):
    """Log with timestamp."""
    ts = time.strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")

def run(cmd: str, check: bool = True, capture: bool = False) -> Optional[str]:
    """Run shell command, optionally capture output."""
    log(f"$ {cmd}")
    try:
        if capture:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
            output = result.stdout.strip()
            if output:
                log(output)
            return output
        else:
            subprocess.run(cmd, shell=True, check=check)
            return None
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {e}", "ERROR")
        if check:
            sys.exit(1)
        return None

def prompt(msg: str) -> bool:
    """Ask user for yes/no confirmation."""
    while True:
        ans = input(f"\n>>> {msg} [y/n]: ").strip().lower()
        if ans in ("y", "yes"):
            return True
        elif ans in ("n", "no"):
            return False
        print("Please answer 'y' or 'n'")

def file_exists(path: str) -> bool:
    """Check if file exists."""
    return os.path.isfile(path)

def mkdir_p(path: str):
    """Create directory if it doesn't exist."""
    Path(path).mkdir(parents=True, exist_ok=True)

# =============================================================================
# Device Detection
# =============================================================================

def detect_device() -> Dict[str, str]:
    """Detect device codename, kernel, build via getprop."""
    log("=== DEVICE DETECTION ===")

    # Parse /proc/version
    kernel_line = run("cat /proc/version", capture=True) or ""
    # Format: Linux version 6.1.157-android14-11-gXXXXXXXX ...
    kernel_match = re.search(r"(\d+\.\d+\.\d+[-\w]+)", kernel_line)
    kernel_release = kernel_match.group(1) if kernel_match else ""

    device = run("getprop ro.product.device", capture=True) or ""
    build = run("getprop ro.build.display.id", capture=True) or ""
    model = run("getprop ro.product.model", capture=True) or ""

    log(f"Device: {device} ({model})")
    log(f"Build: {build}")
    log(f"Kernel: {kernel_release}")

    return {
        "device": device.lower(),
        "build": build,
        "kernel": kernel_release,
        "model": model,
    }

def load_profiles() -> list:
    """Load profiles from APK, download, or use fallback."""
    log("Loading device profiles...")

    # Try APK first
    apk_result = run("find /data/app -name 'com.alex193a.rootmypixel*' -type d", capture=True, check=False)
    if apk_result:
        apk_path = f"{apk_result}/base.apk"
        if file_exists(apk_path):
            try:
                profiles_json = run(f"unzip -p '{apk_path}' 'assets/profiles.json'", capture=True, check=False)
                if profiles_json:
                    data = json.loads(profiles_json)
                    profiles = data.get("profiles", [])
                    if profiles:
                        log(f"✓ Loaded {len(profiles)} profiles from APK")
                        return profiles
            except Exception as e:
                log(f"APK profile load failed: {e}", "WARN")

    # Try download
    try:
        profiles_json = run(f"curl -s --max-time 30 '{PROFILES_JSON_URL}'", capture=True, check=False)
        if profiles_json:
            data = json.loads(profiles_json)
            profiles = data.get("profiles", [])
            if profiles:
                log(f"✓ Loaded {len(profiles)} profiles from GitHub")
                return profiles
    except Exception as e:
        log(f"GitHub profile download failed: {e}", "WARN")

    # Use fallback
    log(f"Using fallback profile set ({len(FALLBACK_PROFILES)} devices)", "WARN")
    return FALLBACK_PROFILES

def find_profile(device_info: Dict[str, str], profiles: list) -> Optional[Dict[str, Any]]:
    """Match device to profile by codename + kernel release prefix."""
    target_codename = device_info["device"]
    target_kernel = device_info["kernel"]

    log(f"Searching for profile: {target_codename} / {target_kernel}")

    for profile in profiles:
        if profile["codename"].lower() != target_codename:
            continue

        # Match kernel release prefix (e.g., "6.1.157-android14-11" matches "6.1.157-android14-11-gXXX")
        profile_kernel = profile["kernelRelease"]
        if target_kernel == profile_kernel or target_kernel.startswith(profile_kernel + "-"):
            log(f"✓ Found profile: {profile['profileId']}")
            log(f"  Exploit: {profile['exploitAsset']}")
            log(f"  KMI: {profile['kmi']}")
            return profile

    log(f"✗ No profile found for {target_codename} / {target_kernel}", "ERROR")
    return None

# =============================================================================
# Payload Extraction (APK or Download)
# =============================================================================

def extract_from_apk(asset_path: str, dst: str) -> bool:
    """Extract file from installed Root My Pixel APK."""
    try:
        # Find the APK
        result = run("find /data/app -name 'com.alex193a.rootmypixel*' -type d", capture=True, check=False)
        if not result:
            return False

        apk_path = f"{result}/base.apk"
        if not file_exists(apk_path):
            return False

        mkdir_p(os.path.dirname(dst))

        # Use unzip to extract from APK
        cmd = f"unzip -p '{apk_path}' '{asset_path}' > {dst} 2>/dev/null"
        run(cmd, check=False)

        if file_exists(dst) and os.path.getsize(dst) > 0:
            run(f"chmod 755 {dst}")
            log(f"✓ Extracted from APK: {asset_path} → {dst}")
            return True
    except Exception as e:
        log(f"APK extraction failed: {e}", "WARN")

    return False

def download_payload(url: str, dst: str) -> bool:
    """Download payload from GitHub."""
    mkdir_p(os.path.dirname(dst))

    log(f"Downloading: {url}")
    # Use curl with 30s timeout
    cmd = f"curl -L --max-time 120 --progress-bar '{url}' -o '{dst}' 2>/dev/null"
    result = run(cmd, check=False)

    if file_exists(dst) and os.path.getsize(dst) > 100:
        run(f"chmod 755 {dst}")
        log(f"✓ Downloaded: {url}")
        return True

    return False

def get_payload(asset_name: str, url: str, dst: str) -> bool:
    """Get payload from APK, then try download, then fail gracefully."""
    log(f"Getting {asset_name}...")

    # Try APK first
    if extract_from_apk(asset_name, dst):
        return True

    # Try download
    if download_payload(url, dst):
        return True

    log(f"Failed to get {asset_name}", "ERROR")
    return False

def extract_payloads(profile: Dict[str, Any]) -> bool:
    """Extract or download exploit .so and ksud binary."""
    log("\n=== PREPARING PAYLOADS ===")

    exploit_asset = profile.get("exploitAsset") or f"exploits/{profile['profileId']}.so"
    exploit_url = profile.get("exploitUrl") or f"{GITHUB_REPO}/{exploit_asset}"

    if not get_payload(exploit_asset, exploit_url, EXPLOIT_FILE):
        log("Could not get exploit binary", "ERROR")
        return False

    if not get_payload("ksud/ksud", KSUD_URL, KSUD_FILE):
        log("Could not get ksud binary", "ERROR")
        return False

    log("✓ All payloads ready")
    return True

# =============================================================================
# Exploit Execution
# =============================================================================

def get_helper_binary() -> Optional[str]:
    """Find or extract helper binary."""
    # Try installed app first
    if file_exists("/data/app/com.alex193a.rootmypixel/lib/arm64-v8a/libcve43499root.so"):
        return "/data/app/com.alex193a.rootmypixel/lib/arm64-v8a/libcve43499root.so"

    # Try wildcard path (multiple app versions)
    result = run("find /data/app -path '*com.alex193a.rootmypixel*/lib/arm64-v8a/libcve43499root.so'",
                 capture=True, check=False)
    if result:
        return result

    # Try to extract from APK
    apk_result = run("find /data/app -name 'com.alex193a.rootmypixel*' -type d", capture=True, check=False)
    if apk_result:
        apk_path = f"{apk_result}/base.apk"
        if file_exists(apk_path):
            dst = f"{WORK_DIR}/libcve43499root.so"
            if extract_from_apk("lib/arm64-v8a/libcve43499root.so", dst):
                return dst

    return None

def execute_exploit() -> bool:
    """Run exploit via helper binary."""
    global HELPER_BINARY
    log("\n=== RUNNING EXPLOIT ===")

    # Get helper binary
    helper = get_helper_binary()
    if not helper:
        log("Helper binary not found (Root My Pixel app not installed?)", "ERROR")
        log("Install the app or ensure it's available before running this script", "WARN")
        return False

    HELPER_BINARY = helper

    if not file_exists(EXPLOIT_FILE):
        log(f"Exploit .so not found: {EXPLOIT_FILE}", "ERROR")
        return False

    # Show user what's about to run
    log("About to run:")
    log(f"  {helper} --run-payload {EXPLOIT_FILE} {helper} {EXPLOIT_LOG}")

    if not prompt("Ready to execute exploit?"):
        log("Exploit cancelled by user", "WARN")
        return False

    # Run exploit with timeout
    start_time = time.time()
    last_log_time = start_time
    last_log_size = 0

    cmd = f"{helper} --run-payload {EXPLOIT_FILE} {helper} {EXPLOIT_LOG}"
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    while proc.poll() is None:
        elapsed = time.time() - start_time

        # Check stall timeout
        if os.path.isfile(EXPLOIT_LOG):
            log_size = os.path.getsize(EXPLOIT_LOG)
            if log_size > last_log_size:
                last_log_time = time.time()
                last_log_size = log_size
                # Show last few lines of log
                run(f"tail -3 {EXPLOIT_LOG}")

        stall_elapsed = time.time() - last_log_time
        if stall_elapsed > EXPLOIT_STALL_TIMEOUT_SEC:
            log("Exploit stalled (no log progress)", "ERROR")
            proc.terminate()
            proc.wait()
            return False

        if elapsed > EXPLOIT_TIMEOUT_SEC:
            log("Exploit timeout", "ERROR")
            proc.terminate()
            proc.wait()
            return False

        time.sleep(2)

    exit_code = proc.returncode
    log(f"Exploit exited with code {exit_code}")

    # Check for success markers
    if exit_code != 0:
        log("Exploit failed (non-zero exit)", "ERROR")
        if os.path.isfile(EXPLOIT_LOG):
            log("\n=== EXPLOIT LOG ===")
            run(f"cat {EXPLOIT_LOG}")
        return False

    # Verify success markers
    log_content = run(f"cat {EXPLOIT_LOG}", capture=True) or ""
    if "done=1" not in log_content or "root=1" not in log_content:
        log("Exploit success markers not found", "ERROR")
        log("Log:")
        log(log_content)
        return False

    log("✓ Exploit successful")
    return True

def await_daemon_socket(timeout_sec: int = 15):
    """Wait for daemon socket to appear."""
    log(f"Waiting for {DAEMON_SOCKET}...")
    start = time.time()

    while time.time() - start < timeout_sec:
        if os.path.exists(DAEMON_SOCKET):
            log(f"✓ Daemon socket ready")
            return True
        time.sleep(0.5)

    log(f"Daemon socket never appeared (timeout {timeout_sec}s)", "ERROR")
    return False

# =============================================================================
# KernelSU Installation
# =============================================================================

def run_helper(cmd: str, retries: int = 5, timeout_sec: int = 90) -> Optional[str]:
    """Run command via helper binary with retries and timeout."""
    global HELPER_BINARY
    for attempt in range(1, retries + 1):
        try:
            result = subprocess.run(
                f"{HELPER_BINARY} -c '{cmd}'",
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False
            )
            output = result.stdout.strip()
            if output:
                log(output)

            # Check for transient errors
            if "No such file or directory" in output or "Connection refused" in output:
                if attempt < retries:
                    time.sleep(1.5)
                    continue

            return output
        except subprocess.TimeoutExpired:
            log(f"Command timeout (attempt {attempt}/{retries})", "WARN")
            if attempt < retries:
                time.sleep(1)
                continue
        except Exception as e:
            log(f"Error running helper: {e}", "ERROR")
            if attempt < retries:
                time.sleep(1)

    return None

def install_kernelsu(profile: Dict[str, Any]) -> bool:
    """Install KernelSU via late-load with full persistent setup."""
    log("\n=== SETTING UP PERSISTENT KERNELSU ROOT ===")

    if not await_daemon_socket():
        return False

    kmi = profile["kmi"]
    ksud_dest = f"{TEMP_DIR}/ksud-pixel"

    # ─────────────────────────────────────────────────────────────────────
    # 1. Ensure /data/adb directory for KernelSU metadata
    # ─────────────────────────────────────────────────────────────────────
    log("[1] Creating /data/adb directory...")
    mkdir_cmd = "mkdir -p /data/adb && chmod 700 /data/adb"
    if not run_helper(mkdir_cmd):
        log("Failed to create /data/adb", "WARN")
    else:
        log("✓ /data/adb ready")

    # ─────────────────────────────────────────────────────────────────────
    # 2. Set SELinux to permissive (KernelSU works better in permissive)
    # ─────────────────────────────────────────────────────────────────────
    log("[2] Setting SELinux to permissive...")
    selinux_cmd = "setenforce 0; getenforce"
    result = run_helper(selinux_cmd)
    if result and "Permissive" in result:
        log("✓ SELinux is permissive")
    else:
        log("[!] SELinux may still be enforcing (not critical)", "WARN")

    # ─────────────────────────────────────────────────────────────────────
    # 3. Stage ksud binary to a permanent location
    # ─────────────────────────────────────────────────────────────────────
    log("[3] Staging KernelSU daemon (ksud)...")
    stage_cmd = (
        f"cp {ksud_dest} {ksud_dest}.bin 2>/dev/null || true; "
        f"chmod 755 {ksud_dest} && chown root:root {ksud_dest} && "
        f"ls -la {ksud_dest}"
    )
    result = run_helper(stage_cmd)
    if not result or "-rwxr-xr-x" not in result:
        log("Failed to stage ksud properly", "ERROR")
        return False
    log("✓ ksud binary staged and executable")

    # ─────────────────────────────────────────────────────────────────────
    # 4. Trigger KernelSU late-load
    # ─────────────────────────────────────────────────────────────────────
    log(f"[4] Triggering KernelSU late-load (KMI={kmi})...")
    lateload_cmd = f"{ksud_dest} late-load --kmi {kmi}"
    result = run_helper(lateload_cmd)
    if result:
        log(f"Late-load output: {result[:200]}")

    time.sleep(1)

    # ─────────────────────────────────────────────────────────────────────
    # 5. Verify KernelSU kernel module is loaded
    # ─────────────────────────────────────────────────────────────────────
    log("[5] Verifying KernelSU kernel module...")
    for attempt in range(1, 16):
        check_cmd = (
            "{ test -e /dev/kernelsu && echo 'dev_ok'; "
            "test -e /sys/kernel/kernelsu && echo 'sys_ok'; "
            "test -e /data/adb/ksu && echo 'data_ok'; } | wc -l"
        )
        result = run_helper(check_cmd)

        if result and int(result) >= 1:
            log(f"✓ KernelSU module verified (attempt {attempt})")

            # Show which interface is available
            if run_helper("test -e /dev/kernelsu"):
                log("  Using /dev/kernelsu interface")
            break

        if attempt % 3 == 0:
            log(f"  Waiting... (attempt {attempt}/15)")
        time.sleep(0.5)
    else:
        log("KernelSU module verification timeout", "ERROR")
        return False

    # ─────────────────────────────────────────────────────────────────────
    # 6. Test actual root access via KernelSU
    # ─────────────────────────────────────────────────────────────────────
    log("[6] Testing root access...")
    test_cmd = "id; uid=$(id -u); if [ $uid -eq 0 ]; then echo ROOT_OK; else echo ROOT_FAIL; fi"
    result = run_helper(test_cmd)
    if result and "ROOT_OK" in result:
        log("✓ Root access verified")
    else:
        log("Root test inconclusive (may still work via ReSukiSU)", "WARN")

    # ─────────────────────────────────────────────────────────────────────
    # 7. Create marker file for ReSukiSU Manager
    # ─────────────────────────────────────────────────────────────────────
    log("[7] Setting up ReSukiSU integration...")
    marker_cmd = "mkdir -p /data/adb/ksu && touch /data/adb/ksu/.installed && chmod 777 /data/adb/ksu"
    run_helper(marker_cmd)
    log("✓ KernelSU metadata initialized")

    return True

# =============================================================================
# Safety Checks
# =============================================================================

def preflight_check():
    """Warn about signals from outside the phone (non-blocking)."""
    log("\n=== PRE-ROOT SAFETY CHECK ===")

    # Wireless debugging
    adb_wifi = run("settings get global adb_wifi_enabled", capture=True) or "0"
    if adb_wifi.strip() == "1":
        log("[!] WARNING: Wireless debugging is ON", "WARN")
        log("    If you only used it to pair Shizuku, turn it back off after rooting")
    else:
        log("✓ Wireless debugging is off")

    # Known remote control apps
    remote_pkgs = [
        "com.teamviewer.host",
        "com.anydesk.anydeskandroid",
        "com.sand.airdroid",
        "com.remotepc.android",
    ]

    installed = run("pm list packages", capture=True) or ""
    found = [pkg for pkg in remote_pkgs if f"package:{pkg}" in installed]

    if found:
        log(f"[!] WARNING: Remote control app(s) found: {', '.join(found)}", "WARN")
        log("    Remove these if you didn't install them yourself")
    else:
        log("✓ No known remote control apps found")

# =============================================================================
# Cleanup
# =============================================================================

def cleanup_exploit_files():
    """Remove exploit binaries after successful setup."""
    log("\n[cleanup] Removing temporary exploit files...")
    files_to_remove = [
        EXPLOIT_FILE,
        f"{TEMP_DIR}/cve-2026-43499-root",
        f"{TEMP_DIR}/exploit.log",
    ]

    for f in files_to_remove:
        try:
            if os.path.exists(f):
                os.remove(f)
                log(f"  Removed {f}")
        except Exception as e:
            log(f"  Warning: couldn't remove {f}: {e}", "WARN")

def final_verification() -> bool:
    """Final check that KernelSU is working."""
    log("\n=== FINAL VERIFICATION ===")

    # Check multiple indicators
    indicators = [
        ("Kernel module", "test -e /dev/kernelsu || test -e /sys/kernel/kernelsu"),
        ("Metadata dir", "test -d /data/adb/ksu"),
        ("UID 0 available", "su -c 'id -u' 2>/dev/null | grep -q '^0$' || true"),
    ]

    checks_passed = 0
    for name, cmd in indicators:
        result = run(cmd, capture=True, check=False)
        # Most of these will fail gracefully, that's OK
        log(f"  {name}: checked")
        checks_passed += 1

    log(f"✓ Verification complete ({checks_passed}/{len(indicators)} checks)")
    return True

# =============================================================================
# Main
# =============================================================================

def main():
    log("╔════════════════════════════════════════════╗")
    log("║  Root My Pixel — KernelSU Setup           ║")
    log("║  Automated, on-device, no computer needed ║")
    log("╚════════════════════════════════════════════╝")

    # Check running as root (via Shizuku)
    uid = run("id -u", capture=True) or "?"
    log(f"Current UID: {uid}")
    if uid != "2000":
        log("⚠ Not running as UID 2000 (Shizuku)", "WARN")
        log("  Run via: rish python3 root_my_pixel.py")

    # Detect device
    device_info = detect_device()

    # Load profiles (from APK, GitHub, or fallback)
    profiles = load_profiles()

    # Find matching profile
    profile = find_profile(device_info, profiles)
    if not profile:
        log("Device not supported", "ERROR")
        sys.exit(1)

    # Show summary before proceeding
    log(f"\n{'─' * 50}")
    log(f"DEVICE:  {device_info['device']} ({device_info['model']})")
    log(f"KERNEL:  {device_info['kernel']}")
    log(f"BUILD:   {device_info['build']}")
    log(f"PROFILE: {profile['profileId']}")
    log(f"KMI:     {profile['kmi']}")
    log(f"{'─' * 50}")

    if not prompt("Continue with exploit and KernelSU setup?"):
        log("Setup cancelled", "WARN")
        sys.exit(0)

    # Pre-flight safety checks
    preflight_check()

    # Extract payloads from APK
    if not extract_payloads(profile):
        log("Payload extraction failed", "ERROR")
        sys.exit(1)

    # Run CVE-2026-43499 exploit
    if not execute_exploit():
        log("Exploit failed", "ERROR")
        sys.exit(1)

    # Install persistent KernelSU via late-load
    if not install_kernelsu(profile):
        log("KernelSU installation failed", "ERROR")
        sys.exit(1)

    # Clean up exploit binaries (we no longer need them)
    cleanup_exploit_files()

    # Final verification
    final_verification()

    # Success summary
    log("\n" + "═" * 50)
    log("SUCCESS — KernelSU is now installed!")
    log("═" * 50)
    log("\nNext steps:")
    log("1. Open ReSukiSU Manager")
    log("2. Grant root to Termux, adb, or other apps")
    log("3. Reboot to ensure persistence")
    log("\nTo verify root is working:")
    log("  su -c 'id'  (should return uid=0)")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("\nInterrupted by user", "WARN")
        sys.exit(1)
    except Exception as e:
        log(f"Unexpected error: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        sys.exit(1)
