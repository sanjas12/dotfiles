#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VSCODE_DIR="$HOME/.config/Code/User"

echo "Каталог скрипта: $SCRIPT_DIR"
echo "Каталог VS Code: $VSCODE_DIR"

mkdir -p "$VSCODE_DIR"

cp "$SCRIPT_DIR/settings.json" "$VSCODE_DIR/settings.json"
cp "$SCRIPT_DIR/keybindings.json" "$VSCODE_DIR/keybindings.json"

echo "Настройки VS Code успешно скопированы."