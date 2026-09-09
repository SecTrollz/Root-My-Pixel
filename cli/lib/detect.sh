#!/bin/bash
# Device detection module

detect_device() {
    log_info "Detecting device..."

    DEVICE="${RMP_DEVICE:-$(getprop ro.product.device)}"
    BUILD="$(getprop ro.build.display.id)"
    MODEL="$(getprop ro.product.model)"
    KERNEL=$(cat /proc/version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[-a-zA-Z0-9]*' | head -1)

    [ -z "$DEVICE" ] && die "Could not detect device"

    log_info "Device: $DEVICE ($MODEL)"
    log_info "Build: $BUILD"
    log_info "Kernel: $KERNEL"

    # Resolve target and KMI
    resolve_target "$DEVICE" "$BUILD" || die "Unsupported device: $DEVICE/$BUILD"

    log_ok "Target: $TARGET (KMI: $KMI)"
}

resolve_target() {
    local dev="$1"
    local build="$2"

    case "$dev:$build" in
        tegu:CP2A.260705.006)     TARGET="tegu-CP2A.260705.006"; KMI="android14-6.1" ;;
        panther:CP2A.260705.006)  TARGET="panther-CP2A.260705.006"; KMI="android14-6.1" ;;
        panther:BP2A.250705.008)  TARGET="panther-BP2A.250705.008"; KMI="android14-6.1" ;;
        lynx:CP2A.260705.006)     TARGET="lynx-CP2A.260705.006"; KMI="android14-6.1" ;;
        mustang:CP2A.260705.006)  TARGET="mustang-CP2A.260705.006"; KMI="android15-6.6" ;;
        blazer:CP2A.260705.006)   TARGET="blazer-CP2A.260705.006"; KMI="android15-6.6" ;;
        caiman:CP2A.260705.006)   TARGET="caiman-CP2A.260705.006"; KMI="android14-6.1" ;;
        komodo:CP2A.260705.006)   TARGET="komodo-CP2A.260705.006"; KMI="android14-6.1" ;;
        tokay:CP2A.260705.006)    TARGET="tokay-CP2A.260705.006"; KMI="android14-6.1" ;;
        comet:CP2A.260705.006)    TARGET="comet-CP2A.260705.006"; KMI="android14-6.1" ;;
        rango:CP2A.260705.006)    TARGET="rango-CP2A.260705.006"; KMI="android15-6.6" ;;
        frankel:CP2A.260705.006)  TARGET="frankel-CP2A.260705.006"; KMI="android15-6.6" ;;
        husky:CP2A.260705.006)    TARGET="husky-CP2A.260705.006"; KMI="android14-6.1" ;;
        shiba:CP2A.260705.006)    TARGET="shiba-CP2A.260705.006"; KMI="android14-6.1" ;;
        akita:CP2A.260805.005)    TARGET="akita-CP2A.260805.005"; KMI="android14-6.1" ;;
        cheetah:CP2A.260705.006)  TARGET="cheetah-CP2A.260705.006"; KMI="android14-6.1" ;;
        oriole:CP2A.260705.006)   TARGET="oriole-CP2A.260705.006"; KMI="android14-6.1" ;;
        raven:CP2A.260705.006)    TARGET="raven-CP2A.260705.006"; KMI="android14-6.1" ;;
        bluejay:CP2A.260705.006)  TARGET="bluejay-CP2A.260705.006"; KMI="android14-6.1" ;;
        bluejay:CP1A.260405.005)  TARGET="bluejay-CP1A.260405.005"; KMI="android14-6.1" ;;
        stallion:CP2A.260805.005) TARGET="stallion-CP2A.260805.005"; KMI="android14-6.1" ;;
        *)                        return 1 ;;
    esac
    return 0
}

export -f detect_device resolve_target
