# Root My Pixel CLI Suite

Mobile-friendly bash CLI for on-device exploitation and KernelSU installation. Modular design with independent commands that can be run together or separately.

## Quick Start

```bash
# On Termux or mobile terminal
bash cli/rmp-cli full
```

Or interactive:
```bash
bash cli/rmp-cli menu
```

## Commands

| Command | Description |
|---------|-------------|
| `detect` | Detect device (codename, build, target) |
| `download` | Download/extract payloads from APK or GitHub |
| `exploit` | Execute CVE-2026-43499 exploit |
| `install` | Install KernelSU (requires exploit first) |
| `full` | Complete workflow (all 4 steps) |
| `menu` | Interactive menu |
| `status` | Show device & setup status |
| `clean` | Remove cached payloads |
| `help` | Show this help |

## Module Structure

```
cli/
├── rmp-cli              # Main orchestration script
└── lib/
    ├── common.sh        # Shared utilities (logging, download, etc)
    ├── detect.sh        # Device detection & target resolution
    ├── payload.sh       # Payload extraction/download
    ├── exploit.sh       # Exploit execution & monitoring
    └── kernelsu.sh      # KernelSU installation
```

## Workflow

### Full Automation
```bash
bash cli/rmp-cli full
```

Runs all 4 steps with user prompts:
1. Detect your Pixel device
2. Download exploit + ksud binaries
3. Execute CVE-2026-43499
4. Install KernelSU

### Step-by-Step
```bash
bash cli/rmp-cli detect      # Identify device
bash cli/rmp-cli download    # Get payloads
bash cli/rmp-cli exploit     # Run exploit
bash cli/rmp-cli install     # Setup KernelSU
```

### Interactive Menu
```bash
bash cli/rmp-cli menu
```

Presents numbered options for each command.

## Supported Devices

All Pixel phones with CVE-2026-43499 exploits:
- Pixel 10, 10 Pro, 10 Pro XL, 10 Pro Fold, 10a
- Pixel 9, 9a, 9 Pro, 9 Pro XL, 9 Pro Fold
- Pixel 8, 8a, 8 Pro
- Pixel 7, 7a, 7 Pro
- Pixel 6, 6a, 6 Pro

See `../README.md` for full device list.

## Requirements

- **Android device** (Termux recommended)
- **Shizuku** running (UID 2000 via Wireless Debugging)
- **Root My Pixel app** installed
- **Bash 4+**, curl/wget, unzip

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RMP_DEVICE` | auto-detect | Force device codename (skip detection) |
| `RMP_TEMP` | `/data/local/tmp` | Temporary directory for payloads |
| `RMP_QUIET` | 0 | Suppress output (1 for quiet) |

## Examples

**Skip device detection:**
```bash
RMP_DEVICE=tegu bash cli/rmp-cli full
```

**Quiet mode (minimal output):**
```bash
RMP_QUIET=1 bash cli/rmp-cli full
```

**Custom temp directory:**
```bash
RMP_TEMP=/sdcard/tmp bash cli/rmp-cli download
```

**Check status only:**
```bash
bash cli/rmp-cli status
```

## Logging

- **Colors:** INFO (blue), OK (green), WARN (yellow), ERROR (red)
- **Progress:** Real-time exploit output streamed to terminal
- **Logs:** Exploit details saved to `/data/local/tmp/exploit.log`

## Troubleshooting

**"Command not found"**
- Bash must be in PATH: `which bash`
- On Termux: `pkg install bash`

**"Helper not found"**
- Root My Pixel app must be installed
- Shizuku must be running (UID 2000)

**"Payload download failed"**
- Check internet connection
- App may fall back to APK extraction if available

**Exploit stalls**
- Device may be in recovery mode (reboot to system)
- Shizuku service may have crashed (restart it)

## Mobile-Friendly Design

- **Minimal dependencies:** bash, curl/wget, unzip (standard on Termux)
- **Small scripts:** Each module ~50-100 lines
- **Modular:** Commands work independently or together
- **Interactive:** Menu-driven or full-automation modes
- **Responsive:** Real-time progress output
- **Cacheable:** Payloads stored locally to avoid re-downloads

## License

Same as Root My Pixel (see `../LICENSE`)
