#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────
# Root My Pixel — Build Standalone Installer
#
# Assembles a single self-contained shell script (root-my-pixel-standalone.sh)
# that runs the exact same local, Shizuku-gated install flow as the app —
# device detection, exploit extraction, IonStack (CVE-2026-43499) run,
# KernelSU/ReSukiSU late-load — without requiring the APK to be installed.
#
# It works by base64-embedding the binaries this repo already builds and
# commits under app/src/main/assets/ (one native helper, one ksud, and the
# per-device-per-build exploit .so for every profile in profiles.json), so
# no new exploit code is written or compiled here — this script only
# packages what build-all.sh already produced.
#
# The generated output is NOT committed to this repo (it's tens of MB of
# base64 and would bloat git history exactly the way the exploit-binary
# incident referenced in README.md did) — run this locally and keep the
# output for yourself, or distribute it out-of-band.
#
# Requirements: jq, base64 (both standard on macOS/Linux).
# ────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/app/src/main/assets"
PROFILES_JSON="$ASSETS/profiles.json"
EXPLOITS_DIR="$ASSETS/exploits"
KSUD_BIN="$ASSETS/ksud/ksud"
HELPER_BIN="$ROOT/app/src/main/jniLibs/arm64-v8a/libcve43499root.so"
OUT="${1:-$ROOT/dist/root-my-pixel-standalone.sh}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew/apt install jq)"; exit 1; }
[ -f "$PROFILES_JSON" ] || { echo "ERROR: missing $PROFILES_JSON"; exit 1; }
[ -f "$KSUD_BIN" ] || { echo "ERROR: missing $KSUD_BIN (run ./build-all.sh first)"; exit 1; }
[ -f "$HELPER_BIN" ] || { echo "ERROR: missing $HELPER_BIN (run ./build-all.sh first)"; exit 1; }

mkdir -p "$(dirname "$OUT")"

b64_of() { base64 < "$1" | tr -d '\n'; }

echo "[*] Embedding native helper ($(stat -f%z "$HELPER_BIN" 2>/dev/null || stat -c%s "$HELPER_BIN") bytes)..."
HELPER_B64="$(b64_of "$HELPER_BIN")"

echo "[*] Embedding ksud ($(stat -f%z "$KSUD_BIN" 2>/dev/null || stat -c%s "$KSUD_BIN") bytes)..."
KSUD_B64="$(b64_of "$KSUD_BIN")"

PROFILE_COUNT="$(jq '.profiles | length' "$PROFILES_JSON")"
echo "[*] Embedding $PROFILE_COUNT exploit payloads..."

{
  cat <<'HEADER'
#!/system/bin/sh
# Root My Pixel — Standalone Installer (generated, do not hand-edit)
#
# Self-contained equivalent of the app's install flow: every exploit
# payload for every supported device/build, the native helper, and ksud
# are embedded below as base64. Requires Shizuku running locally on THIS
# device (rish, or auto-escalated below) — there is no networking anywhere
# in this script, matching the app's own SecurityInvariantsTest guarantee.
# Root only ever comes from a local Shizuku Binder session you paired
# yourself; nothing here fetches anything or phones out.
#
# Regenerate with: scripts/build-standalone-installer.sh

TEMP_DIR="/data/local/tmp"
HELPER_FILE="$TEMP_DIR/rootmypixel-helper"
EXPLOIT_FILE="$TEMP_DIR/cve-2026-43499-app.so"
KSUD_FILE="$TEMP_DIR/ksud-pixel"
DAEMON_SOCKET="$TEMP_DIR/temp_su.sock"
EXPLOIT_LOG="$TEMP_DIR/exploit.log"
EXPLOIT_TIMEOUT=1800
STALL_TIMEOUT=600

log() {
    ts=$(date '+%H:%M:%S'); level=$1; shift
    echo "[$ts] [$level] $@"
}
prompt() {
    while true; do printf ">>> $1 [y/n]: "; read -r ans; case "$ans" in y|yes) return 0 ;; n|no) return 1 ;; esac; done
}

