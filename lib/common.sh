#!/bin/bash
# Shared helpers: logging, dry-run aware execution, package installers.
# Compatible with the stock macOS bash 3.2 – no associative arrays, no mapfile.

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}
TTY=/dev/tty
# GUI=1 when driven by the desktop app: questions and progress go over stdin/stdout
# as "::event::payload" lines instead of the terminal.
GUI=${MAC_SETUP_GUI:-0}

# Newlines in the payload are sent as a literal \n so every event stays on one line.
gui_event() {
  [ "$GUI" = 1 ] || return 0
  printf '::%s::%s\n' "$1" "$(printf '%s' "$2" | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }')"
}

# The desktop app hands over the admin password through an askpass helper.
sudo() {
  if [ -n "${SUDO_ASKPASS:-}" ]; then command sudo -A "$@"; else command sudo "$@"; fi
}

# ---------------------------------------------------------------- output ---
if [ -t 1 ]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

log()     { printf '%s\n' "$*"; }
info()    { printf '%s›%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()      { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()     { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
heading() { printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

# Things the user still has to do by hand; printed in the final summary.
FOLLOW_UPS=()
follow_up() { FOLLOW_UPS+=("$*"); gui_event follow-up "$*"; }

# Run a command, or only print it in dry-run mode.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s  [dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

has_tty() { [ -r "$TTY" ] && [ -w "$TTY" ] && (: <"$TTY") 2>/dev/null; }

# ask "Question" [default y|n] -> returns 0 for yes.
# ask <question> [default y|n] [yes label] [no label]
ask() {
  local q=$1 def=${2:-n} yes=${3:-Yes} no=${4:-No} answer hint="[y/N]"
  [ "$def" = y ] && hint="[Y/n]"
  [ -n "${3:-}" ] && hint="$hint (y = $yes, n = $no)"
  if [ "$GUI" = 1 ]; then
    gui_event ask "$def::$yes::$no::$q"
    IFS= read -r answer <&3 || answer=$def
    [ "$answer" = y ]; return
  fi
  if [ "$ASSUME_YES" = 1 ] || ! has_tty; then
    [ "$def" = y ]; return
  fi
  printf '%s?%s %s %s ' "$C_YELLOW" "$C_RESET" "$q" "$hint" >"$TTY"
  IFS= read -r answer <"$TTY"
  [ -z "$answer" ] && answer=$def
  case "$answer" in [yYjJ]*) return 0 ;; *) return 1 ;; esac
}

pause() {
  if [ "$GUI" = 1 ]; then gui_event pause "${1:-Continue}"; IFS= read -r _ <&3; return 0; fi
  if [ "$ASSUME_YES" = 1 ] || ! has_tty; then return 0; fi
  printf '%s⏎%s %s ' "$C_YELLOW" "$C_RESET" "${1:-Press Enter to continue}" >"$TTY"
  IFS= read -r _ <"$TTY"
}

# require_app <App Name>: fails when missing, except in a dry run (an earlier item would install it).
require_app() {
  app_exists "$1" && return 0
  if [ "$DRY_RUN" = 1 ]; then info "(dry-run) assuming $1 gets installed first"; return 0; fi
  warn "$1 is not installed – skipping"; return 1
}

app_exists() { [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]; }

# ------------------------------------------------------------- shell rc ---
# Lines collected here end up in one managed block in ~/.zshrc.
ZSHRC_LINES=()
ZSHRC_BEGIN="# >>> mac-initial-setup >>>"
ZSHRC_END="# <<< mac-initial-setup <<<"

# zshrc_add <line>: add a line to the managed block in ~/.zshrc. Written right away, so a
# command is usable in new terminal windows even if the run stops halfway.
zshrc_add() {
  local l
  for l in "${ZSHRC_LINES[@]}"; do [ "$l" = "$1" ] && return 0; done
  ZSHRC_LINES+=("$1")
  [ "$DRY_RUN" = 1 ] || write_zshrc_block quiet
}

# Rewrite the managed block: the lines from earlier runs plus the ones added in this run.
write_zshrc_block() {
  [ ${#ZSHRC_LINES[@]} -eq 0 ] && return 0
  local rc="$HOME/.zshrc" tmp old
  if [ "$DRY_RUN" = 1 ]; then
    info "Would add to the mac-initial-setup block in $rc:"; printf '    %s\n' "${ZSHRC_LINES[@]}"; return 0
  fi
  touch "$rc"
  old=$(awk -v b="$ZSHRC_BEGIN" -v e="$ZSHRC_END" '$0==b{inb=1;next} $0==e{inb=0;next} inb' "$rc")
  tmp=$(mktemp)
  awk -v b="$ZSHRC_BEGIN" -v e="$ZSHRC_END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$rc" >"$tmp"
  { cat "$tmp"
    echo "$ZSHRC_BEGIN"
    { [ -n "$old" ] && printf '%s\n' "$old"; printf '%s\n' "${ZSHRC_LINES[@]}"; } | awk '!seen[$0]++'
    echo "$ZSHRC_END"; } >"$rc"
  rm -f "$tmp"
  [ "${1:-}" = quiet ] || ok "Updated the mac-initial-setup block in ~/.zshrc"
}

# -------------------------------------------------------------- homebrew ---
brew_bin() {
  if [ -x /opt/homebrew/bin/brew ]; then echo /opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew ]; then echo /usr/local/bin/brew
  fi
}

ensure_clt() {
  xcode-select -p >/dev/null 2>&1 && return 0
  info "Installing Xcode Command Line Tools…"
  [ "$DRY_RUN" = 1 ] && { run xcode-select --install; return 0; }
  # Headless install through softwareupdate (same trick Homebrew uses).
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo touch "$marker"
  local label
  label=$(softwareupdate -l 2>/dev/null | grep -E '^\s*\* Label: Command Line Tools' | sed 's/^.*Label: //' | sort -V | tail -1)
  if [ -n "$label" ]; then
    sudo softwareupdate -i "$label" --verbose
  fi
  sudo rm -f "$marker"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install 2>/dev/null
    pause "Finish the Command Line Tools installer dialog, then press Enter"
  fi
  xcode-select -p >/dev/null 2>&1
}

ensure_brew() {
  [ -n "${BREW_READY:-}" ] && return 0
  local b; b=$(brew_bin)
  if [ -z "$b" ]; then
    ensure_clt || return 1
    info "Installing Homebrew…"
    if [ "$DRY_RUN" = 1 ]; then
      run /bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)'
      return 0
    fi
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    b=$(brew_bin)
    [ -n "$b" ] || return 1
  fi
  eval "$("$b" shellenv)"
  # Make brew available in new login shells.
  local line="eval \"\$($b shellenv)\""
  if ! grep -qs 'brew shellenv' "$HOME/.zprofile"; then
    if [ "$DRY_RUN" = 1 ]; then run echo "$line >> ~/.zprofile"; else echo "$line" >>"$HOME/.zprofile"; fi
  fi
  export HOMEBREW_NO_ENV_HINTS=1
  BREW_READY=1
}

