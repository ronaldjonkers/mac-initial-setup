#!/bin/bash
# App and developer tool installers that need more than a one-line cask/appstore call.

# ------------------------------------------------------------- TextMate ---
TEXTMATE_EXTS="txt text md markdown json jsonc php phtml css scss sass less html htm xhtml js mjs cjs jsx ts tsx vue svelte xml svg yml yaml toml ini conf cfg env log csv tsv sql sh bash zsh fish py rb go rs java kt swift c h cc cpp hpp m mm lua pl r dart twig blade tpl htaccess gitignore gitattributes editorconfig dockerfile lock"
TEXTMATE_UTIS="public.plain-text public.source-code public.script public.shell-script public.json public.xml public.yaml net.daringfireball.markdown public.css public.php-script com.netscape.javascript-source public.html"
# Never hand these to a text editor: images, and .ts which macOS knows as MPEG video.
TEXTMATE_SKIP="public.svg-image public.mpeg-2-transport-stream"

LS_PLIST="$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"

# Print the UTI of each file extension that is a text type (or unknown to macOS, like .tsx).
text_utis() {
  osascript -l JavaScript -e '
    ObjC.import("CoreServices");
    function run(argv) {
      return argv.map(e => {
        const id = ObjC.castRefToObject($.UTTypeCreatePreferredIdentifierForTag($.kUTTagClassFilenameExtension, $(e), null)).js;
        return (id.startsWith("dyn.") || $.UTTypeConformsTo($(id), $("public.text"))) ? id : "";
      }).filter(Boolean).join("\n");
    }' "$@"
}

# The app that opens https links (the default browser), as a path.
default_browser() {
  osascript -l JavaScript -e 'ObjC.import("AppKit");
    $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL($.NSURL.URLWithString("https://example.com")).path.js' 2>/dev/null
}

# ls_set_handlers <bundle id> <uti>…: make an app the default for these types by writing the
# LaunchServices preferences directly. The official API (used by duti) makes macOS ask for
# confirmation once per type, and on recent macOS setting public.html also changes the browser.
ls_set_handlers() {
  local id=$1 pb=/usr/libexec/PlistBuddy f=$LS_PLIST i=0 t uti
  shift
  if [ "$DRY_RUN" = 1 ]; then run "$pb" "$f" "# $id ← $*"; return 0; fi
  mkdir -p "$(dirname "$f")"
  "$pb" -c "Print :LSHandlers" "$f" >/dev/null 2>&1 || "$pb" -c "Add :LSHandlers array" "$f" >/dev/null || return 1
  cp "$f" "$f.backup-$(date +%Y%m%d-%H%M%S)"
  while "$pb" -c "Print :LSHandlers:$i" "$f" >/dev/null 2>&1; do i=$((i + 1)); done
  # Remove the old entries for these types (from the end, so the indexes stay valid)…
  while [ $i -gt 0 ]; do
    i=$((i - 1))
    t=$("$pb" -c "Print :LSHandlers:$i:LSHandlerContentType" "$f" 2>/dev/null) || continue
    case " $* " in *" $t "*) "$pb" -c "Delete :LSHandlers:$i" "$f" || return 1 ;; esac
  done
  # …and add the new ones. One call per type: PlistBuddy crashes on long command lists.
  for uti in "$@"; do
    "$pb" -c "Add :LSHandlers:0 dict" \
          -c "Add :LSHandlers:0:LSHandlerContentType string $uti" \
          -c "Add :LSHandlers:0:LSHandlerRoleAll string $id" \
          -c "Add :LSHandlers:0:LSHandlerPreferredVersions dict" \
          -c "Add :LSHandlers:0:LSHandlerPreferredVersions:LSHandlerRoleAll string -" "$f" >/dev/null || return 1
  done
  plutil -convert binary1 "$f"
  killall lsd 2>/dev/null   # LaunchServices restarts and reads the new preferences
  sleep 1
}

