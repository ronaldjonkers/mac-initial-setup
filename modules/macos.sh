#!/bin/bash
# macOS / Finder / Dock / input tweaks. Each function is one checklist item.

# ---------------------------------------------------------------- Finder ---
finder_hidden_files()  { dw com.apple.finder AppleShowAllFiles -bool true; needs_restart Finder; }
finder_extensions()    { dw NSGlobalDomain AppleShowAllExtensions -bool true; needs_restart Finder; }
finder_bars()          { dw com.apple.finder ShowPathbar -bool true; dw com.apple.finder ShowStatusBar -bool true; needs_restart Finder; }
finder_posix_title()   { dw com.apple.finder _FXShowPosixPathInTitle -bool true; needs_restart Finder; }
finder_list_view()     { dw com.apple.finder FXPreferredViewStyle -string Nlsv; needs_restart Finder; }
finder_folders_first() { dw com.apple.finder _FXSortFoldersFirst -bool true; dw com.apple.finder _FXSortFoldersFirstOnDesktop -bool true; needs_restart Finder; }
finder_search_here()   { dw com.apple.finder FXDefaultSearchScope -string SCcf; needs_restart Finder; }
finder_no_ext_warning(){ dw com.apple.finder FXEnableExtensionChangeWarning -bool false; needs_restart Finder; }
finder_home_window()   { dw com.apple.finder NewWindowTarget -string PfHm; dw com.apple.finder NewWindowTargetPath -string "file://$HOME/"; needs_restart Finder; }
finder_show_library()  { run chflags nohidden "$HOME/Library"; }
finder_no_dsstore()    { dw com.apple.desktopservices DSDontWriteNetworkStores -bool true; dw com.apple.desktopservices DSDontWriteUSBStores -bool true; }
finder_drives_desktop(){ dw com.apple.finder ShowExternalHardDrivesOnDesktop -bool true; dw com.apple.finder ShowRemovableMediaOnDesktop -bool true; needs_restart Finder; }
finder_trash_30d()     { dw com.apple.finder FXRemoveOldTrashItems -bool true; needs_restart Finder; }

# ------------------------------------------------------------------ Dock ---
dock_no_recents()      { dw com.apple.dock show-recents -bool false; needs_restart Dock; }
dock_fixed_spaces()    { dw com.apple.dock mru-spaces -bool false; needs_restart Dock; }
dock_autohide()        { dw com.apple.dock autohide -bool true; dw com.apple.dock autohide-delay -float 0; dw com.apple.dock autohide-time-modifier -float 0.4; needs_restart Dock; }
dock_minimize_app()    { dw com.apple.dock minimize-to-application -bool true; needs_restart Dock; }
desktop_no_click_reveal() { dw com.apple.WindowManager EnableStandardClickToShowDesktop -bool false; }

# ------------------------------------------------------ Keyboard & input ---
kb_fast_repeat()       { dw NSGlobalDomain KeyRepeat -int 2; dw NSGlobalDomain InitialKeyRepeat -int 15; dw NSGlobalDomain ApplePressAndHoldEnabled -bool false; follow_up "Log out and back in for the key repeat settings."; }
kb_no_smart_quotes()   { dw NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false; dw NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false; dw NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false; }
kb_no_autocorrect()    { dw NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false; dw NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false; }
kb_full_access()       { dw NSGlobalDomain AppleKeyboardUIMode -int 2; }

tp_no_natural_scroll() { dw NSGlobalDomain com.apple.swipescrolldirection -bool false; follow_up "Log out and back in so the scroll direction applies everywhere."; }

tp_tap_to_click() {
  dw com.apple.AppleMultitouchTrackpad Clicking -bool true
  dw com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  run defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  dw NSGlobalDomain com.apple.mouse.tapBehavior -int 1
}

# Three finger drag (normally hidden under Accessibility). Swipes move to four fingers,
# exactly what System Settings does when you switch it on.
tp_three_finger_drag() {
  local d
  for d in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    dw $d TrackpadThreeFingerDrag -bool true
    dw $d TrackpadThreeFingerHorizSwipeGesture -int 0
    dw $d TrackpadThreeFingerVertSwipeGesture -int 0
    dw $d TrackpadFourFingerHorizSwipeGesture -int 2
    dw $d TrackpadFourFingerVertSwipeGesture -int 2
  done
  run defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerDragGesture -bool true
  run defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 0
  run defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerVertSwipeGesture -int 0
  follow_up "Log out and back in to activate three finger drag (check: Settings → Accessibility → Pointer Control → Trackpad Options)."
}

# ----------------------------------------------------------- Screenshots ---
shots_folder() { run mkdir -p "$HOME/Screenshots"; dw com.apple.screencapture location -string "$HOME/Screenshots"; needs_restart SystemUIServer; }
shots_no_shadow() { dw com.apple.screencapture disable-shadow -bool true; needs_restart SystemUIServer; }

# ---------------------------------------------------------------- System ---
sys_expand_dialogs() {
  dw NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  dw NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  dw NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  dw NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
}
sys_save_local()      { dw NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false; }
sys_no_photos_popup() { run defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true; }
sys_textedit_plain()  { dw com.apple.TextEdit RichText -int 0; }
sys_scrollbars()      { dw NSGlobalDomain AppleShowScrollBars -string Always; }
sys_firewall()        { run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on && ok "Firewall on"; }
sys_no_boot_sound()   { run sudo nvram StartupMute=%01; }

