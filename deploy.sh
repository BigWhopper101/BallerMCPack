#!/usr/bin/env bash
# deploy.sh — Zip BallerMCPack and push a GitHub release, nya~!
# Usage: ./deploy.sh [version-name]
#   With no args, uses "latest" (overwrites previous)
#   With a name like "v1.2", creates that as a versioned release

set -e

NAME="${1:-latest}"
PACK_DIR="/home/bigwhopper/Downloads/MinecraftStuff/Texture Packs/Custom/BallerMCPack"
ZIP_FILE="/tmp/BallerMCPack.zip"

cd "$PACK_DIR"

# Step 1: Zip it up (exclude .git folder and other junk)
echo "  (=^･ω･^=)  Zipping BallerMCPack..."
zip -r "$ZIP_FILE" . -x ".git/*" ".gitignore" "*.zip" > /dev/null

ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo "  Zipped! ($ZIP_SIZE)"

# Step 2: Check if release already exists
if gh release view "$NAME" --json name > /dev/null 2>&1; then
    echo "  Release \"$NAME\" exists — deleting and recreating..."
    gh release delete "$NAME" --yes
fi

# Step 3: Create release and upload
echo "  Uploading to GitHub..."
gh release create "$NAME" \
    --title "BallerMCPack ${NAME}" \
    --notes "Auto-deployed $(date '+%Y-%m-%d %H:%M')" \
    "$ZIP_FILE"

# Step 4: Clean up
rm "$ZIP_FILE"

echo ""
echo "  ฅ^•ﻌ•^ฅ  Done! Download URL:"
echo "  https://github.com/BigWhopper101/BallerMCPack/releases/download/${NAME}/BallerMCPack.zip"
