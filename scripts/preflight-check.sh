#!/system/bin/sh
# Root My Pixel — pre-root safety preflight.
#
# Run this BEFORE rooting, through Shizuku's own shell client so it runs at
# ADB-shell privilege without a computer:
#
#   rish scripts/preflight-check.sh
#
# (rish ships inside the Shizuku app: Shizuku -> "Use Shizuku in terminal
# apps" -> follow the setup steps to authorize your terminal, then rish
# behaves like a drop-in replacement for `sh`.)
#
# What it checks, and why: if the device already has a remote-control
# channel active (an MDM/enterprise Device Policy Controller, a Device
# Owner, a Profile Owner, or some other active Device Admin app), granting
# root hands that remote party root-level leverage too — not just the
# device's owner. This script only detects and reports; it never tries to
# remove or disable anything itself (a Device Owner generally can't be
# safely stripped by a script anyway — that needs either the MDM app's own
# "remove admin" flow or a factory reset).
#
# Exit code: 0 = clear to proceed. 1 = an active Device Admin / Device
# Owner / Profile Owner was found — do not root until it's removed.
# Warnings (Wireless debugging left on, a known remote-support app
# installed) are printed but do not change the exit code, since they're
# not necessarily a problem on their own.

FAIL=0

echo "=== Root My Pixel: pre-root safety preflight ==="
echo ""

# ── 1. Device Admin / Device Owner / Profile Owner ──────────────────────
echo "[*] Checking for active Device Admin / Device Owner / Profile Owner..."
DP_DUMP=$(dumpsys device_policy 2>/dev/null)

if [ -z "$DP_DUMP" ]; then
    echo "[!] WARN: could not read 'dumpsys device_policy' output (unexpected on a Pixel;"
    echo "    Shizuku shell may not have permission, or the command failed). Treat this as"
    echo "    inconclusive, not as a pass — verify manually if you can."
else
    if echo "$DP_DUMP" | grep -qi "Device Owner:"; then
        echo "[X] FAIL: a Device Owner is configured on this device."
        echo "$DP_DUMP" | grep -i -A3 "Device Owner:" | sed 's/^/      /'
        echo "    A Device Owner has full MDM-level remote control over this device already."
        echo "    Do NOT root until it is removed (via the MDM app's own removal flow, or a"
        echo "    factory reset) — rooting now would hand that remote controller root too."
        FAIL=1
    fi

    if echo "$DP_DUMP" | grep -qi "Profile Owner"; then
        echo "[X] FAIL: a Profile Owner is configured on this device (e.g. a work profile)."
        echo "$DP_DUMP" | grep -i -A3 "Profile Owner" | sed 's/^/      /'
        echo "    Remove the work profile / managed profile before rooting."
        FAIL=1
    fi

    ADMIN_COMPONENTS=$(echo "$DP_DUMP" | grep -oE 'admin=ComponentInfo\{[^}]+\}' | sort -u)
    if [ -n "$ADMIN_COMPONENTS" ]; then
        echo "[X] FAIL: active Device Admin app(s) found:"
        echo "$ADMIN_COMPONENTS" | sed 's/^/      /'
        echo "    Remove these via Settings -> Security -> Device admin apps before rooting."
        FAIL=1
    fi

    if [ "$FAIL" -eq 0 ]; then
        echo "[OK] No Device Owner, Profile Owner, or active Device Admin app detected."
    fi
fi
echo ""

# ── 2. Wireless debugging left on ────────────────────────────────────────
echo "[*] Checking Wireless debugging state..."
ADB_WIFI=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '[:space:]')
if [ "$ADB_WIFI" = "1" ]; then
    echo "[!] WARN: Wireless debugging is currently ON. If you only turned it on to pair"
    echo "    Shizuku, turn it back off now (Settings -> Developer options -> Wireless"
    echo "    debugging) — leaving it on is a standing local-network attack surface."
else
    echo "[OK] Wireless debugging is off (or its state couldn't be read, which is itself fine)."
fi
echo ""

# ── 3. Known remote-support / remote-access apps ─────────────────────────
echo "[*] Scanning installed packages for known remote-support/remote-access apps..."
# Non-exhaustive on purpose: a hit here is a prompt to double-check the app
# is one you actually intend to have installed, not proof of a problem —
# legitimate remote-support tools and legitimate MDM enrollment both use
# these packages, so this list only warns, it never fails the preflight.
KNOWN_REMOTE_PKGS="
com.teamviewer.host
com.teamviewer.quicksupport.market
com.teamviewer.quicksupport.addon
com.anydesk.anydeskandroid
com.sand.airdroid
com.sand.airmirror
com.rsupport.mobizen.mvagent
com.splashtop.remote.pad.v2
com.splashtop.streamer
com.remotepc.android
com.google.android.apps.work.clouddpc
com.airwatch.androidagent
com.microsoft.windowsintune.companyportal
com.citrix.CitrixReceiver
com.mobileiron.compliance.android
com.afwsamples.testdpc
"

INSTALLED_PKGS=$(pm list packages 2>/dev/null | sed 's/^package://')
FOUND_REMOTE=""
for pkg in $KNOWN_REMOTE_PKGS; do
    if echo "$INSTALLED_PKGS" | grep -qx "$pkg"; then
        FOUND_REMOTE="$FOUND_REMOTE$pkg
"
    fi
done

if [ -n "$FOUND_REMOTE" ]; then
    echo "[!] WARN: known remote-support/MDM-agent package(s) installed:"
    echo "$FOUND_REMOTE" | sed '/^$/d; s/^/      /'
    echo "    If you didn't install these yourself, remove them before rooting."
else
    echo "[OK] No known remote-support/MDM-agent packages found."
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────
echo "=== Summary ==="
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: an active Device Owner / Profile Owner / Device Admin was found."
    echo "Do not proceed with rooting until it is removed."
    exit 1
fi
echo "PASS: no active Device Owner / Profile Owner / Device Admin found."
echo "Review any WARN lines above, then it's safe to continue."
exit 0
