#!/usr/bin/env python3
"""
Root My Pixel — On-Device Python Script
Simple, transparent, user-approved rooting for Google Pixel devices.

Run via:
  rish python3 root_my_pixel.py    (on-device, via Shizuku)

Or on PC via adb:
  adb shell python3 root_my_pixel.py
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

PROFILES_JSON = "app/src/main/assets/profiles.json"
EXPLOIT_ASSETS_DIR = "app/src/main/assets/exploits"
KSUD_ASSET = "app/src/main/assets/ksud/ksud"
HELPER_LIB = "app/src/main/jniLibs/arm64-v8a/libcve43499root.so"

TEMP_DIR = "/data/local/tmp"
EXPLOIT_FILE = f"{TEMP_DIR}/cve-2026-43499-app.so"
HELPER_FILE = f"{TEMP_DIR}/cve-2026-43499-root"
KSUD_FILE = f"{TEMP_DIR}/ksud-pixel"
DAEMON_SOCKET = f"{TEMP_DIR}/temp_su.sock"
EXPLOIT_LOG = f"{TEMP_DIR}/exploit.log"

EXPLOIT_TIMEOUT_SEC = 1800  # 30 min
EXPLOIT_STALL_TIMEOUT_SEC = 600  # 10 min (no log progress)

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

def load_profiles(json_path: str) -> list:
    """Load profiles from profiles.json."""
    if not file_exists(json_path):
        log(f"profiles.json not found: {json_path}", "ERROR")
        sys.exit(1)

    with open(json_path) as f:
        data = json.load(f)
    return data.get("profiles", [])

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
# Payload Extraction
# =============================================================================

def extract_payload(src: str, dst: str) -> bool:
    """Extract asset file to destination. Path relative to repo root."""
    if not file_exists(src):
        log(f"Asset not found: {src}", "ERROR")
        return False

    mkdir_p(os.path.dirname(dst))
    run(f"cp {src} {dst}")
    run(f"chmod 755 {dst}")

    if not file_exists(dst):
        log(f"Failed to extract: {src} -> {dst}", "ERROR")
        return False

    log(f"Extracted: {dst}")
    return True

def extract_payloads(profile: Dict[str, Any]) -> bool:
    """Extract exploit .so and ksud binary."""
    log("\n=== EXTRACTING PAYLOADS ===")

    exploit_asset = profile["exploitAsset"]

    if not extract_payload(exploit_asset, EXPLOIT_FILE):
        return False

    if not extract_payload(KSUD_ASSET, KSUD_FILE):
        return False

    log("All payloads extracted")
    return True

# =============================================================================
# Exploit Execution
# =============================================================================

def execute_exploit() -> bool:
    """Run exploit via helper binary."""
    log("\n=== RUNNING EXPLOIT ===")

    if not file_exists(HELPER_LIB):
        log(f"Helper binary not found: {HELPER_LIB}", "ERROR")
        return False

    if not file_exists(EXPLOIT_FILE):
        log(f"Exploit .so not found: {EXPLOIT_FILE}", "ERROR")
        return False

    # Show user what's about to run
    log("About to run:")
    log(f"  {HELPER_LIB} --run-payload {EXPLOIT_FILE} {HELPER_LIB} {EXPLOIT_LOG}")

    if not prompt("Ready to execute exploit?"):
        log("Exploit cancelled by user", "WARN")
        return False

    # Run exploit with timeout
    start_time = time.time()
    last_log_time = start_time
    last_log_size = 0

    cmd = f"{HELPER_LIB} --run-payload {EXPLOIT_FILE} {HELPER_LIB} {EXPLOIT_LOG}"
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

def run_helper(cmd: str, retries: int = 5) -> Optional[str]:
    """Run command via helper binary with retries."""
    for attempt in range(1, retries + 1):
        result = run(f"{HELPER_LIB} -c '{cmd}'", capture=True, check=False)

        if result is None:
            continue

        # Check for transient errors
        if "No such file or directory" in result or "Connection refused" in result:
            if attempt < retries:
                time.sleep(1)
                continue

        return result

    return None

def install_kernelsu(profile: Dict[str, Any]) -> bool:
    """Install KernelSU via late-load."""
    log("\n=== INSTALLING KERNELSU ===")

    if not await_daemon_socket():
        return False

    kmi = profile["kmi"]

    # Stage ksud
    log(f"Staging ksud to {KSUD_FILE}...")
    stage_cmd = f"cp {KSUD_FILE} {KSUD_FILE}.real && chmod 755 {KSUD_FILE}.real && chown root:root {KSUD_FILE}.real"
    result = run_helper(stage_cmd)
    if not result:
        log("Failed to stage ksud", "ERROR")
        return False

    log("✓ ksud staged")

    # Trigger late-load
    log(f"Triggering KernelSU late-load (kmi={kmi})...")
    lateload_cmd = f"{KSUD_FILE}.real late-load --kmi {kmi}"
    result = run_helper(lateload_cmd)
    if result:
        log(result)

    # Verify KSU is active
    log("Verifying KernelSU...")
    for attempt in range(1, 11):
        check_cmd = "test -e /dev/kernelsu && echo KSU_OK || (test -e /sys/kernel/kernelsu && echo KSU_OK) || (test -e /data/adb/ksu && echo KSU_OK) || echo KSU_NOT_FOUND"
        result = run_helper(check_cmd)

        if result and "KSU_OK" in result:
            log(f"✓ KernelSU verified (attempt {attempt})")
            return True

        time.sleep(0.5)

    log("KernelSU verification failed", "ERROR")
    return False

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
# Main
# =============================================================================

def main():
    log("=== Root My Pixel (Python) ===")
    log("Simple, transparent rooting script")

    # Check running as root (via Shizuku)
    uid = run("id -u", capture=True) or "?"
    log(f"Running as UID {uid}")
    if uid != "2000":
        log("WARNING: Not running as UID 2000 (Shizuku)", "WARN")
        log("Run via: rish python3 root_my_pixel.py")

    # Detect device
    device_info = detect_device()

    # Load profiles
    profiles = load_profiles(PROFILES_JSON)

    # Find matching profile
    profile = find_profile(device_info, profiles)
    if not profile:
        sys.exit(1)

    # Show summary
    log(f"\n=== SUMMARY ===")
    log(f"Device: {device_info['device']} ({device_info['model']})")
    log(f"Profile: {profile['profileId']}")
    log(f"KMI: {profile['kmi']}")

    if not prompt("Continue with rooting?"):
        log("Cancelled", "WARN")
        sys.exit(0)

    # Pre-flight checks
    preflight_check()

    # Extract payloads
    if not extract_payloads(profile):
        sys.exit(1)

    # Run exploit
    if not execute_exploit():
        sys.exit(1)

    # Install KernelSU
    if not install_kernelsu(profile):
        sys.exit(1)

    log("\n=== SUCCESS ===")
    log("Root access acquired!")
    log("Open ReSukiSU Manager to grant root to apps")

if __name__ == "__main__":
    main()
