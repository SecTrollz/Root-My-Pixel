#!/system/bin/sh
# Unroot and restore stock state for Root-My-Pixel.

LOG_FILE="/data/local/tmp/unr00t.log"
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
        [ -n "$output" ] && log "    [SUCCESS] $output" || log "    [SUCCESS]"
    else
        [ -n "$output" ] && log "    [FAILED (exit $status)] $output" || log "    [FAILED (exit $status)]"
    fi
    return $status
}

exec_root() {
    local cmd="$1"
    local out
    local status

    # A direct invocation through the CVE client can already be root.
    if [ "$(id -u)" = "0" ]; then
        /system/bin/sh -c "$cmd"
        return $?
    fi

    # ReSukiSU/KernelSU, when the calling identity has been granted root.
    if command -v su >/dev/null 2>&1; then
        out=$(su -c "$cmd" 2>&1)
        status=$?
        if [ $status -eq 0 ]; then
            [ -n "$out" ] && echo "$out"
            return 0
        fi
    fi

    # The temporary client is accepted by the CVE daemon for the shell UID.
    if [ -x /data/local/tmp/su ] && [ -S /data/local/tmp/temp_su.sock ]; then
        out=$(/data/local/tmp/su -c "$cmd" 2>&1)
        status=$?
        if [ $status -eq 0 ]; then
            [ -n "$out" ] && echo "$out"
            return 0
        fi
    fi

    echo "root execution unavailable"
    return 1
}

# Keep privileged changes separate from shell-accessible cleanup. A reboot
# tears down the CVE daemon and all mount namespaces, so broad process matches
# are neither required nor safe.
ROOT_CLEANUP='rm -rf /data/adb || exit 1; umount /apex/com.android.virt/bin 2>/dev/null || true; setenforce 1 2>/dev/null || true'
TMP_CLEANUP='rm -f /data/local/tmp/cve-2026-43499-app.so /data/local/tmp/cve-2026-43499-root /data/local/tmp/ksud-pixel /data/local/tmp/su /data/local/tmp/.su.new.* /data/local/tmp/temp_su.sock /data/local/tmp/exploit.log /data/local/tmp/su_daemon.log'

log "[1/3] Cleaning privileged root state..."
if exec_root "$ROOT_CLEANUP"; then
    log "    [SUCCESS] KernelSU state and temporary APEX mount cleaned"
else
    log "    [INFO] No root transport in this shell; the app fallback may have already cleaned it"
fi

log "[2/3] Cleaning temporary CVE and ReSukiSU files..."
if exec_root "$TMP_CLEANUP"; then
    log "    [SUCCESS] Temporary files removed with root"
else
    run_cmd "Removing shell-accessible temporary files..." rm -f \
        /data/local/tmp/cve-2026-43499-app.so \
        /data/local/tmp/cve-2026-43499-root \
        /data/local/tmp/ksud-pixel \
        /data/local/tmp/su \
        /data/local/tmp/.su.new.* \
        /data/local/tmp/temp_su.sock \
        /data/local/tmp/exploit.log \
        /data/local/tmp/su_daemon.log
fi

log "[3/3] Rebooting to terminate the daemon and unload KernelSU..."
sync
if exec_root "svc power reboot || reboot"; then
    log "    [SUCCESS] Reboot requested as root"
elif run_cmd "Requesting reboot as shell..." svc power reboot; then
    log "    [SUCCESS] Reboot requested as shell"
else
    run_cmd "Requesting fallback reboot..." reboot
fi
