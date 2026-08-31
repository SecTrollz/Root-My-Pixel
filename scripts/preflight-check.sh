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
# Root My Pixel is for a device's owner, physically holding it, rooting
# their own phone — that person never needs, and shouldn't need, any
# Device Admin/Owner status themselves; that's irrelevant to normal use.
# What actually matters: a Device Owner means full, whole-device MDM/
# enterprise control provisioned through a deliberate enrollment flow —
# someone other than whoever is holding the phone right now administers
# it, and rooting would hand that remote party root too. That's the one
# thing this script fails on.
#
# A generic active Device Admin component or a work-profile Profile Owner
# is a much weaker, noisier signal — Find My Device and plenty of ordinary
# consumer apps register as device admins on completely normal, fully-owned
# personal phones, and a work profile only manages its own sandboxed
# profile, not the whole device. Neither implies someone else controls the
# device the way a Device Owner does, so neither fails the check — both are
# printed as warnings to review instead.
#
# This script only detects and reports; it never tries to remove or
# disable anything itself (a Device Owner generally can't be safely
# stripped by a script anyway — that needs either the MDM app's own
# "remove admin" flow or a factory reset).
#
# Exit code: 0 = clear to proceed (including when only warnings were
# found). 1 = a Device Owner was found — do not root until it's removed.

FAIL=0

echo "=== Root My Pixel: pre-root safety preflight ==="
echo ""

# ── 1. Device Owner (blocking), Profile Owner / Device Admin (warn only) ─
echo "[*] Checking for a Device Owner (whole-device MDM/remote control)..."
DP_DUMP=$(dumpsys device_policy 2>/dev/null)

if [ -z "$DP_DUMP" ]; then
    echo "[!] WARN: could not read 'dumpsys device_policy' output (unexpected on a Pixel;"
    echo "    Shizuku shell may not have permission, or the command failed). Treat this as"
    echo "    inconclusive, not as a pass — verify manually if you can."
else
    if echo "$DP_DUMP" | grep -qi "Device Owner:"; then
        echo "[X] FAIL: a Device Owner is configured on this device."
        echo "$DP_DUMP" | grep -i -A3 "Device Owner:" | sed 's/^/      /'
        echo "    A Device Owner has full MDM-level remote control over this device already —"
        echo "    someone other than whoever is holding it right now administers it."
        echo "    Do NOT root until it is removed (via the MDM app's own removal flow, or a"
        echo "    factory reset) — rooting now would hand that remote controller root too."
        FAIL=1
    else
        echo "[OK] No Device Owner found — this device isn't under remote/MDM control."
    fi

    if echo "$DP_DUMP" | grep -qi "Profile Owner"; then
        echo "[!] WARN: a Profile Owner is configured (e.g. a work profile)."
        echo "$DP_DUMP" | grep -i -A3 "Profile Owner" | sed 's/^/      /'
        echo "    This only manages its own sandboxed profile, not the whole device, so it"
        echo "    doesn't block rooting — review it if you don't recognize it."
    fi

    ADMIN_COMPONENTS=$(echo "$DP_DUMP" | grep -oE 'admin=ComponentInfo\{[^}]+\}' | sort -u)
    if [ -n "$ADMIN_COMPONENTS" ]; then
        echo "[!] WARN: active Device Admin app(s) found:"
        echo "$ADMIN_COMPONENTS" | sed 's/^/      /'
        echo "    This is common and often benign (e.g. Find My Device) and doesn't block"
        echo "    rooting — review it if you don't recognize it."
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
    echo "FAIL: a Device Owner was found. Do not proceed with rooting until it is removed."
    exit 1
fi
echo "PASS: no Device Owner found."
echo "Review any WARN lines above (Profile Owner, Device Admin apps, Wireless debugging,"
echo "known remote-support apps) — none of them block rooting on their own, but it's worth"
echo "confirming you recognize everything listed."
exit 0
