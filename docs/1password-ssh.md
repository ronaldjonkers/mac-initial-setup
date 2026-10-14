# SSH keys with 1Password

The setup supports two ways to use an SSH key stored in 1Password. You can pick either one, or both.

| | **A. Restore key to disk** (`ssh-key-restore`, default on) | **B. 1Password SSH agent** (`ssh-1p-agent`, default off) |
|---|---|---|
| Where the private key lives | `~/.ssh/id_ed25519`, encrypted with a passphrase | Only in 1Password |
| Passphrase | Saved in 1Password and in the macOS Keychain, so you never type it | No passphrase needed |
| Touch ID | Once, when the setup reads the key with `op` | Every time an app uses the key (per session) |
| Works without 1Password running | Yes | No |

## 1. Create the item in 1Password (one time)

**If you already have a key** (for example `~/.ssh/id_ed25519` on your old Mac):

1. In 1Password, choose **New Item → SSH Key**.
2. Click **Add Private Key → Import a Key File** and pick your key. If it is protected, 1Password asks for the passphrase once.
3. Name the item **`SSH Key`**, or set a different name in the setup under *1Password item with your SSH key*.
4. Optional: add a **password** field named **`passphrase`** containing the passphrase you want on disk. If you leave it out, the setup generates a strong passphrase and saves it as a separate Password item **`SSH Key passphrase`**. The 1Password CLI can't add fields to SSH Key items, so it can't be stored on the key item itself.

**If you don't have a key yet**, create one in 1Password with **New Item → SSH Key → Add Private Key → Generate a New Key** (Ed25519), name it `SSH Key`, and add the public key to GitHub and your servers.

If the item is missing during setup, the setup shows these steps and waits until you click **Check again**.

## 2. Allow the terminal to use 1Password

In the 1Password app:

- **Settings → Security**: turn on Touch ID.
- **Settings → Developer**: turn on **Integrate with 1Password CLI**. `op` then unlocks with Touch ID, without a separate sign-in.
- For option B, also turn on **Use the SSH agent** in the same place.

On recent macOS, `op` may say *No accounts configured* even though the switch is on. macOS blocks the terminal from reading 1Password's settings file, so `op` can't see the switch. Setting `OP_BIOMETRIC_UNLOCK_ENABLED=true` tells `op` to use the app integration anyway. The setup does this during the run and adds it to `~/.zshrc`.

The `1password-setup` item opens 1Password, explains where the **Integrate with 1Password CLI** switch is, and checks the connection each time you click **Check again**. 1Password then asks once to allow access, which you approve with Touch ID.

## 3. What the setup does

For option A (`ssh-key-restore`):

```sh
op item get "SSH Key" --format json                      # find the item (Touch ID)
op read "op://<vault>/<item>/private key?ssh-format=openssh"
ssh-keygen -p -f key -P "" -N "<passphrase>"            # encrypt it on disk
ssh-add --apple-use-keychain ~/.ssh/id_ed25519          # passphrase → Keychain
```

With `UseKeychain yes` and `AddKeysToAgent yes` in `~/.ssh/config`, macOS loads the key from then on without asking.

For option B (`ssh-1p-agent`), the setup adds this to `~/.ssh/config`:

```
IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

It also links `~/.1password/agent.sock` and exports `SSH_AUTH_SOCK`, so tools that ignore the ssh config can use the agent too.

## Touch ID in the terminal

The `touchid-sudo` item enables Touch ID for `sudo` through `/etc/pam.d/sudo_local`, which survives macOS updates. Combined with the 1Password CLI integration, `sudo`, `op` and (with option B) `ssh`/`git` all unlock with your fingerprint.
