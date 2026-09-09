#!/bin/bash
# Common utilities for RMP CLI

REPO="https://github.com/SecTrollz/Root-My-Pixel/raw/main"
TMP="${RMP_TEMP:-/data/local/tmp}"
QUIET="${RMP_QUIET:-0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREY='\033[0;90m'
NC='\033[0m'

# Logging
log_info() {
    [ "$QUIET" = "1" ] && return
    echo -e "${BLUE}[*]${NC} $*"
}

log_ok() {
    [ "$QUIET" = "1" ] && return
    echo -e "${GREEN}[✓]${NC} $*"
}

log_err() {
    echo -e "${RED}[!]${NC} $*" >&2
}

log_warn() {
    [ "$QUIET" = "1" ] && return
    echo -e "${YELLOW}[!]${NC} $*"
}

die() {
    log_err "$@"
    exit 1
}

prompt() {
    local msg="${1:-Continue?}"
    [ "$QUIET" = "1" ] && return 0

    while true; do
        echo ""
        read -p ">>> $msg (y/n): " ans
        case "$ans" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer 'y' or 'n'" ;;
        esac
    done
}

# Download with fallback (curl → wget)
download() {
    local url="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if command -v curl >/dev/null 2>&1; then
        curl -L --max-time 120 --progress-bar "$url" -o "$dst" 2>/dev/null && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget --timeout=120 -O "$dst" "$url" 2>/dev/null && return 0
    fi

    return 1
}

# Check if on Android
is_android() {
    [ -f /proc/version ] && grep -q Android /proc/version
}

# Get Android property
getprop() {
    if command -v getprop >/dev/null 2>&1; then
        command getprop "$1" 2>/dev/null || echo ""
    else
        echo ""
    fi
}
