#!/bin/bash
# One-line installer – works on a brand-new Mac, nothing needs to be installed first:
#
#   curl -fsSL https://raw.githubusercontent.com/ronaldjonkers/mac-initial-setup/main/install.sh | bash
#
# Downloads the main branch (desktop app + scripts) to ~/.mac-initial-setup and opens the app.
# Add "-s -- --tui" to use the terminal checklist instead:  … | bash -s -- --tui
set -euo pipefail

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
curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" -o "$tmp/source.tar.gz"
tar -xzf "$tmp/source.tar.gz" -C "$tmp"
src="$tmp/${REPO##*/}-main"
[ -f "$src/setup.sh" ] && [ -x "$src/bin/mac-setup" ] || {
  echo "The main branch is missing setup.sh or the desktop app binary." >&2
  exit 1
}

if pgrep -f "$DEST/(bin/mac-setup|setup.sh)" >/dev/null; then
  echo "A setup run from $DEST is still active. Try again when it finishes." >&2
  exit 1
fi

if [ -e "$DEST" ]; then mv "$DEST" "$tmp/previous"; fi
if ! mv "$src" "$DEST"; then
  [ ! -e "$tmp/previous" ] || mv "$tmp/previous" "$DEST"
  exit 1
fi
rm -rf "$tmp"
trap - EXIT

if [ "$TUI" = 0 ]; then
  echo "› Opening the app…"
  exec "$DEST/bin/mac-setup" ${ARGS[@]+"${ARGS[@]}"}
fi

# stdin is the curl pipe; give the terminal checklist the keyboard back.
exec /bin/bash "$DEST/setup.sh" ${ARGS[@]+"${ARGS[@]}"} </dev/tty