extract_payload() {
    log "INFO" "Extracting $3..."
    mkdir -p "$(dirname "$2")"
    echo "$1" | base64 -d > "$2" 2>/dev/null || { log "ERROR" "Failed to extract $3"; return 1; }
    [ -f "$2" ] && [ -s "$2" ] && { chmod 755 "$2"; log "INFO" "Extracted: $3"; return 0; }
    return 1
}

# Everything staged in $TEMP_DIR is scrubbed on every exit path (success,
# failure, or an interrupted run) — the original skeleton only cleaned up
# after a full success, leaving the exploit binary and log behind on any
# earlier failure.
cleanup() { rm -f "$HELPER_FILE" "$EXPLOIT_FILE" "$EXPLOIT_LOG"; }
trap cleanup EXIT INT TERM

check_arch() {
    ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
    if [ "$ABI" != "arm64-v8a" ]; then
        log "ERROR" "Unsupported ABI: $ABI (need arm64-v8a — every supported Pixel target is arm64)"
        return 1
    fi
}

# Non-blocking safety preflight, ported from scripts/preflight-check.sh:
# these are the only two things that could let someone other than the
# phone's physical holder influence what happens right now. Never blocks.
safety_preflight() {
    log "INFO" "=== SAFETY PREFLIGHT ==="
    ADB_WIFI=$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '[:space:]')
    if [ "$ADB_WIFI" = "1" ]; then
        log "WARN" "Wireless debugging is ON — turn it off after Shizuku pairing if you haven't."
    else
        log "INFO" "Wireless debugging is off."
    fi
    INSTALLED_PKGS=$(pm list packages 2>/dev/null | sed 's/^package://')
    FOUND_REMOTE=""
    for pkg in com.teamviewer.host com.teamviewer.quicksupport.market com.teamviewer.quicksupport.addon \
               com.anydesk.anydeskandroid com.sand.airdroid com.sand.airmirror com.rsupport.mobizen.mvagent \
               com.splashtop.remote.pad.v2 com.splashtop.streamer com.remotepc.android; do
        if echo "$INSTALLED_PKGS" | grep -qx "$pkg"; then
            FOUND_REMOTE="$FOUND_REMOTE $pkg"
        fi
    done
    if [ -n "$FOUND_REMOTE" ]; then
        log "WARN" "Known remote-screen-control app(s) installed:$FOUND_REMOTE — remove if you didn't install them."
    else
        log "INFO" "No known remote-screen-control apps found."
    fi
}

