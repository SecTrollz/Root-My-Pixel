#!/bin/bash
# Root My Pixel — One-Command Installer
# Just run this, answer questions, get root!

set -e

echo "╔═════════════════════════════════════════╗"
echo "║   ROOT MY PIXEL - AUTOMATIC SETUP       ║"
echo "╚═════════════════════════════════════════╝"
echo ""

# Download the easy mode script
echo "📥 Downloading Root My Pixel..."
INSTALL_DIR="${1:-.}/rmp-cli"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Get the latest CLI suite
echo "Fetching files..."
curl -sL https://github.com/SecTrollz/Root-My-Pixel/raw/main/cli/rmp-easy -o rmp-easy 2>/dev/null || {
    echo "❌ Download failed. Check internet connection."
    exit 1
}

curl -sL https://github.com/SecTrollz/Root-My-Pixel/raw/main/cli/rmp-cli -o rmp-cli 2>/dev/null || {
    echo "❌ Download failed. Check internet connection."
    exit 1
}

# Download lib files
mkdir -p lib
for file in common.sh detect.sh payload.sh exploit.sh kernelsu.sh; do
    echo -n "  $file ... "
    curl -sL "https://github.com/SecTrollz/Root-My-Pixel/raw/main/cli/lib/$file" -o "lib/$file" 2>/dev/null && echo "✅" || echo "⚠️"
done

chmod +x rmp-easy rmp-cli

echo ""
echo "✅ Installation complete!"
echo ""
echo "To start: bash rmp-easy"
echo ""