# cask <token> [App Name] – skips when the app is already present (e.g. from the App Store).
cask() {
  local token=$1 app=${2:-}
  ensure_brew || return 1
  if [ -n "$app" ] && app_exists "$app"; then ok "$app already installed"; return 0; fi
  if [ "$DRY_RUN" = 0 ] && brew list --cask "$token" >/dev/null 2>&1; then ok "$token already installed"; return 0; fi
  run brew install --cask "$token"
}

# formula <name>…
formula() {
  ensure_brew || return 1
  local f missing=()
  for f in "$@"; do
    if [ "$DRY_RUN" = 0 ] && brew list --formula "$f" >/dev/null 2>&1; then continue; fi
    missing+=("$f")
  done
  [ ${#missing[@]} -eq 0 ] && { ok "Already installed: $*"; return 0; }
  run brew install "${missing[@]}"
}

# formula_keg <name>: for formulas Homebrew keeps out of PATH (keg-only); adds their bin folder.
formula_keg() {
  formula "$1" || return 1
  zshrc_add "export PATH=\"\${HOMEBREW_PREFIX:-/opt/homebrew}/opt/$1/bin:\$PATH\""
}

ensure_tool() { command -v "$1" >/dev/null 2>&1 || formula "${2:-$1}"; }

# appstore <id> <App Name> – install through the Mac App Store with `mas`.
appstore() {
  local id=$1 app=$2
  if app_exists "$app"; then ok "$app already installed"; return 0; fi
  ensure_tool mas || return 1
  if run mas install "$id"; then return 0; fi
  warn "Could not install $app from the App Store (are you signed in to the App Store?)"
  run open "macappstore://apps.apple.com/app/id$id"
  follow_up "Install $app from the App Store (page opened) – sign in to the App Store first."
  return 1
}

# sparkle_app <App Name> <appcast url> – install the newest release listed in a Sparkle appcast.
sparkle_app() {
  local app=$1 appcast=$2 url
  if app_exists "$app"; then ok "$app already installed (it updates itself)"; return 0; fi
  url=$(curl -fsSL "$appcast" | grep -oE 'url="https://[^"]+\.(dmg|zip)"' | head -1 | sed -E 's/^url="(.*)"$/\1/')
  [ -n "$url" ] || { err "No download found in $appcast"; return 1; }
  info "Downloading $app from $url"
  install_from_url "$app" "$url"
}

# install_from_url <App Name> <url to .dmg or .zip>
install_from_url() {
  local app=$1 url=$2
  [ "$DRY_RUN" = 1 ] && { run curl -fL "$url"; run ditto "$app.app" /Applications; return 0; }
  local work; work=$(mktemp -d)
  local file="$work/${url##*/}"
  curl -fL --progress-bar -o "$file" "$url" || { rm -rf "$work"; return 1; }
  local src=""
  case "$file" in
    *.dmg)
      local mnt="$work/mnt"; mkdir -p "$mnt"
      hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mnt" "$file" || { rm -rf "$work"; return 1; }
      src=$(find "$mnt" -maxdepth 1 -name '*.app' | head -1)
      [ -n "$src" ] && ditto "$src" "/Applications/$(basename "$src")"
      hdiutil detach -quiet "$mnt"
      ;;
    *.zip)
      ditto -x -k "$file" "$work/x"
      src=$(find "$work/x" -maxdepth 2 -name '*.app' | head -1)
      [ -n "$src" ] && ditto "$src" "/Applications/$(basename "$src")"
      ;;
  esac
  rm -rf "$work"
  [ -n "$src" ] || { err "No .app found in download"; return 1; }
  local dest="/Applications/$(basename "$src")"
  if spctl --assess --type execute "$dest" 2>/dev/null; then
    ok "Installed $(basename "$src") (signature and notarization verified)"
  else
    warn "Installed $(basename "$src"), but Gatekeeper could not verify it"
  fi
}

# --------------------------------------------------------------- defaults ---
NEED_RESTART=()
needs_restart() {
  local a
  for a in "${NEED_RESTART[@]}"; do [ "$a" = "$1" ] && return 0; done
  NEED_RESTART+=("$1")
}

dw() { run defaults write "$@"; }
