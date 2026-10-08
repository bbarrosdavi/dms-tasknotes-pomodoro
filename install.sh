#!/usr/bin/env bash
# install.sh - Installer for DMS TaskNotes Pomodoro Integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMS_PLUGINS_DIR="${HOME}/.config/DankMaterialShell/plugins"
NIRI_DIR="${HOME}/.config/niri"

echo "=== Installing DMS TaskNotes Pomodoro Plugin ==="

# 1. Install DMS Plugin
mkdir -p "${DMS_PLUGINS_DIR}"
TARGET_DMS="${DMS_PLUGINS_DIR}/tasknotesPomodoro"
if [ -L "${TARGET_DMS}" ] || [ -d "${TARGET_DMS}" ]; then
    echo "  [i] Replacing existing DMS plugin at ${TARGET_DMS}"
    rm -rf "${TARGET_DMS}"
fi
ln -sf "${SCRIPT_DIR}/dms-plugin" "${TARGET_DMS}"
echo "  [✓] Linked DMS plugin -> ${TARGET_DMS}"

# 2. Check for Obsidian Vaults
OBSIDIAN_CONFIG="${HOME}/.config/obsidian/obsidian.json"
VAULT_PATH=""

if [ -f "${OBSIDIAN_CONFIG}" ] && command -v jq >/dev/null 2>&1; then
    VAULT_PATH=$(jq -r '.vaults[] | select(.open == true) | .path' "${OBSIDIAN_CONFIG}" 2>/dev/null | head -n 1 || true)
fi

if [ -z "${VAULT_PATH}" ] && [ $# -gt 0 ]; then
    VAULT_PATH="$1"
fi

if [ -n "${VAULT_PATH}" ] && [ -d "${VAULT_PATH}/.obsidian/plugins" ]; then
    TARGET_OBS="${VAULT_PATH}/.obsidian/plugins/tasknotes-dms-bridge"
    echo "  [i] Detected Obsidian vault at: ${VAULT_PATH}"
    mkdir -p "${TARGET_OBS}"
    cp -r "${SCRIPT_DIR}/obsidian-plugin/"* "${TARGET_OBS}/"
    echo "  [✓] Installed Obsidian bridge plugin to ${TARGET_OBS}"
else
    echo "  [!] To install the Obsidian bridge plugin manually, copy 'obsidian-plugin/' to:"
    echo "      <your-vault>/.obsidian/plugins/tasknotes-dms-bridge"
fi

# 3. Inform about Niri window rule
echo ""
echo "=== Niri Wayland Configuration ==="
echo "Add the following window rule to your Niri configuration (~/.config/niri/config.kdl or dms/windowrules.kdl):"
cat "${SCRIPT_DIR}/niri/windowrules.kdl"
echo ""
echo "Installation complete! Run 'dms restart' and restart Obsidian to activate."
