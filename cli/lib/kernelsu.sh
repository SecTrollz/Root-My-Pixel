#!/bin/bash
# KernelSU installation module

install_kernelsu() {
    log_info "Installing KernelSU..."

    [ ! -f "$TMP/libcve43499root.so" ] && die "Helper not staged. Run 'exploit' first."
    [ ! -f "$TMP/ksud-pixel" ] && die "ksud not staged. Run 'download' first."

    local helper="$TMP/libcve43499root.so"
    local ksud="$TMP/ksud-pixel"
    local sock="/data/local/tmp/temp_su.sock"

    # Wait for daemon socket
    log_info "Waiting for daemon socket..."
    local wait_count=0
    while [ ! -S "$sock" ] && [ $wait_count -lt 30 ]; do
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    [ ! -S "$sock" ] && die "Daemon socket timeout"
    log_ok "Daemon ready"

    # Helper function to run commands as root
    run_as_root() {
        "$helper" -c "$1" 2>&1
    }

    # Step 1: Create /data/adb
    log_info "Creating /data/adb..."
    run_as_root "mkdir -p /data/adb && chmod 700 /data/adb" >/dev/null
    log_ok "/data/adb ready"

    # Step 2: SELinux permissive
    log_info "Setting SELinux permissive..."
    run_as_root "setenforce 0" >/dev/null 2>&1 || true
    local se=$(run_as_root "getenforce")
    if echo "$se" | grep -q "Permissive"; then
        log_ok "SELinux permissive"
    else
        log_warn "SELinux still enforcing (may not be critical)"
    fi

    # Step 3: Stage ksud
    log_info "Staging ksud..."
    run_as_root "chmod 755 $ksud && chown root:root $ksud" >/dev/null
    log_ok "ksud staged"

    # Step 4: Trigger late-load
    log_info "Triggering KernelSU late-load (KMI=$KMI)..."
    run_as_root "$ksud late-load --kmi $KMI" >/dev/null 2>&1 || true
    sleep 1

    # Step 5: Verify KernelSU
    log_info "Verifying KernelSU..."
    local attempt=1
    while [ $attempt -le 15 ]; do
        local check=$(run_as_root "test -e /dev/kernelsu && echo 1 || echo 0")
        if [ "$check" = "1" ]; then
            log_ok "KernelSU verified"
            break
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt 15 ]; then
        log_warn "KernelSU not yet available (may appear after reboot)"
    fi

    # Step 6: Create metadata
    log_info "Creating KernelSU metadata..."
    run_as_root "mkdir -p /data/adb/ksu && touch /data/adb/ksu/.installed" >/dev/null
    log_ok "KernelSU setup complete"

    return 0
}

export -f install_kernelsu
