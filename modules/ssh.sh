#!/bin/bash
# SSH: config file, restoring a key from 1Password, and the 1Password SSH agent.

ssh_config() {
  local user cfgfile="$HOME/.ssh/config" agent_line=""
  user=$(cfg ssh_user)
  if selected ssh-1p-agent; then
    agent_line="    IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
  fi
  local content
  content=$(
    echo "# Managed by mac-initial-setup. Put your own host entries in ~/.ssh/config.d/"
    echo "Include ~/.ssh/config.d/*"
    echo
    echo "Host *"
    [ -n "$user" ] && echo "    User $user"
    echo "    IgnoreUnknown UseKeychain"
    echo "    UseKeychain yes"
    echo "    AddKeysToAgent yes"
    echo "    ServerAliveInterval 60"
    [ -n "$agent_line" ] && echo "$agent_line"
  )
  if [ "$DRY_RUN" = 1 ]; then info "Would write $cfgfile:"; printf '%s\n' "$content" | sed 's/^/    /'; return 0; fi
  mkdir -p "$HOME/.ssh/config.d" && chmod 700 "$HOME/.ssh"
  if [ -f "$cfgfile" ] && ! grep -q 'Managed by mac-initial-setup' "$cfgfile"; then
    cp "$cfgfile" "$cfgfile.backup-$(date +%Y%m%d-%H%M%S)"
    warn "Existing ~/.ssh/config backed up"
  fi
  printf '%s\n' "$content" >"$cfgfile"
  chmod 600 "$cfgfile"
  ok "Wrote ~/.ssh/config (User ${user:-<none>})"
}

# Read a field from 1Password, empty when it does not exist.
op_field() { op read "op://$1/$2/$3" 2>/dev/null; }

# op_create_password <vault id> <title> <password> <note>: via a private template file, so the
# password never shows up in the process list.
op_create_password() {
  local tpl rc
  tpl=$(umask 077; mktemp)
  printf '{"title":"%s","category":"PASSWORD","fields":[{"id":"password","type":"CONCEALED","purpose":"PASSWORD","label":"password","value":"%s"},{"id":"notesPlain","type":"STRING","purpose":"NOTES","label":"notesPlain","value":"%s"}]}' \
    "$(json_str "$2")" "$3" "$(json_str "$4")" >"$tpl"
  op item create --vault "$1" --template "$tpl" >/dev/null; rc=$?
  rm -f "$tpl"
  return $rc
}

json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Put the private key from a 1Password "SSH Key" item on disk, protected by a passphrase
# that is itself stored in 1Password and in the macOS Keychain – so you never type it.
ssh_key_restore() {
  local title vault
  title=$(cfg op_ssh_item); vault=$(cfg op_ssh_vault)
  [ -n "$title" ] || { err "No 1Password item name set"; return 1; }
  if [ "$DRY_RUN" = 1 ]; then
    run op read "op://${vault:-<vault>}/$title/private key?ssh-format=openssh"
    run ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
    return 0
  fi
  op_ready || { follow_up "Re-run with --only ssh-key-restore once the 1Password CLI works."; return 1; }

  local json
  while ! json=$(op item get "$title" ${vault:+--vault "$vault"} --format json 2>/dev/null); do
    case $(op item get "$title" ${vault:+--vault "$vault"} 2>&1 >/dev/null) in
      *[Mm]ore\ than\ one*)
        err "There are several 1Password items named '$title'"
        follow_up "Rename the extra '$title' items in 1Password, or enter the vault in the SSH settings, then re-run with --only ssh-key-restore."
        return 1 ;;
    esac
    warn "No 1Password item named '$title' found"
    if [ "$GUI" != 1 ] && { [ "$ASSUME_YES" = 1 ] || ! has_tty; }; then json=; break; fi
    ask "Your SSH key isn't in 1Password yet. Add it (one time):

1. In 1Password choose New Item → SSH Key.
2. Name it exactly: $title
3. Already have a key? Add Private Key → Import a Key File (for example ~/.ssh/id_ed25519 from your old Mac).
   No key yet? Add Private Key → Generate a New Key (Ed25519).
4. Optional: the password the key should get on your Macs. Leave it out and one is generated and saved as a separate item \"$title passphrase\".
5. Save. If you have several items with this name, enter the vault in the SSH settings of this setup.