detect_device() {
    log "INFO" "=== DEVICE DETECTION ==="
    KERNEL=$(cat /proc/version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    DEVICE=$(getprop ro.product.device 2>/dev/null)
    BUILD=$(getprop ro.build.display.id 2>/dev/null)
    MODEL=$(getprop ro.product.model 2>/dev/null)
    log "INFO" "Device: $DEVICE ($MODEL), Build: $BUILD, Kernel: $KERNEL"
}

# Matches on (codename, build display ID) — that pair is unique per profile
# in profiles.json (e.g. panther has two distinct entries, one per build).
# Kernel is cross-checked as a sanity guard, not part of the match key.
find_profile() {
    echo "$PROFILES" | while IFS='|' read -r dev kern_base build kmi suffix; do
        [ -z "$dev" ] && continue
        if [ "$dev" = "$1" ] && [ "$3" = "$build" ]; then
            if [ "$2" != "$kern_base" ]; then
                log "WARN" "Kernel base $2 != expected $kern_base for $dev-$build (continuing — build ID matched)"
            fi
            echo "$dev|$build|$kmi|$suffix"
            return
        fi
    done
}

get_exploit_b64() {
    suffix="$1"
    eval "printf '%s' \"\$EXPLOIT_B64_$suffix\""
}

execute_exploit() {
    log "INFO" ""
    log "INFO" "=== RUNNING EXPLOIT ==="
    [ ! -f "$HELPER_FILE" ] && { log "ERROR" "Helper binary not staged"; return 1; }
    [ ! -f "$EXPLOIT_FILE" ] && { log "ERROR" "Exploit not found"; return 1; }
    prompt "Ready to execute exploit?" || { log "WARN" "Exploit cancelled"; return 1; }

    start_time=$(date +%s); last_log_time=$start_time; last_log_size=0
    timeout $EXPLOIT_TIMEOUT "$HELPER_FILE" --run-payload "$EXPLOIT_FILE" "$HELPER_FILE" "$EXPLOIT_LOG" 2>&1 &
    pid=$!

    while kill -0 $pid 2>/dev/null; do
        now=$(date +%s); elapsed=$((now - start_time))
        if [ -f "$EXPLOIT_LOG" ]; then
            log_size=$(stat -c%s "$EXPLOIT_LOG" 2>/dev/null || echo 0)
            if [ "$log_size" -gt "$last_log_size" ]; then
                last_log_time=$now; last_log_size=$log_size
                tail -3 "$EXPLOIT_LOG" | while read line; do log "INFO" "$line"; done
            fi
        fi
        [ $((now - last_log_time)) -gt $STALL_TIMEOUT ] && { log "ERROR" "Exploit stalled"; kill $pid 2>/dev/null; return 1; }
        [ $elapsed -gt $EXPLOIT_TIMEOUT ] && { log "ERROR" "Exploit timeout"; kill $pid 2>/dev/null; return 1; }
        sleep 2
    done

    wait $pid 2>/dev/null || true
    grep -q "done=1" "$EXPLOIT_LOG" 2>/dev/null && grep -q "root=1" "$EXPLOIT_LOG" 2>/dev/null || { log "ERROR" "Exploit failed — see $EXPLOIT_LOG"; return 1; }
    log "INFO" "Exploit successful"
}

await_daemon_socket() {
    log "INFO" "Waiting for daemon socket..."
    start=$(date +%s)
    while true; do
        [ -S "$DAEMON_SOCKET" ] && { log "INFO" "Daemon socket ready"; return 0; }
        [ $(($(date +%s) - start)) -gt 15 ] && { log "ERROR" "Daemon socket timeout"; return 1; }
        sleep 0.5
    done
}

run_helper() {
    cmd="$1"; retries=${2:-5}; attempt=1
    while [ $attempt -le $retries ]; do
        output=$(timeout 90 "$HELPER_FILE" -c "$cmd" 2>&1 || true)
        [ -n "$output" ] && echo "$output" | while read line; do log "INFO" "$line"; done
        if [ $attempt -lt $retries ] && echo "$output" | grep -q "Connection refused"; then
            sleep 1.5; attempt=$((attempt + 1)); continue
        fi
        echo "$output"
        return 0
    done
}

install_kernelsu() {
    kmi="$1"
    log "INFO" ""
    log "INFO" "=== SETTING UP KERNELSU ROOT ==="
    await_daemon_socket || return 1
    log "INFO" "[1] Creating /data/adb..."
    run_helper "mkdir -p /data/adb && chmod 700 /data/adb" >/dev/null || true
    log "INFO" "[2] Setting SELinux permissive..."
    run_helper "setenforce 0" >/dev/null || true
    log "INFO" "[3] Staging ksud..."
    run_helper "chmod 755 $KSUD_FILE && chown root:root $KSUD_FILE" >/dev/null || true
    log "INFO" "[4] Running ksud late-load (KMI=$kmi)..."
    run_helper "$KSUD_FILE late-load --kmi $kmi" >/dev/null || true
    sleep 1
    log "INFO" "[5] Verifying kernel module..."
    attempt=1
    while [ $attempt -le 15 ]; do
        run_helper "test -e /dev/kernelsu" >/dev/null 2>&1 && { log "INFO" "KernelSU verified"; break; }
        [ $((attempt % 3)) -eq 0 ] && log "INFO" "  Waiting... ($attempt/15)"
        sleep 0.5
        attempt=$((attempt + 1))
    done
    log "INFO" "[6] Testing root..."
    test=$(run_helper "id -u" 2>/dev/null || echo "")
    [ "$test" = "0" ] && log "INFO" "Root verified" || log "WARN" "Root test inconclusive"
    log "INFO" "[7] Setting up ReSukiSU..."
    run_helper "mkdir -p /data/adb/ksu && chmod 777 /data/adb/ksu" >/dev/null || true
}

main() {
    log "INFO" "================================================"
    log "INFO" "  Root My Pixel — Standalone Installer"
    log "INFO" "================================================"

    check_arch || exit 1
    safety_preflight
    detect_device
    profile=$(find_profile "$DEVICE" "$KERNEL" "$BUILD")
    [ -z "$profile" ] && { log "ERROR" "Device/build not supported: $DEVICE / $BUILD"; exit 1; }

    # Split on '|' without a subshell (a `cmd | read` pipe here would run
    # the read in a subshell and silently drop dev/build/kmi/suffix once it
    # exits — the bug in the original skeleton that always fed an empty
    # --kmi into ksud late-load).
    OLDIFS="$IFS"; IFS='|'; set -- $profile; IFS="$OLDIFS"
    dev="$1"; build="$2"; kmi="$3"; suffix="$4"
    log "INFO" "MATCHED: $dev ($MODEL) | BUILD: $build | KMI: $kmi"

    prompt "Continue?" || exit 0
    mkdir -p "$TEMP_DIR"

    log "INFO" ""
    log "INFO" "=== PREPARING PAYLOADS ==="
    extract_payload "$HELPER_B64" "$HELPER_FILE" "native helper" || exit 1
    extract_payload "$(get_exploit_b64 "$suffix")" "$EXPLOIT_FILE" "exploit ($dev-$build)" || exit 1
    extract_payload "$KSUD_B64" "$KSUD_FILE" "ksud" || exit 1
    log "INFO" "All payloads ready"

    execute_exploit || exit 1
    install_kernelsu "$kmi" || exit 1

    log "INFO" ""
    log "INFO" "================================================"
    log "INFO" "SUCCESS — KernelSU is installed!"
    log "INFO" "================================================"
    log "INFO" ""
    log "INFO" "Next: Open ReSukiSU Manager -> Grant root"
    log "INFO" "Verify: su -c 'id'  (should return uid=0)"
}

auto_invoke_with_rish() {
    uid=$(id -u 2>/dev/null)
    if [ "$uid" != "2000" ]; then
        script_abs="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")" || return 1
        if command -v rish >/dev/null 2>&1; then
            log "INFO" "Escalating to Shizuku context via rish..."
            exec rish sh "$script_abs" "$@"
        else
            log "ERROR" "================================================"
            log "ERROR" "NOT running in Shizuku (UID: $uid, need: 2000)"
            log "ERROR" "rish binary not found in PATH"
            log "ERROR" "================================================"
            log "ERROR" "FIXES:"
            log "ERROR" "1. Install Shizuku app, pair it, tap Start"
            log "ERROR" "2. Shizuku -> Use Shizuku in terminal apps -> authorize this terminal"
            log "ERROR" "3. Run: rish sh '$script_abs'"
            log "ERROR" "================================================"
            exit 1
        fi
    fi
}

