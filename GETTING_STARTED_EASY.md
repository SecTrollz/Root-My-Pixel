# Getting Started — Super Easy

This guide is for everyone. No tech knowledge needed.

## What You're Doing

You're installing **root access** on your Pixel phone. Root = unlimited control.

- ✅ Takes 5-10 minutes
- ✅ No computer needed (after initial setup)
- ✅ Phone stays normal, just gains root
- ✅ Can be undone by factory reset

## What You Need

**On your phone:**
1. Shizuku app (installed + running)
2. Root My Pixel app (installed)
3. Termux or any terminal

**Everything else:**
- WiFi or mobile data
- Pixel phone (listed below)
- Your phone charged to 50%+

## Supported Phones

- Pixel 10, 10 Pro, 10a
- Pixel 9, 9a, 9 Pro
- Pixel 8, 8a, 8 Pro
- Pixel 7, 7a, 7 Pro
- Pixel 6, 6a, 6 Pro

## Step 1: Install Shizuku (5 min)

Shizuku gives the exploit temporary power.

**On your Pixel:**

1. Go to **Settings → About phone**
2. Tap **Build number** 7 times (until it says "Developer")
3. Go back → **Settings → System → Developer options**
4. Turn on **Wireless debugging** (keep WiFi on)
5. Install **Shizuku app** from Google Play
6. Open Shizuku → Tap **"Pair device with pairing code"**
7. Follow the code → Confirm
8. Tap **"Start"** (Shizuku is now running)

✅ **Done!** Shizuku is running.

## Step 2: Install Root My Pixel (1 min)

Download from GitHub:
- Go to https://github.com/SecTrollz/Root-My-Pixel/releases
- Download latest `app-debug.apk`
- Install it (you'll get a warning, tap **"Install anyway"**)

✅ **Done!** App is installed.

## Step 3: Run the Easy Exploit (5 min)

Open Termux and copy-paste this:

```bash
cd /data/local/tmp
curl -L https://github.com/SecTrollz/Root-My-Pixel/raw/main/cli/rmp-easy -o rmp-easy
bash rmp-easy
```

Then:
1. Choose **Option 1** (Easy walkthrough)
2. Answer the questions (just type "yes")
3. **Keep your phone screen ON**
4. Wait for the green checkmarks

✅ **Done!** You have root!

## Step 4: Verify It Works (1 min)

Open Termux and type:

```bash
su
```

If it asks permission, tap **Allow**.

If you see `#` at the bottom, **you have root!** 🎉

Type `exit` to quit.

## What Now?

**To use root:**
- Open Termux → Type `su` → You're root
- Apps can ask for root via ReSukiSU

**To grant apps root:**
1. Open **ReSukiSU** app
2. Choose which apps get root
3. Done

**To keep it after restart:**
- Reboot your phone
- Restart Shizuku
- Root will still work

## Troubleshooting

**"Shizuku not running"**
- Make sure Wireless debugging is ON in Developer options
- Open Shizuku and tap Start again

**"Root My Pixel app not found"**
- Download it from GitHub releases (see Step 2)
- Make sure it installed (check Settings → Apps)

**"Exploit failed / timed out"**
- Keep your phone screen on
- Close other apps
- Try again in 30 seconds
- Make sure internet is working

**"It didn't work at all"**
- Reboot your phone
- Start Shizuku again
- Retry the exploit

## Got Root? What's Next?

### Popular root apps:
- **Termux** — Full Linux terminal
- **Magisk** — Mod system (if installed)
- **Titanium Backup** — Backup everything
- **AdAway** — Block ads system-wide

### Important:
- ⚠️ Some apps detect root and won't work
- ⚠️ Never grant root to apps you don't trust
- ⚠️ Factory reset removes root

## Advanced (If Needed)

Using the CLI directly:

```bash
# Interactive menu
bash cli/rmp-cli menu

# Full automation
bash cli/rmp-cli full

# Check status
bash cli/rmp-cli status
```

## Questions?

- Check **GETTING_STARTED.md** for more details
- See **cli/README.md** for all CLI options
- Visit GitHub issues if something's wrong

## Summary

| Step | What | Time |
|------|------|------|
| 1 | Install Shizuku | 5 min |
| 2 | Install app | 1 min |
| 3 | Run exploit | 5 min |
| 4 | Verify | 1 min |
| **Total** | **Root access!** | **~15 min** |

You've got this! 🚀
