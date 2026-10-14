#!/bin/bash
# 1Password: browser extensions, app integration (Touch ID for CLI + SSH agent).

OP_CHROME_EXT_ID=aeblfdkhhhdcdjpifhhbdiojplfjncoa
OP_FIREFOX_EXT_ID='{d634138d-c276-4fc8-924b-40a0ea21d284}'
OP_AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# `op` reads 1Password's settings file to see whether "Integrate with 1Password CLI" is on, but
# recent macOS blocks the terminal from reading another app's data, so `op` thinks it is off.
# This tells `op` to use the app integration anyway (also added to ~/.zshrc for your own use).
export OP_BIOMETRIC_UNLOCK_ENABLED=true

# Chromium browsers pick up "external extensions" on next launch and ask you to enable them.
# The system-wide folder is used: macOS blocks other apps from writing into a browser's own
# ~/Library/Application Support folder.
op_chromium_ext() {
  local name=$1 dir="/Library/Application Support/$2/External Extensions"
  run sudo mkdir -p "$dir" || return 1
  printf '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }\n' \
    | run sudo tee "$dir/$OP_CHROME_EXT_ID.json" >/dev/null || return 1
  ok "1Password extension queued for $name"
  follow_up "Open $name and click 'Enable extension' when it offers 1Password."
}

op_ext_chrome() { op_chromium_ext "Google Chrome" "Google/Chrome"; }
op_ext_brave()  { op_chromium_ext "Brave" "BraveSoftware/Brave-Browser"; }

op_ext_firefox() {
  local dist="/Applications/Firefox.app/Contents/Resources/distribution"
  require_app Firefox || return 1
  if [ -f "$dist/policies.json" ] && ! grep -q 1password "$dist/policies.json"; then
    warn "$dist/policies.json already exists – not overwriting it"
    run open "https://addons.mozilla.org/firefox/addon/1password-x-password-manager/"
    follow_up "Install the 1Password add-on in Firefox (page opened)."
    return 0
  fi
  local json
  json=$(cat <<EOF
{
  "policies": {
    "ExtensionSettings": {
      "$OP_FIREFOX_EXT_ID": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
      }
    }
  }
}
EOF
)
  if [ "$DRY_RUN" = 1 ]; then run tee "$dist/policies.json"; return 0; fi
  if mkdir -p "$dist" 2>/dev/null && printf '%s\n' "$json" >"$dist/policies.json" 2>/dev/null; then :
  else
    sudo mkdir -p "$dist" && printf '%s\n' "$json" | sudo tee "$dist/policies.json" >/dev/null || return 1
  fi
  ok "Firefox will install 1Password on next launch"
}

op_ext_safari() {
  appstore 1569813296 "1Password for Safari" || return 1
  follow_up "Safari → Settings → Extensions: enable 1Password."
}

# Connect the 1Password CLI to the app (one time). Keeps explaining what is still missing until
# `op` works or you skip it. Checking needs no Touch ID; the final step asks you to approve once.
op_connect() {
  command -v op >/dev/null 2>&1 || cask 1password-cli || return 1
  [ "$DRY_RUN" = 1 ] && { run op vault list; return 0; }
  local msg detail
  op vault list >/dev/null 2>&1 && return 0
  require_app 1Password || return 1
  # Without anyone to click "Check again" (--yes, no terminal) there is no point in waiting.
  if [ "$GUI" != 1 ] && { [ "$ASSUME_YES" = 1 ] || ! has_tty; }; then return 1; fi
  open -a 1Password
  while :; do
    if [ -z "$(op account list 2>/dev/null)" ]; then
      msg="Connect 1Password to the terminal (one time):

1. The 1Password app is now open. Sign in if it asks you to.
2. Open its settings: in the menu bar choose 1Password → Settings… (or press ⌘ ,).
3. Click Developer in the sidebar.
4. Tick \"Integrate with 1Password CLI\".
   Dutch: Instellingen → Ontwikkelaar → \"Integreer met 1Password CLI\".

Then click Check again."
    else
      detail=$(op vault list 2>&1 >/dev/null) && { ok "1Password CLI is connected to the app"; return 0; }
      msg="Almost there: 1Password is connected, but access wasn't approved.

Click Check again. 1Password then asks to allow access – approve it with Touch ID or your password.

($detail)"
    fi
    ask "$msg" y "Check again" "Skip" || return 1
  done
}

# Guided 1Password setup: CLI connection now, the rest as follow-ups so nothing blocks.
op_integration() {
  zshrc_add 'export OP_BIOMETRIC_UNLOCK_ENABLED=true   # 1Password CLI: use the app integration'
  if op_connect; then
    [ "$DRY_RUN" = 1 ] || ok "1Password CLI works"
  else
    warn "1Password CLI is not connected – skipped"
    follow_up "1Password → Settings → Developer → tick 'Integrate with 1Password CLI'."
  fi
  follow_up "1Password → Settings → Security: turn on Touch ID. General: 'Start at login' and 'Keep in menu bar'."
  selected ssh-1p-agent && follow_up "1Password → Settings → Developer → turn on 'Use the SSH agent'."
  return 0
}

# Make sure `op` works before reading from 1Password.
op_ready() { op_connect; }
