---
title: Forgot your Password?
description: Read or reset the web console's login password on a Linux, SteamOS or Windows host.
---

Read the web console's login password on the host, or reset it. This is only the console login; a
client that can't connect needs [Pairing](/docs/pairing).

| Host | Password file | Restart the console |
|---|---|---|
| Linux packages, NixOS | `~/.config/rubyfunk/web-password` | `systemctl --user restart rubyfunk-web` |
| SteamOS | `~/.config/rubyfunk/web.env` | `systemctl --user restart rubyfunk-web` |
| Windows | `%ProgramData%\rubyfunk\web-password` | `rubyfunk-host service restart`, elevated |

## Read it

The file holds the password in clear text until your first sign-in. After that the console keeps
only a salted hash, and you [reset it](#reset-it) instead.

```sh
sed -n 's/^RUBYFUNK_UI_PASSWORD=//p' ~/.config/rubyfunk/web-password   # Linux
sed -n 's/^RUBYFUNK_UI_PASSWORD=//p' ~/.config/rubyfunk/web.env        # SteamOS
```

On Windows, from an elevated PowerShell (the file is readable by Administrators only):

```powershell
rubyfunk-host web password
```

## Reset it

Write a `RUBYFUNK_UI_PASSWORD=<new-password>` line into the file and restart the console. The next
sign-in hashes it and signs every other session out.

```sh
printf 'RUBYFUNK_UI_PASSWORD=%s\n' 'new-password' > ~/.config/rubyfunk/web-password
chmod 600 ~/.config/rubyfunk/web-password
systemctl --user restart rubyfunk-web
```

- SteamOS: edit `web.env` rather than overwriting it, because it also holds the session secret.
- Windows, from an elevated PowerShell:

  ```powershell
  notepad "$env:ProgramData\rubyfunk\web-password"   # add RUBYFUNK_UI_PASSWORD=<new-password>
  rubyfunk-host service restart
  ```

On the Linux packages you can instead delete `web-password` and restart the console. It generates a
new password to [read](#read-it).

## The password is right, and sign-in still fails

- **Too many sign-in attempts. Try again …**: after five wrong tries, a device waits up to five
  minutes. Wait, or restart the console to clear it.
- **Wrong password.** for every password, and other console pages answer `auth not configured`: the
  file has no password line. Add one as in [Reset it](#reset-it).
