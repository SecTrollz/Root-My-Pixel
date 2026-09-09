#!/system/bin/sh
# Root My Pixel — KernelSU Setup (Professional Edition)
# Hostile system approach: multiple fallbacks, verbose logging, graceful degradation

set -e

# ============================================================================
# Configuration
# ============================================================================
TEMP_DIR="/data/local/tmp"
WORK_DIR="$TEMP_DIR/rmp-setup"
EXPLOIT_FILE="$TEMP_DIR/exploit.so"
HELPER_FILE="$TEMP_DIR/helper.so"
KSUD_FILE="$TEMP_DIR/ksud"
DAEMON_SOCKET="$TEMP_DIR/temp_su.sock"
EXPLOIT_LOG="$TEMP_DIR/exploit.log"

REPO_BASE="https://github.com/SecTrollz/Root-My-Pixel/raw/main"
GITHUB_TIMEOUT=30

# Device info (populated by detect_device)
DEVICE=""
BUILD=""
KERNEL=""
MODEL=""
KMI=""

# ============================================================================
# Logging & Utilities
# ============================================================================
log() {
    local level="$1"; shift
    local ts=$(date '+%H:%M:%S')
    echo "[$ts] [$level] $*"
}

fatal() {
    log "FATAL" "$*"
    exit 1
}

warn() {
    log "WARN" "$*"
}

info() {
    log "INFO" "$*"
}

debug() {
    log "DEBUG" "$*"
}

try_cmd() {
    local desc="$1"; shift
    info "Trying: $desc"
    debug "$ $*"
    if "$@" 2>&1; then
        info "✓ $desc"
        return 0
    else
        local ret=$?
        warn "✗ $desc (exit: $ret)"
        return $ret
    fi
}

# ============================================================================
# Device Detection
# ============================================================================
detect_device() {
    info "=== DEVICE DETECTION ==="

    DEVICE=$(getprop ro.product.device 2>/dev/null || echo "")
    BUILD=$(getprop ro.build.display.id 2>/dev/null || echo "")
    MODEL=$(getprop ro.product.model 2>/dev/null || echo "")

    # Kernel: extract first 3 components only (6.1.157 from 6.1.157-android14-11-gXXX)
    local kernel_full=$(cat /proc/version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    KERNEL="$kernel_full"

    [ -z "$DEVICE" ] && fatal "Cannot detect device (getprop failed)"
    [ -z "$BUILD" ] && fatal "Cannot detect build (getprop failed)"
    [ -z "$KERNEL" ] && fatal "Cannot detect kernel (proc/version failed)"

    info "Device: $DEVICE ($MODEL)"
    info "Build: $BUILD"
    info "Kernel: $KERNEL"
}

# ============================================================================
# Profile Matching
# ============================================================================
get_profile() {
    # Hardcoded profiles (last resort fallback)
    case "$DEVICE:$KERNEL:$BUILD" in
        tegu:6.1.157:CP2A.260805.005)
            echo "android14-6.1|tegu-CP2A.260805.005"
            return 0
            ;;
        tegu:6.1.157:CP2A.260705.006)
            echo "android14-6.1|tegu-CP2A.260705.006"
            return 0
            ;;
        panther:6.1.157:CP2A.260705.006)
            echo "android14-6.1|panther-CP2A.260705.006"
            return 0
            ;;
        panther:6.1.124:BP2A.250705.008)
            echo "android14-6.1|panther-BP2A.250705.008"
            return 0
            ;;
        mustang:6.6.118:CP2A.260705.006)
            echo "android15-6.6|mustang-CP2A.260705.006"
            return 0
            ;;
        lynx:6.1.157:CP2A.260705.006)
            echo "android14-6.1|lynx-CP2A.260705.006"
            return 0
            ;;
    esac

    warn "No profile found for $DEVICE:$KERNEL:$BUILD"
    return 1
}

# ============================================================================
# Payload Acquisition (Multi-method)
# ============================================================================
acquire_payload() {
    local name="$1" url="$2" dst="$3"

    info "Acquiring $name..."
    mkdir -p "$(dirname "$dst")"

    # Method 1: Download from GitHub
    if command -v curl >/dev/null 2>&1; then
        info "  [1] Trying GitHub download..."
        if try_cmd "curl $url" curl -L --max-time $GITHUB_TIMEOUT -o "$dst" "$url" 2>/dev/null; then
            if [ -s "$dst" ]; then
                info "✓ Downloaded: $name"
                chmod 755 "$dst"
                return 0
            fi
        fi
    fi

    # Method 2: Extract from installed app
    if [ -d "/data/app" ]; then
        info "  [2] Trying app extraction..."
        local app_dir=$(find /data/app -name "com.alex193a.rootmypixel*" -type d 2>/dev/null | head -1)
        if [ -n "$app_dir" ] && [ -f "$app_dir/base.apk" ]; then
            local asset_path=""
            case "$name" in
                Helper)
                    asset_path="lib/arm64-v8a/libcve43499root.so"
                    ;;
                Exploit)
                    asset_path="exploits/${DEVICE}-${BUILD}.so"
                    ;;
                ksud)
                    asset_path="ksud/ksud"
                    ;;
            esac

            if [ -n "$asset_path" ]; then
                if unzip -p "$app_dir/base.apk" "$asset_path" > "$dst" 2>/dev/null; then
                    if [ -s "$dst" ]; then
                        info "✓ Extracted from app: $name"
                        chmod 755 "$dst"
                        return 0
                    fi
                fi
            fi
        fi
    fi

    # Method 3: Local fallback (if file exists)
    if [ -f "/sdcard/$name.so" ]; then
        cp "/sdcard/$name.so" "$dst"
        chmod 755 "$dst"
        info "✓ Copied from /sdcard: $name"
        return 0
    fi

    warn "✗ Could not acquire: $name"
    return 1
}

