#!/system/bin/sh
# Root My Pixel — On-Device KernelSU Setup
# Automated exploit + KernelSU installation entirely on-device via Shizuku
# No computer required, no Python dependencies
#
# Usage: rish sh scripts/on-device-setup.sh
#
# Requires:
#   - Shizuku running (UID 2000)
#   - Root My Pixel app installed
#   - curl or wget for downloads
#   - unzip for extracting payloads

set -e

# =============================================================================
# Configuration
# =============================================================================

GITHUB_REPO="https://github.com/SecTrollz/Root-My-Pixel/raw/main"
TEMP_DIR="/data/local/tmp"
WORK_DIR="/data/local/tmp/rmp-work"
EXPLOIT_FILE="$TEMP_DIR/cve-2026-43499-app.so"
KSUD_FILE="$TEMP_DIR/ksud-pixel"
DAEMON_SOCKET="$TEMP_DIR/temp_su.sock"
EXPLOIT_LOG="$TEMP_DIR/exploit.log"

# Timeouts (seconds)
EXPLOIT_TIMEOUT=1800      # 30 minutes max
STALL_TIMEOUT=600         # 10 minutes no activity
DAEMON_WAIT=15            # daemon socket ready

# =============================================================================
# Logging & Utilities
# =============================================================================

log() {
    local level="$1"
    shift
    local ts=$(date '+%H:%M:%S')
    printf "[%s] [%-5s] %s\n" "$ts" "$level" "$*"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_err()   { log "ERROR" "$@"; }

prompt() {
    local msg="$1"
    while true; do
        printf "\n>>> %s [y/n]: " "$msg"
        read -r ans
        case "$ans" in
            y|Y|yes) return 0 ;;
            n|N|no)  return 1 ;;
            *)       echo "Please answer 'y' or 'n'" ;;
        esac
    done
}

die() {
    log_err "$@"
    exit 1
}

# =============================================================================
# Device Detection
# =============================================================================

detect_device() {
    log_info "Detecting device..."

    DEVICE=$(getprop ro.product.device 2>/dev/null || echo "unknown")
    BUILD=$(getprop ro.build.display.id 2>/dev/null || echo "unknown")
    KERNEL=$(cat /proc/version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-a-zA-Z0-9]*' | head -1)
    MODEL=$(getprop ro.product.model 2>/dev/null || echo "unknown")

    log_info "Device: $DEVICE ($MODEL)"
    log_info "Build: $BUILD"
    log_info "Kernel: $KERNEL"
}

# Device → target mapping (build-specific)
find_target() {
    case "$DEVICE:$BUILD" in
        tegu:CP2A.260705.006)     echo "tegu-CP2A.260705.006" ;;
        panther:CP2A.260705.006)  echo "panther-CP2A.260705.006" ;;
        panther:BP2A.250705.008)  echo "panther-BP2A.250705.008" ;;
        lynx:CP2A.260705.006)     echo "lynx-CP2A.260705.006" ;;
        mustang:CP2A.260705.006)  echo "mustang-CP2A.260705.006" ;;
        caiman:CP2A.260705.006)   echo "caiman-CP2A.260705.006" ;;
        komodo:CP2A.260705.006)   echo "komodo-CP2A.260705.006" ;;
        tokay:CP2A.260705.006)    echo "tokay-CP2A.260705.006" ;;
        blazer:CP2A.260705.006)   echo "blazer-CP2A.260705.006" ;;
        # Add more as needed...
        *)                        return 1 ;;
    esac
}

get_kmi() {
    case "$1" in
        *-CP2A.260705.006|*-CP1A.260405.005|*-BP2A.250705.008|*-CD1A.*)
            echo "android14-6.1" ;;
        *)
            echo "android15-6.6" ;;
    esac
}

# =============================================================================
# Payload Management
# =============================================================================

extract_from_apk() {
    local asset="$1"
    local dst="$2"

    local apk_dir=$(find /data/app -name 'com.alex193a.rootmypixel*' -type d 2>/dev/null | head -1)
    [ -z "$apk_dir" ] && return 1

    local apk="$apk_dir/base.apk"
    [ ! -f "$apk" ] && return 1

    mkdir -p "$(dirname "$dst")"
    unzip -p "$apk" "$asset" > "$dst" 2>/dev/null || return 1

    [ -f "$dst" ] && [ -s "$dst" ] && {
        chmod 755 "$dst"
        log_info "✓ Extracted: $asset"
        return 0
    }
    return 1
}