# Turn on the built-in locate database and build it now instead of waiting for the weekly run.
locate_enable() {
  if [ -s /var/db/locate.database ]; then ok "locate already works"; return 0; fi
  run sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.locate.plist 2>/dev/null
  run sudo sh -c '/usr/libexec/locate.updatedb >/dev/null 2>&1 &' || return 1
  ok "locate enabled – the index is being built in the background (takes a few minutes)"
}

# Touch ID for sudo, via sudo_local so it survives macOS updates.
sys_touchid_sudo() {
  local f=/etc/pam.d/sudo_local
  if grep -qs '^auth.*pam_tid.so' "$f"; then ok "Touch ID for sudo already enabled"; return 0; fi
  if [ -f /etc/pam.d/sudo_local.template ]; then
    run sudo sh -c "sed -e 's/^#auth/auth/' /etc/pam.d/sudo_local.template > $f"
  else
    run sudo sh -c "printf 'auth       sufficient     pam_tid.so\n' > $f"
  fi
  ok "Touch ID for sudo enabled"
}

sys_computer_name() {
  local name; name=$(cfg computer_name)
  [ -n "$name" ] || return 0
  [ "$(scutil --get ComputerName 2>/dev/null)" = "$name" ] && return 0
  heading "Computer name"
  local host; host=$(printf '%s' "$name" | tr ' ' '-' | tr -cd '[:alnum:]-')
  run sudo scutil --set ComputerName "$name"
  run sudo scutil --set LocalHostName "$host"
  run sudo scutil --set HostName "$host"
  ok "Computer name set to $name"
}

restart_ui() {
  local a
  for a in "${NEED_RESTART[@]}"; do run killall "$a" 2>/dev/null; done
}

# ---------------------------------------------------------------- Safari ---
# Safari is sandboxed: writing its preferences requires Full Disk Access for the terminal.
safari_writable() {
  [ "$DRY_RUN" = 1 ] && return 0
  defaults write com.apple.Safari MacSetupProbe -bool true 2>/dev/null || return 1
  defaults delete com.apple.Safari MacSetupProbe 2>/dev/null
}

safari_prepare() {
  [ -n "${SAFARI_CHECKED:-}" ] && return "$SAFARI_CHECKED"
  SAFARI_CHECKED=0
  pgrep -xq Safari && { info "Quitting Safari"; run osascript -e 'quit app "Safari"'; sleep 1; }
  if ! safari_writable; then
    warn "This terminal needs Full Disk Access to change Safari settings."
    run open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    pause "Add your terminal app under Full Disk Access, then press Enter"
    if ! safari_writable; then
      follow_up "Give your terminal Full Disk Access, restart it, then re-run with --only safari-downloads,safari-dev,safari-full-url,safari-privacy,safari-status-bar"
      SAFARI_CHECKED=1
    fi
  fi
  return "$SAFARI_CHECKED"
}

safari_no_open_downloads() { safari_prepare || return 1; dw com.apple.Safari AutoOpenSafeDownloads -bool false; }
safari_dev() {
  safari_prepare || return 1
  dw com.apple.Safari IncludeDevelopMenu -bool true
  dw com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  dw com.apple.Safari WebKitPreferences.developerExtrasEnabled -bool true
  dw com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  dw NSGlobalDomain WebKitDeveloperExtras -bool true
}
safari_full_url()   { safari_prepare || return 1; dw com.apple.Safari ShowFullURLInSmartSearchField -bool true; }
safari_status_bar() { safari_prepare || return 1; dw com.apple.Safari ShowOverlayStatusBar -bool true; dw com.apple.Safari ShowStandaloneTabBar -bool true; }
safari_privacy()    { safari_prepare || return 1; dw com.apple.Safari UniversalSearchEnabled -bool false; dw com.apple.Safari SuppressSearchSuggestions -bool true; }

# ------------------------------------------------------------- Dock apps ---
# Find an app bundle by name in the usual places (Safari lives in a cryptex on recent macOS).
find_app() {
  local d
  for d in /Applications /System/Applications /System/Applications/Utilities \
           /System/Volumes/Preboot/Cryptexes/App/System/Applications "$HOME/Applications"; do
    [ -d "$d/$1.app" ] && { echo "$d/$1.app"; return 0; }
  done
  mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '$1.app'" 2>/dev/null | head -1 | grep .
}

# Replace the Dock's apps with exactly the list in the dock_apps setting (Finder and Trash always stay).
dock_clean() {
  local path url name names missing=() old_ifs=$IFS
  IFS=, names=($(cfg dock_apps)); IFS=$old_ifs
  run defaults write com.apple.dock persistent-apps -array
  for name in "${names[@]}"; do
    name=$(printf '%s' "$name" | sed -e 's/^ *//' -e 's/ *$//')
    [ -n "$name" ] || continue
    path=$(find_app "$name") || { missing+=("$name"); continue; }
    url="file://$(printf '%s/' "$path" | sed 's/ /%20/g')"
    run defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$url</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
  done
  needs_restart Dock
  [ ${#missing[@]} -gt 0 ] && warn "Not found, left out of the Dock: ${missing[*]}"
  ok "Dock cleaned up"
}

shots_clipboard() { dw com.apple.screencapture target -string clipboard; needs_restart SystemUIServer; }