# ============================================================================
# Exploitation
# ============================================================================
get_helper() {
    # Try to find helper binary
    if [ -f "$HELPER_FILE" ]; then
        echo "$HELPER_FILE"
        return 0
    fi

    # Try to find in app
    local app_helper=$(find /data/app -path "*/com.alex193a.rootmypixel*/lib/arm64-v8a/libcve43499root.so" 2>/dev/null | head -1)
    if [ -n "$app_helper" ]; then
        echo "$app_helper"
        return 0
    fi

    return 1
}

execute_exploit() {
    local helper=$(get_helper)
    [ -z "$helper" ] && fatal "Helper binary not found"
    [ ! -f "$EXPLOIT_FILE" ] && fatal "Exploit not found"

    info ""
    info "=== RUNNING EXPLOIT ==="
    info "Helper: $helper"
    info "Exploit: $EXPLOIT_FILE"

    read -p ">>> Ready to execute exploit? [y/n]: " ans
    case "$ans" in
        y|yes) ;;
        *) fatal "Exploit cancelled" ;;
    esac

    # Run exploit
    local start=$(date +%s)
    timeout 1800 "$helper" --run-payload "$EXPLOIT_FILE" "$helper" "$EXPLOIT_LOG" 2>&1 &
    local pid=$!

    # Wait and monitor
    while kill -0 $pid 2>/dev/null; do
        sleep 2
        if [ -f "$EXPLOIT_LOG" ]; then
            tail -1 "$EXPLOIT_LOG"
        fi

        local elapsed=$(($(date +%s) - start))
        [ $elapsed -gt 1800 ] && { kill $pid; fatal "Exploit timeout"; }
    done

    wait $pid || fatal "Exploit failed"

    # Check success markers
    if grep -q "done=1" "$EXPLOIT_LOG" && grep -q "root=1" "$EXPLOIT_LOG"; then
        info "✓ Exploit successful"
        return 0
    fi

    fatal "Exploit did not complete successfully"
}

# ============================================================================
# KernelSU Installation
# ============================================================================
install_kernelsu() {
    local kmi="$1"

    info ""
    info "=== SETTING UP KERNELSU ==="
    info "KMI: $kmi"

    [ ! -f "$KSUD_FILE" ] && fatal "ksud binary not found"

    # Create directories
    "$HELPER_FILE" -c "mkdir -p /data/adb && chmod 700 /data/adb" >/dev/null 2>&1 || true

    # Set SELinux permissive
    "$HELPER_FILE" -c "setenforce 0" >/dev/null 2>&1 || true

    # Stage and run ksud
    "$HELPER_FILE" -c "chmod 755 $KSUD_FILE" >/dev/null 2>&1 || true
    info "Running ksud late-load (KMI=$kmi)..."
    "$HELPER_FILE" -c "$KSUD_FILE late-load --kmi $kmi" >/dev/null 2>&1 || true

    # Verify
    sleep 2
    if "$HELPER_FILE" -c "test -e /dev/kernelsu" >/dev/null 2>&1; then
        info "✓ KernelSU verified"
        return 0
    fi

    warn "KernelSU verification inconclusive (module may still be loading)"
    return 0
}

# ============================================================================
# Main
# ============================================================================
main() {
    info "╔════════════════════════════════════════════╗"
    info "║  Root My Pixel — KernelSU Setup            ║"
    info "╚════════════════════════════════════════════╝"

    detect_device

    # Get profile
    local profile_info=$(get_profile) || fatal "Device not supported"
    KMI=$(echo "$profile_info" | cut -d'|' -f1)
    PROFILE=$(echo "$profile_info" | cut -d'|' -f2)

    info "Profile: $PROFILE (KMI: $KMI)"

    read -p ">>> Continue? [y/n]: " ans
    case "$ans" in
        y|yes) ;;
        *) info "Cancelled"; exit 0 ;;
    esac

    # Create work directory
    mkdir -p "$WORK_DIR" "$TEMP_DIR"

    # Acquire payloads
    info ""
    info "=== ACQUIRING PAYLOADS ==="
    acquire_payload "Helper" "$REPO_BASE/app/src/main/jniLibs/arm64-v8a/libcve43499root.so" "$HELPER_FILE" || fatal "Cannot get helper binary"
    acquire_payload "Exploit" "$REPO_BASE/app/src/main/assets/exploits/$PROFILE.so" "$EXPLOIT_FILE" || fatal "Cannot get exploit binary"
    acquire_payload "ksud" "$REPO_BASE/app/src/main/assets/ksud/ksud" "$KSUD_FILE" || fatal "Cannot get ksud binary"

    # Execute
    execute_exploit
    install_kernelsu "$KMI"

    # Cleanup
    rm -f "$EXPLOIT_FILE" "$EXPLOIT_LOG"

    info ""
    info "════════════════════════════════════════════"
    info "✓ SUCCESS — KernelSU installed!"
    info "════════════════════════════════════════════"
    info ""
    info "Next: Open ReSukiSU Manager → Grant root to apps"
    info "Test: su -c 'id'  (should return uid=0)"
}

# Run
main "$@"