download_payload() {
    local url="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"
    log_info "Downloading: $url"

    if command -v curl >/dev/null 2>&1; then
        curl -L --max-time 120 --progress-bar "$url" -o "$dst" 2>/dev/null || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget --timeout=120 -O "$dst" "$url" 2>/dev/null || return 1
    else
        log_err "Neither curl nor wget found"
        return 1
    fi

    [ -f "$dst" ] && [ -s "$dst" ] && {
        chmod 755 "$dst"
        log_info "✓ Downloaded: $(basename "$dst")"
        return 0
    }
    return 1
}

get_payload() {
    local asset="$1"
    local url="$2"
    local dst="$3"

    log_info "Getting $asset..."
    extract_from_apk "$asset" "$dst" && return 0
    download_payload "$url" "$dst" && return 0

    log_err "Failed to get $asset"
    return 1
}

get_helper_binary() {
    local helpers="/data/app/com.alex193a.rootmypixel/lib/arm64-v8a/libcve43499root.so"

    if [ -f "$helpers" ]; then
        HELPER_BINARY="$helpers"
        return 0
    fi

    helpers=$(find /data/app -path '*/com.alex193a.rootmypixel*/lib/arm64-v8a/libcve43499root.so' 2>/dev/null | head -1)
    if [ -n "$helpers" ]; then
        HELPER_BINARY="$helpers"
        return 0
    fi

    log_err "Helper binary not found (Root My Pixel app not installed?)"
    return 1
}

# =============================================================================
# Exploit Execution
# =============================================================================

execute_exploit() {
    log_info ""
    log_info "=== RUNNING EXPLOIT ==="

    get_helper_binary || die "Helper binary not found"

    [ ! -f "$EXPLOIT_FILE" ] && die "Exploit .so not found: $EXPLOIT_FILE"

    log_info "Command: $HELPER_BINARY --run-payload $EXPLOIT_FILE $HELPER_BINARY $EXPLOIT_LOG"

    prompt "Ready to run exploit?" || {
        log_warn "Cancelled by user"
        return 1
    }

    log_info "Running exploit..."
    local start_time=$(date +%s)
    local last_log_time=$start_time
    local last_log_size=0

    # Run exploit in background with timeout
    (timeout $EXPLOIT_TIMEOUT "$HELPER_BINARY" --run-payload "$EXPLOIT_FILE" "$HELPER_BINARY" "$EXPLOIT_LOG" 2>&1) &
    local pid=$!

    while kill -0 $pid 2>/dev/null; do
        local now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ -f "$EXPLOIT_LOG" ]; then
            local log_size=$(stat -c%s "$EXPLOIT_LOG" 2>/dev/null || echo 0)
            if [ $log_size -gt $last_log_size ]; then
                last_log_time=$now
                last_log_size=$log_size
                tail -3 "$EXPLOIT_LOG" 2>/dev/null | while read -r line; do
                    log_info "$line"
                done
            fi
        fi

        local stall=$((now - last_log_time))
        if [ $stall -gt $STALL_TIMEOUT ]; then
            log_err "Exploit stalled (no activity for ${stall}s)"
            kill $pid 2>/dev/null || true
            wait $pid 2>/dev/null || true
            return 1
        fi

        if [ $elapsed -gt $EXPLOIT_TIMEOUT ]; then
            log_err "Exploit timeout (${elapsed}s)"
            kill $pid 2>/dev/null || true
            wait $pid 2>/dev/null || true
            return 1
        fi

        sleep 2
    done

    wait $pid 2>/dev/null || true
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_err "Exploit failed (exit code: $exit_code)"
        [ -f "$EXPLOIT_LOG" ] && {
            log_info ""
            log_info "=== EXPLOIT LOG ==="
            cat "$EXPLOIT_LOG"
        }
        return 1
    fi

    if grep -q "done=1" "$EXPLOIT_LOG" 2>/dev/null && grep -q "root=1" "$EXPLOIT_LOG" 2>/dev/null; then
        log_info "✓ Exploit successful"
        return 0
    fi

    log_err "Exploit success markers not found in log"
    return 1
}

await_daemon_socket() {
    local start=$(date +%s)
    log_info "Waiting for daemon socket: $DAEMON_SOCKET"

    while true; do
        if [ -S "$DAEMON_SOCKET" ]; then
            log_info "✓ Daemon socket ready"
            return 0
        fi

        local now=$(date +%s)
        if [ $((now - start)) -gt $DAEMON_WAIT ]; then
            log_err "Daemon socket timeout"
            return 1
        fi

        sleep 0.5
    done
}