Then click Check again." y "Check again" "Skip" || { json=; break; }
  done
  if [ -z "$json" ]; then
    follow_up "Create an 'SSH Key' item named '$title' in 1Password (see docs/1password-ssh.md), then re-run with --only ssh-key-restore."
    return 1
  fi
  ok "Found '$title' in 1Password"

  local id vid type keyname priv pub pass
  id=$(printf '%s' "$json" | plutil -extract id raw -o - -)
  vid=$(printf '%s' "$json" | plutil -extract vault.id raw -o - -)
  type=$(op_field "$vid" "$id" "key type" | tr '[:upper:]' '[:lower:]')
  case "$type" in
    rsa*) keyname=id_rsa ;;
    *)    keyname=id_ed25519 ;;
  esac
  priv=$(op read "op://$vid/$id/private key?ssh-format=openssh") || return 1
  pub=$(op_field "$vid" "$id" "public key")
  [ -n "$priv" ] || { err "Item '$title' has no private key"; return 1; }

  # The passphrase: a "passphrase" field on the SSH Key item, or a separate Password item
  # "<title> passphrase" (the CLI can't add fields to SSH Key items), or a new one.
  local passitem="$title passphrase"
  pass=$(op_field "$vid" "$id" "passphrase")
  [ -n "$pass" ] || pass=$(op_field "$vid" "$passitem" "password")
  if [ -z "$pass" ]; then
    pass=$(openssl rand -hex 24)
    op_create_password "$vid" "$passitem" "$pass" "Passphrase of ~/.ssh/$keyname on your Macs, from the '$title' item. Created by mac-initial-setup." || return 1
    ok "Generated a passphrase and saved it in 1Password as '$passitem'"
  fi

  local keyfile="$HOME/.ssh/$keyname" tmp
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  tmp=$(umask 077; mktemp "$HOME/.ssh/.restore.XXXXXX")
  printf '%s\n' "$priv" >"$tmp"
  # 1Password exports the key unencrypted; encrypt it on disk with the passphrase.
  ssh-keygen -p -q -f "$tmp" -P "" -N "$pass" >/dev/null || { rm -f "$tmp"; err "Could not encrypt key"; return 1; }
  if [ -f "$keyfile" ] && ! cmp -s <(ssh-keygen -y -P "$pass" -f "$tmp" 2>/dev/null) <(ssh-keygen -y -P "" -f "$keyfile" 2>/dev/null); then
    mv "$keyfile" "$keyfile.backup-$(date +%Y%m%d-%H%M%S)"
    [ -f "$keyfile.pub" ] && mv "$keyfile.pub" "$keyfile.pub.backup-$(date +%Y%m%d-%H%M%S)"
    warn "Existing $keyfile backed up"
  fi
  mv "$tmp" "$keyfile"; chmod 600 "$keyfile"
  [ -n "$pub" ] && printf '%s\n' "$pub" >"$keyfile.pub" && chmod 644 "$keyfile.pub"
  ok "SSH key written to ~/.ssh/$keyname"

  # Store the passphrase in the login Keychain (UseKeychain yes picks it up from now on).
  local askpass; askpass=$(mktemp)
  printf '#!/bin/sh\nprintf "%%s\\n" "$MAC_SETUP_PP"\n' >"$askpass"; chmod 700 "$askpass"
  if MAC_SETUP_PP="$pass" SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
     ssh-add --apple-use-keychain "$keyfile" </dev/null >/dev/null 2>&1; then
    ok "Passphrase stored in the macOS Keychain – you won't be asked for it again"
  else
    warn "Could not add the key to the Keychain (no ssh-agent in this session?)"
    follow_up "Run once: ssh-add --apple-use-keychain ~/.ssh/$keyname  (passphrase is in 1Password)"
  fi
  rm -f "$askpass"
}

ssh_1p_agent() {
  run mkdir -p "$HOME/.1password"
  run ln -sfn "$OP_AGENT_SOCK" "$HOME/.1password/agent.sock"
  zshrc_add 'export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"   # 1Password SSH agent'
  follow_up "1Password → Settings → Developer → enable 'Use the SSH agent' (ssh then asks for Touch ID)."
  ok "1Password SSH agent configured"
}