# ls_remove_handlers <bundle id> <type or URL scheme>…: drop that app's default-app entries for these.
ls_remove_handlers() {
  local id=$1 pb=/usr/libexec/PlistBuddy f=$LS_PLIST i=0 t n=0
  shift
  [ -f "$f" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then run "$pb" "$f" "# remove $id for: $*"; return 0; fi
  while "$pb" -c "Print :LSHandlers:$i" "$f" >/dev/null 2>&1; do i=$((i + 1)); done
  while [ $i -gt 0 ]; do
    i=$((i - 1))
    [ "$("$pb" -c "Print :LSHandlers:$i:LSHandlerRoleAll" "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]')" = "$id" ] || continue
    t=$("$pb" -c "Print :LSHandlers:$i:LSHandlerContentType" "$f" 2>/dev/null) \
      || t=$("$pb" -c "Print :LSHandlers:$i:LSHandlerURLScheme" "$f" 2>/dev/null) || continue
    case " $* " in *" $t "*) "$pb" -c "Delete :LSHandlers:$i" "$f" && n=$((n + 1)) ;; esac
  done
  [ $n -gt 0 ] && { plutil -convert binary1 "$f"; killall lsd 2>/dev/null; sleep 1; ok "Removed $n wrong TextMate links (web browser, images, video) left by an older version"; }
  return 0
}

textmate_defaults() {
  require_app TextMate || return 1
  local id utis uti n=0
  id=$(defaults read /Applications/TextMate.app/Contents/Info CFBundleIdentifier 2>/dev/null || echo com.macromates.TextMate)
  id=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
  utis=$( { printf '%s\n' $TEXTMATE_UTIS; text_utis $TEXTMATE_EXTS; } | sort -u | grep -vxF "$(printf '%s\n' $TEXTMATE_SKIP)")
  [ -n "$utis" ] || { err "Could not look up the file types"; return 1; }
  ls_set_handlers "$id" $utis || { err "Could not update the default apps"; return 1; }
  ls_remove_handlers "$id" $TEXTMATE_SKIP http https com.apple.default-app.web-browser
  if [ "$DRY_RUN" = 0 ]; then
    case $(default_browser) in
      *TextMate*) warn "TextMate is set as the web browser (left over from an older version of this setup?)"
         follow_up "Pick your browser again: System Settings → Desktop & Dock → Default web browser." ;;
    esac
  fi
  for uti in $utis; do n=$((n + 1)); done
  ok "TextMate is now the default for $n file types (no confirmation dialogs)"
}

textmate_cli() {
  local mate
  require_app TextMate || return 1
  [ "$DRY_RUN" = 1 ] && ! app_exists TextMate && return 0
  mate=$(find /Applications/TextMate.app/Contents -name mate -type f -perm -u+x 2>/dev/null | head -1)
  [ -n "$mate" ] || { warn "mate binary not found in TextMate.app"; return 1; }
  ensure_brew || return 1
  run ln -sf "$mate" "$(brew --prefix)/bin/mate"
  ok "'mate' command installed"
}

textmate_editor() {
  zshrc_add 'export EDITOR="mate -w"'
  zshrc_add 'export VISUAL="mate -w"'
}

# ------------------------------------------------------------ Autostart ---
# True when the app already opens at login: registered by the app itself (Background Task
# Management, no permission needed) or as a classic login item.
login_item_exists() {
  sfltool dumpbtm 2>/dev/null | awk -v url="URL: $2" '
    /Disposition:/ { on = /enabled/ }
    index($0, url) && on { found = 1 }
    END { exit !found }' && return 0
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ *//' | grep -qx "$1"
}

# autostart <App>: start the app now (in the background) and open it at every login.
autostart() {
  local app=$1 path
  if [ "$DRY_RUN" = 1 ]; then
    run osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$app.app\", hidden:true}"
    run open -g -a "$app"
    return 0
  fi
  path=$(find_app "$app") || { warn "$app is not installed"; return 1; }
  if login_item_exists "$app" "$path"; then
    ok "$app already opens at login"
  elif osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$path\", hidden:true}" >/dev/null; then
    ok "$app opens at login"
  else
    warn "Could not add $app to the login items (no permission to control System Events?)"
    follow_up "System Settings → General → Login Items: add $app with +."
  fi
  open -g "$path" && ok "$app is running"
  follow_up "$app: finish its first-run steps if it shows any (permissions, license)."
}

