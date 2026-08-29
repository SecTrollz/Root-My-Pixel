#!/system/bin/sh
# Unroot and restore stock state for Root-My-Pixel

LOG_FILE="/data/local/tmp/unroot.log"
echo "=== Unroot started at $(date) ===" > "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date +%T)] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date +%T)] $*"
}

run_cmd() {
    local desc="$1"
    shift
    log "--> $desc"
    local output
    output=$("$@" 2>&1)
    local status=$?
    if [ $status -eq 0 ]; then
        if [ -n "$output" ]; then
            log "    [SUCCESS] $output"
        else
            log "    [SUCCESS]"
        fi
    else
        if [ -n "$output" ]; then
            log "    [FAILED (exit $status)] $output"
        else
            log "    [FAILED (exit $status)]"
        fi
    fi
    return $status
}

exec_root() {
    local cmd="$1"
    # 1. Try system su in PATH (KernelSU)
    if command -v su >/dev/null 2>&1; then
        local out
        out=$(su -c "$cmd" 2>&1)
        if [ $? -eq 0 ]; then
            [ -n "$out" ] && echo "$out"
            return 0
        fi
    fi

    # 2. Try standard /system/bin/su
    if [ -x "/system/bin/su" ]; then
        local out
        out=$(/system/bin/su -c "$cmd" 2>&1)
        if [ $? -eq 0 ]; then
            [ -n "$out" ] && echo "$out"
            return 0
        fi
    fi

    # 3. Try local exploit daemon su binary
    if [ -x "/data/local/tmp/su" ] && [ -e "/data/local/tmp/temp_su.sock" ]; then
        local out
        out=$(/data/local/tmp/su -c "$cmd" 2>&1)
        if [ $? -eq 0 ]; then
            [ -n "$out" ] && echo "$out"
            return 0
        fi
    fi

    echo "root execution unavailable (SELinux enforcing or daemon offline)"
    return 1
}

log "[1/4] Cleaning root configurations..."
run_cmd "Cleaning /data/adb..." exec_root "rm -rf /data/adb /data/adb/*"
run_cmd "Unmounting Virt APEX..." exec_root "umount /apex/com.android.virt/bin"
run_cmd "Restoring SELinux enforcing..." exec_root "setenforce 1"

log "[2/4] Terminating exploit processes..."
run_cmd "Killing cve-2026-43499..." pkill -f "cve-2026-43499"
run_cmd "Killing su_daemon..." pkill -f "su_daemon"
run_cmd "Killing cve43499_roothold..." pkill -f "cve43499_roothold"
run_cmd "Killing ksud..." pkill -f "ksud"

log "[3/4] Cleaning temporary files in /data/local/tmp..."
run_cmd "Removing exploit binaries and logs..." rm -f \
    /data/local/tmp/cve-2026-43499* \
    /data/local/tmp/ksud* \
    /data/local/tmp/su \
    /data/local/tmp/.su.new.* \
    /data/local/tmp/temp_su.sock \
    /data/local/tmp/exploit.log \
    /data/local/tmp/su_daemon.log

log "[4/4] Triggering system reboot..."
log "=== Unroot script finished, issuing reboot ==="
if ! run_cmd "Issuing svc power reboot..." svc power reboot; then
    run_cmd "Issuing fallback reboot..." reboot
fi
