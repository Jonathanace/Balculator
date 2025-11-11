#!/bin/bash

# --- Configuration: CHANGE THESE VALUES ---
ORIGINAL_FILE="original_game_files/main.lua"
MODIFIED_FILE="game/game_files/main.lua"
PATCH_NAME="main_lua_patch.patch"
# -----------------------------------------

echo "Creating $PATCH_NAME..."

diff -u "$ORIGINAL_FILE" "$MODIFIED_FILE" > "$PATCH_NAME"

# A simple status check
if [ $? -eq 0 ]; then
    echo "✅ Success! Patch file created."
else
    echo "⚠️ Diff ran, but check the output for errors or warnings (exit code: $?)."
fi