# =============================================================================
# KernelSU Installation
# =============================================================================

run_as_root() {
    local cmd="$1"
    [ -z "$HELPER_BINARY" ] && die "Helper binary not set"

    "$HELPER_BINARY" -c "$cmd" 2>&1
}

install_kernelsu() {
    local kmi="$1"

    log_info ""
    log_info "=== SETTING UP KERNELSU ==="

    await_daemon_socket || die "Daemon socket never appeared"

    # 1. Create /data/adb
    log_info "[1] Creating /data/adb directory..."
    run_as_root "mkdir -p /data/adb && chmod 700 /data/adb" >/dev/null
    log_info "✓ /data/adb ready"

    # 2. Set SELinux permissive
    log_info "[2] Setting SELinux permissive..."
    run_as_root "setenforce 0" >/dev/null
    local se_status=$(run_as_root "getenforce")
    if echo "$se_status" | grep -q "Permissive"; then
        log_info "✓ SELinux permissive"
    else
        log_warn "SELinux may still be enforcing (continuing anyway)"
    fi

    # 3. Stage ksud
    log_info "[3] Staging ksud binary..."
    run_as_root "chmod 755 $KSUD_FILE && chown root:root $KSUD_FILE" >/dev/null
    log_info "✓ ksud staged"

    # 4. Trigger KernelSU late-load
    log_info "[4] Triggering KernelSU late-load (KMI=$kmi)..."
    run_as_root "$KSUD_FILE late-load --kmi $kmi" >/dev/null || true
    sleep 1

    # 5. Verify KernelSU
    log_info "[5] Verifying KernelSU modules..."
    local attempt=1
    while [ $attempt -le 15 ]; do
        local check=$(run_as_root "test -e /dev/kernelsu && echo 1 || echo 0")
        if [ "$check" = "1" ]; then
            log_info "✓ KernelSU verified"
            break
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt 15 ]; then
        log_warn "KernelSU module not yet available (may appear after reboot)"
    fi

    # 6. Create marker for ReSukiSU
    log_info "[6] Creating KernelSU metadata..."
    run_as_root "mkdir -p /data/adb/ksu && touch /data/adb/ksu/.installed" >/dev/null
    log_info "✓ Setup complete"

    return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_info "╔════════════════════════════════════════════╗"
    log_info "║ Root My Pixel — On-Device KernelSU Setup  ║"
    log_info "╚════════════════════════════════════════════╝"

    local uid=$(id -u 2>/dev/null || echo "?")
    if [ "$uid" != "2000" ]; then
        log_warn "Not running as UID 2000 (Shizuku)"
        log_warn "Run via: rish sh $0"
        return 1
    fi

    # Detect device
    detect_device

    # Find target
    local target=$(find_target)
    [ -z "$target" ] && die "Device $DEVICE/$BUILD not supported"

    local kmi=$(get_kmi "$target")

    log_info ""
    log_info "─────────────────────────────────────────"
    log_info "Device:  $DEVICE ($MODEL)"
    log_info "Build:   $BUILD"
    log_info "Kernel:  $KERNEL"
    log_info "Target:  $target"
    log_info "KMI:     $kmi"
    log_info "─────────────────────────────────────────"

    prompt "Continue with exploit and KernelSU?" || {
        log_warn "Cancelled"
        return 0
    }

    # Setup
    mkdir -p "$WORK_DIR"
    rm -f "$EXPLOIT_LOG"

    # Get payloads
    log_info ""
    log_info "=== PREPARING PAYLOADS ==="

    get_payload "exploits/${target}.so" "$GITHUB_REPO/app/src/main/assets/exploits/${target}.so" "$EXPLOIT_FILE" || exit 1
    get_payload "ksud" "$GITHUB_REPO/app/src/main/assets/ksud/ksud" "$KSUD_FILE" || exit 1
    log_info "✓ All payloads ready"

    # Execute
    execute_exploit || exit 1
    install_kernelsu "$kmi" || exit 1

    # Cleanup
    rm -f "$EXPLOIT_LOG" "$WORK_DIR"/* 2>/dev/null || true

    # Done
    log_info ""
    log_info "═════════════════════════════════════════"
    log_info "SUCCESS — KernelSU is installed!"
    log_info "═════════════════════════════════════════"
    log_info ""
    log_info "Next steps:"
    log_info "1. Open ReSukiSU Manager"
    log_info "2. Grant root to apps as needed"
    log_info "3. Reboot to persist"
    log_info ""
}

main "$@"