# ------------------------------------------------------------------ PHP ---
# Point the php command at the version chosen in the php_default setting. Runs at the end, and
# only when one of the PHP items was part of this run.
php_set_default() {
  selected php || selected php84 || selected php83 || selected php82 || return 0
  local v f other
  v=$(cfg php_default); v=${v#php}; v=${v#@}; v=$(printf '%s' "$v" | tr -d ' ')
  case $v in ""|latest) f=php ;; 8.[0-9]) f=php@$v ;; *) warn "Unknown PHP version '$v' – use latest, 8.4, 8.3 or 8.2"; return 1 ;; esac
  heading "PHP default"
  ensure_brew || return 1
  if [ "$DRY_RUN" = 0 ] && ! brew list --formula "$f" >/dev/null 2>&1; then
    warn "PHP $v isn't installed – tick it in Programming languages"; return 1
  fi
  for other in $(brew list --formula 2>/dev/null | grep -E '^php(@[0-9.]+)?$'); do
    [ "$other" = "$f" ] || run brew unlink "$other"
  done
  if [ "$f" = php ]; then run brew link --overwrite php; else run brew link --overwrite --force "$f"; fi || return 1
  ok "php is now $( [ "$DRY_RUN" = 1 ] && echo "$f" || "$(brew --prefix)/bin/php" -r 'echo "PHP ", PHP_VERSION;' )"
}

# ------------------------------------------------------------- Dev tools ---
# check_cmd <command> <path>: say whether a freshly installed command works from a new terminal.
check_cmd() {
  [ "$DRY_RUN" = 1 ] && return 0
  if [ -x "$2" ] || command -v "$1" >/dev/null 2>&1; then ok "'$1' works in new terminal windows"
  else warn "'$1' was installed but can't be found"; return 1; fi
}

install_claude_code() {
  zshrc_add 'export PATH="$HOME/.local/bin:$PATH"'
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then ok "Claude Code already installed"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; return 0; fi
  curl -fsSL https://claude.ai/install.sh | bash || return 1
  check_cmd claude "$HOME/.local/bin/claude"
}

install_rust() {
  if command -v rustup >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/rustup" ]; then ok "Rust already installed"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then run bash -c 'curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'; return 0; fi
  curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path || return 1
  zshrc_add '. "$HOME/.cargo/env"'
}

install_kimi() {
  zshrc_add 'export PATH="$HOME/.local/bin:$PATH"'
  if command -v kimi >/dev/null 2>&1 || [ -x "$HOME/.local/bin/kimi" ]; then ok "Kimi CLI already installed"; return 0; fi
  ensure_tool uv || return 1
  run uv tool install --python 3.13 kimi-cli || return 1
  check_cmd kimi "$HOME/.local/bin/kimi"
}

install_xcode() {
  appstore 497799835 Xcode || return 1
  [ "$DRY_RUN" = 1 ] || app_exists Xcode || return 0
  info "Accepting the Xcode license and installing components…"
  run sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  run sudo xcodebuild -license accept
  run sudo xcodebuild -runFirstLaunch
}

git_config() {
  local name email
  name=$(cfg git_name); email=$(cfg git_email)
  [ -n "$name" ]  && run git config --global user.name "$name"
  [ -n "$email" ] && run git config --global user.email "$email"
  run git config --global init.defaultBranch main
  run git config --global pull.rebase true
  run git config --global push.autoSetupRemote true
  run git config --global core.excludesfile "$HOME/.gitignore_global"
  if [ "$DRY_RUN" = 0 ] && [ ! -f "$HOME/.gitignore_global" ]; then
    printf '.DS_Store\n._*\n.AppleDouble\n.LSOverride\n.idea/\n.vscode/\n*.swp\n.env.local\n' >"$HOME/.gitignore_global"
  fi
  [ -z "$name$email" ] && follow_up "Set your git name/email: git config --global user.name/user.email"
  ok "Git configured"
}

# Path setup used by the brew-installed CLIs.
shell_basics() {
  zshrc_add 'export PATH="$HOME/.local/bin:$PATH"'
  zshrc_add 'alias ll="ls -lahG"'
}
