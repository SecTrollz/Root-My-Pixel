#!/bin/bash
# Payload management module

get_all_payloads() {
    log_info "Sourcing payloads..."

    mkdir -p "$CACHE_DIR" "$TMP"

    # Try APK extraction first
    extract_from_apk && {
        log_ok "Extracted from APK"
        return 0
    }

    # Fallback to download
    download_payloads || die "Failed to get payloads"
    log_ok "Downloaded payloads"
}

extract_from_apk() {
    local apk_dir=$(find /data/app -name 'com.alex193a.rootmypixel*' -type d 2>/dev/null | head -1)
    [ -z "$apk_dir" ] && return 1

    local apk="$apk_dir/base.apk"
    [ ! -f "$apk" ] && return 1

    log_info "Extracting from APK..."

    unzip -p "$apk" "exploits/${TARGET}.so" > "$CACHE_DIR/exploit.so" 2>/dev/null || return 1
    unzip -p "$apk" "ksud/ksud" > "$CACHE_DIR/ksud" 2>/dev/null || return 1
    unzip -p "$apk" "lib/arm64-v8a/libcve43499root.so" > "$CACHE_DIR/helper.so" 2>/dev/null || return 1

    chmod 755 "$CACHE_DIR"/*.so "$CACHE_DIR/ksud"
    return 0
}

download_payloads() {
    log_info "Downloading payloads..."

    download "$REPO/app/src/main/assets/exploits/${TARGET}.so" "$CACHE_DIR/exploit.so" || return 1
    download "$REPO/app/src/main/assets/ksud/ksud" "$CACHE_DIR/ksud" || return 1
    download "$REPO/releases/download/latest/libcve43499root.so" "$CACHE_DIR/helper.so" || return 1

    chmod 755 "$CACHE_DIR"/*.so "$CACHE_DIR/ksud"
    return 0
}

stage_payloads() {
    log_info "Staging payloads to $TMP..."

    cp "$CACHE_DIR/exploit.so" "$TMP/cve-2026-43499-app.so" || return 1
    cp "$CACHE_DIR/ksud" "$TMP/ksud-pixel" || return 1
    cp "$CACHE_DIR/helper.so" "$TMP/libcve43499root.so" || return 1

    chmod 755 "$TMP"/*.so "$TMP/ksud-pixel"
    log_ok "Payloads staged"
}

export -f get_all_payloads extract_from_apk download_payloads stage_payloads
