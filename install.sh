#!/bin/bash
# One-line installer – works on a brand-new Mac, nothing needs to be installed first:
#
#   curl -fsSL https://raw.githubusercontent.com/ronaldjonkers/mac-initial-setup/main/install.sh | bash
#
# Downloads the latest release (desktop app + scripts) to ~/.mac-initial-setup and opens the app.
# Add "-s -- --tui" to use the terminal checklist instead:  … | bash -s -- --tui
set -e

REPO=${MAC_SETUP_REPO:-ronaldjonkers/mac-initial-setup}
DEST="$HOME/.mac-initial-setup"
TUI=0
ARGS=()
for a in "$@"; do
  case $a in --tui) TUI=1 ;; *) ARGS+=("$a") ;; esac
done

[ "$(uname -s)" = Darwin ] || { echo "This only runs on macOS."; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "› Downloading mac-initial-setup…"
if curl -fsSL "https://github.com/$REPO/releases/latest/download/mac-initial-setup.tar.gz" -o "$tmp/release.tar.gz"; then
  tar -xzf "$tmp/release.tar.gz" -C "$tmp"
  src="$tmp/mac-initial-setup"
else
  # No release yet: use the scripts from the main branch (terminal checklist only).
  echo "  (no release found, using the main branch)"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp"
  src=$(find "$tmp" -maxdepth 1 -type d -name 'mac-initial-setup*' | head -1)
  TUI=1
fi

rm -rf "$DEST"
mv "$src" "$DEST"

if [ "$TUI" = 0 ] && [ -x "$DEST/bin/mac-setup" ]; then
  echo "› Opening the app…"
  exec "$DEST/bin/mac-setup" ${ARGS[@]+"${ARGS[@]}"}
fi

# stdin is the curl pipe; give the terminal checklist the keyboard back.
exec /bin/bash "$DEST/setup.sh" ${ARGS[@]+"${ARGS[@]}"} </dev/tty
