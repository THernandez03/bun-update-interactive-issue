#!/usr/bin/env bash
# reproduce.sh — Capture bun update -i output via PTY for visual inspection.
#
# Usage:
#   bash reproduce.sh
#
# Requires: bun, script (util-linux on Linux/WSL, built-in on macOS)
set -euo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

BUN_VERSION=$(bun --version 2>/dev/null || echo "unknown")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/pty-output.txt"

echo ""
echo -e "${BOLD}bun update -i rendering regression reproducer${RESET}"
echo -e "Bun version: ${CYAN}${BUN_VERSION}${RESET}"
echo ""

# Install pinned outdated packages
echo -e "${BOLD}Installing packages...${RESET}"
cd "$SCRIPT_DIR"
bun install --no-progress 2>&1 | grep -v "^$" | head -5
echo ""

# Capture the interactive TUI output via a real PTY.
# bun update -i only renders in interactive (TTY) mode — `script` provides that.
echo -e "${BOLD}Capturing bun update -i output via PTY...${RESET}"
echo -e "      (Sending 'q' after 1s to exit the interactive UI)"
echo ""

rm -f "$OUTPUT_FILE"

OS="$(uname -s)"
INNER_CMD="FORCE_COLOR=1 TERM=xterm-256color TERM_PROGRAM= bun update -i"

if [[ "$OS" == "Darwin" ]]; then
  ( sleep 1; printf "q" ) | script -q "$OUTPUT_FILE" sh -c "$INNER_CMD" >/dev/null 2>&1 || true
else
  ( sleep 1; printf "q" ) | script -q -c "$INNER_CMD" "$OUTPUT_FILE" >/dev/null 2>&1 || true
fi

if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
  echo "⚠  PTY capture produced no output."
  echo "   Run manually in a real terminal: FORCE_COLOR=1 bun update -i"
  exit 1
fi

# Strip ANSI/OSC escape sequences so the visible text is readable
sed \
  -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
  -e 's/\x1b\][^\x07]*\(\x07\|\x1b\\\)//g' \
  -e 's/\x1b[^[]//g' \
  -e 's/[^[:print:][:space:]]//g' \
  "$OUTPUT_FILE"

echo ""
echo "Raw PTY bytes saved to: $OUTPUT_FILE"
echo ""
echo "Expected (v1.3.14):"
echo "  □ ai      0.0.1   0.0.1   6.0.191"
echo "  □ git-cz  1.8.4   1.8.4   4.9.0"
echo "  □ taze    0.18.0  0.18.0  19.14.1"
echo ""
echo "Actual (v1.4.0):"
echo "  □ ai....0.0.1....0.0.1....6.0.191"
echo "  □ git-cz....1.8.4....1.8.4....4.9.0"
echo "  □ taze....0.18.0....0.18.0....19.14.1"
