#!/bin/bash
# mac-initial-setup – set up a new Mac with your apps and settings.
# https://github.com/ronaldjonkers/mac-initial-setup  ·  MIT license

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/lib/common.sh"
. "$ROOT/lib/ui.sh"
for f in "$ROOT"/modules/*.sh; do . "$f"; done
. "$ROOT/catalog.sh"
# Work from the home folder: installers (Homebrew, git) fail when the current folder disappears,
# for example when the app folder is replaced by an update while a run is going.
cd "$HOME" || exit 1

LOG="$HOME/Library/Logs/mac-initial-setup.log"
ONLY="" ENABLE="" DISABLE="" INTERACTIVE=1 GUI_RUN=0

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

  (no options)        Interactive checklist; everything is pre-selected the way the author likes it
  -y, --yes           No checklist, no questions: install the defaults
  -n, --dry-run       Show what would happen, change nothing
      --only a,b      Run only these item ids
      --enable a,b    Also select these items
      --disable a,b   Deselect these items
  -l, --list          List all items and settings
  -h, --help          This help

Settings can be preset with environment variables, e.g.
  MAC_SETUP_SSH_USER=jane MAC_SETUP_GIT_EMAIL=jane@example.com ./setup.sh
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    -y|--yes)     ASSUME_YES=1; INTERACTIVE=0 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --only)       ONLY=$2; INTERACTIVE=0; shift ;;
    --enable)     ENABLE=$2; shift ;;
    --disable)    DISABLE=$2; shift ;;
    -l|--list)    print_catalog; exit 0 ;;
    --json)       print_json; exit 0 ;;
    --gui-run)    GUI_RUN=1; GUI=1; INTERACTIVE=0 ;;
    -h|--help)    usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

[ "$(uname -s)" = Darwin ] || { err "This script only runs on macOS."; exit 1; }
[ "$(id -u)" = 0 ] && { err "Run this as your normal user, not with sudo."; exit 1; }

[ -n "$ONLY" ] && select_only "$ONLY"
[ "$GUI_RUN" = 1 ] && [ -z "$ONLY" ] && { for i in "${!I_SEL[@]}"; do I_SEL[i]=0; done; }
# In GUI mode answers arrive on stdin; give commands /dev/null so nothing can steal them.
[ "$GUI" = 1 ] && exec 3<&0 </dev/null
[ -n "$ENABLE" ] && set_items "$ENABLE" 1
[ -n "$DISABLE" ] && set_items "$DISABLE" 0

if [ "$INTERACTIVE" = 1 ]; then
  has_tty || { err "No terminal available; use --yes for a non-interactive run."; exit 1; }
  ui_run || { log "Cancelled – nothing was changed."; exit 0; }
fi

total=$(count_selected)
[ "$total" -gt 0 ] || { log "Nothing selected."; exit 0; }

printf '\n%s%d items selected.%s' "$C_BOLD" "$total" "$C_RESET"
[ "$DRY_RUN" = 1 ] && printf ' %s(dry run – nothing will be changed)%s' "$C_YELLOW" "$C_RESET"
printf '\n'
if [ "$INTERACTIVE" = 1 ] && ! ask "Start now?" y; then log "Cancelled."; exit 0; fi

# Log everything from here on.
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
log "---- $(date) ----"

# Ask for the password once and keep sudo alive; keep the Mac awake.
if [ "$DRY_RUN" = 0 ]; then
  if [ -n "${SUDO_ASKPASS:-}" ]; then
    sudo -v || { err "Wrong password"; exit 1; }
  else
    info "Your password is needed for a few system changes."
    sudo -v </dev/tty || exit 1
  fi
  ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
  caffeinate -dimsu -w $$ &
fi

DONE=() FAILED=()
current_section=-1
for i in "${!I_ID[@]}"; do
  [ "${I_SEL[i]}" = 1 ] || continue
  if [ "${I_SEC[i]}" != "$current_section" ]; then
    current_section=${I_SEC[i]}
    heading "${H_LABEL[current_section]}"
  fi
  info "${C_BOLD}${I_LABEL[i]}${C_RESET}"
  gui_event item-start "${I_ID[i]}"
  if eval "${I_ACTION[i]}"; then
    DONE+=("${I_ID[i]}")
    gui_event item-done "${I_ID[i]}"
  else
    err "Failed: ${I_LABEL[i]}"
    FAILED+=("${I_ID[i]}")
    gui_event item-fail "${I_ID[i]}"
  fi
done

# Settings that act on their own when filled in.
php_set_default
sys_computer_name

write_zshrc_block
restart_ui

heading "Summary"
ok "${#DONE[@]} items done"
if [ ${#FAILED[@]} -gt 0 ]; then
  err "${#FAILED[@]} failed: ${FAILED[*]}"
  log "   Retry with: ./setup.sh --only $(IFS=,; echo "${FAILED[*]}")"
fi
if [ ${#FOLLOW_UPS[@]} -gt 0 ]; then
  printf '\n%sStill to do by hand:%s\n' "$C_BOLD" "$C_RESET"
  for f in "${FOLLOW_UPS[@]}"; do printf '  • %s\n' "$f"; done
fi
printf '\nLog: %s\nOpen a new terminal window to load the new shell settings.\n' "$LOG"
gui_event finished "${#DONE[@]}::${#FAILED[@]}"
