#!/system/bin/sh
# Unroot and restore stock state for Root-My-Pixel

# 1. Root cleanup via temporary root daemon if still active
if [ -e "/data/local/tmp/temp_su.sock" ] || [ -x "/data/local/tmp/su" ]; then
    /data/local/tmp/su -c "rm -rf /data/adb /data/adb/* 2>/dev/null" 2>/dev/null || true
    /data/local/tmp/su -c "umount /apex/com.android.virt/bin 2>/dev/null" 2>/dev/null || true
    /data/local/tmp/su -c "setenforce 1 2>/dev/null" 2>/dev/null || true
fi

# 2. Terminate exploit and daemon processes
pkill -f "cve-2026-43499" 2>/dev/null || true
pkill -f "su_daemon" 2>/dev/null || true
pkill -f "cve43499_roothold" 2>/dev/null || true
pkill -f "ksud" 2>/dev/null || true

# 3. Remove all temporary exploit files, payloads, sockets, and logs
rm -f /data/local/tmp/cve-2026-43499* \
      /data/local/tmp/ksud* \
      /data/local/tmp/su \
      /data/local/tmp/.su.new.* \
      /data/local/tmp/temp_su.sock \
      /data/local/tmp/exploit.log \
      /data/local/tmp/su_daemon.log 2>/dev/null || true

# 4. Trigger reboot to reset kernel RAM to stock
svc power reboot 2>/dev/null || reboot 2>/dev/null || true
