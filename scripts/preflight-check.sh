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
# their own phone. Whether the device is enrolled in an MDM/enterprise
# Device Policy Controller (Device Owner, Profile Owner, or any other
# Device Admin app) is irrelevant to that — a corporate-managed phone's
# legitimate holder can root it exactly like anyone else, and this script
# does not check for or care about that status at all.
#
# The actual guarantee that only the physical holder can ever reach root
# is structural, not something this script verifies: Root My Pixel has no
# INTERNET permission and no networking code anywhere (enforced by
# SecurityInvariantsTest in the app's own test suite), so there is no
# network path for a signal from outside the phone to reach it at all —
# root only ever comes from a local Shizuku Binder session that itself
# requires physical/local pairing.
#
# What this script DOES check, as non-blocking warnings, are two things
# that genuinely could let someone other than the phone's holder influence
# what happens right now: Wireless debugging left on (a standing
# local-network ADB surface), and a known remote-screen-control app being
# installed (a literal outside input channel). Neither is proof of a
# problem on its own, and this script never fails or blocks on anything —
# it's informational only.
#
# Exit code: always 0.

echo "=== Root My Pixel: pre-root safety preflight ==="
echo ""

# ── 1. Wireless debugging left on ────────────────────────────────────────
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

# ── 2. Known remote-screen-control apps ──────────────────────────────────
echo "[*] Scanning installed packages for known remote-screen-control apps..."
# Remote-screen-control apps only — deliberately NOT MDM/DPC packages, since
# MDM enrollment is irrelevant to whether the phone's physical holder can
# root it (see header above). These are apps that let someone else
# literally drive the screen remotely, a genuine outside-input channel.
# Non-exhaustive on purpose: a hit here is a prompt to double-check the app
# is one you actually intend to have installed, not proof of a problem —
# this list only warns, it never fails the preflight.
# Keep this in sync with InstallViewModel.kt's KNOWN_REMOTE_CONTROL_PACKAGES.
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
    echo "[!] WARN: known remote-screen-control app(s) installed:"
    echo "$FOUND_REMOTE" | sed '/^$/d; s/^/      /'
    echo "    These let someone else drive the screen remotely — if you didn't install one"
    echo "    yourself, remove it before rooting."
else
    echo "[OK] No known remote-screen-control apps found."
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────
echo "=== Summary ==="
echo "Nothing here blocks rooting — MDM/Device Owner enrollment is irrelevant, and root"
echo "only ever comes from a local Shizuku session (this app has no networking at all)."
echo "Review any WARN lines above, then it's safe to continue."
exit 0