HEADER

  printf 'HELPER_B64="%s"\n' "$HELPER_B64"
  printf 'KSUD_B64="%s"\n' "$KSUD_B64"

  echo 'PROFILES="'
  jq -r '.profiles[] | [.codename, (.kernelRelease | split("-")[0]), .buildDisplay, .kmi, (.profileId | gsub("[^A-Za-z0-9]"; "_"))] | join("|")' "$PROFILES_JSON"
  echo '"'

  jq -r '.profiles[] | "\(.codename)-\(.buildDisplay)|\(.exploitAsset)|\(.profileId | gsub("[^A-Za-z0-9]"; "_"))"' "$PROFILES_JSON" | \
  while IFS='|' read -r label asset suffix; do
    echo "[*]   $label" >&2
    printf 'EXPLOIT_B64_%s="%s"\n' "$suffix" "$(b64_of "$EXPLOITS_DIR/$(basename "$asset")")"
  done

  cat <<'FOOTER'

auto_invoke_with_rish "$@"
main "$@"
FOOTER
} > "$OUT"

chmod +x "$OUT"
echo ""
echo "[*] Wrote $OUT ($(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT") bytes, $PROFILE_COUNT profiles embedded)"
echo "[*] Syntax check:"
sh -n "$OUT" && echo "    OK"
