---
title: Uninstalling
description: Remove the RubyFunk host or a client for each install method, and clear what the removal leaves behind.
---

Remove RubyFunk the way you installed it, then clear what stays behind if you want a clean slate.

Removal never deletes the config directory: `~/.config/rubyfunk` on Linux, `%ProgramData%\rubyfunk`
for the Windows host. It holds the host's identity, paired devices, console password, `host.env`,
library, logs and [plugins](/docs/plugins), so a reinstall picks up where you left off.

## Linux hosts

The [guided installer](/docs/install#guided-install-preview) does steps 1 and 2 for apt, dnf,
pacman and the Bazzite sysext: `sh install.sh --uninstall` (fetch it with
`curl -fsSLO https://punktfunk.unom.io/install.sh`).

1. Stop the user services first. Package removal can't see the links `enable` wrote in your home,
   and the units then fail at every login:

   ```sh
   systemctl --user disable --now rubyfunk-host rubyfunk-web rubyfunk-scripting
   ```

   Add `rubyfunk-kde-session` if you set up the [headless KDE session](/docs/kde#headless-session).

2. Remove the packages and the repository. Name only the packages you installed:

   | How you installed | Remove |
   |---|---|
   | Ubuntu (apt) | `sudo apt purge rubyfunk-host rubyfunk-web rubyfunk-scripting rubyfunk-client`, then `sudo rm -f /etc/apt/sources.list.d/rubyfunk.list /etc/apt/keyrings/rubyfunk.asc && sudo apt update` |
   | Fedora (dnf) | `sudo dnf remove rubyfunk rubyfunk-web rubyfunk-scripting rubyfunk-client`, then `sudo rm -f /etc/yum.repos.d/rubyfunk.repo` |
   | Bazzite / Fedora Atomic, layered RPMs | `sudo rpm-ostree uninstall rubyfunk rubyfunk-web` (what `rpm-ostree status` lists), remove `/etc/yum.repos.d/rubyfunk.repo`, then reboot |
   | Bazzite sysext | [See below](#bazzite--fedora-atomic-systemd-sysext) |
   | Arch / CachyOS (pacman) | `sudo pacman -Rns rubyfunk-host rubyfunk-web rubyfunk-scripting rubyfunk-client`, then delete the `[rubyfunk]` (or `[rubyfunk-canary]`) section from `/etc/pacman.conf` |
   | Omarchy | `rubyfunk-omarchy remove` first, then as Arch |
   | Steam Deck on-device build | [See below](#steamos--steam-deck-host-on-device-build) |
   | NixOS | [See below](#nixos) |

3. Clear what stays behind — the config directory, the tray's autostart entry, the three groups the
   packages create, lingering and the unit drop-ins:

   ```sh
   rm -rf ~/.config/rubyfunk ~/.config/systemd/user/rubyfunk-*.service.d
   rm -f ~/.config/autostart/io.github.gunu3371.rubyfunk.tray.desktop
   sudo groupdel rubyfunk-update
   sudo groupdel rubyfunk-door
   sudo gpasswd -d "$USER" rubyfunk; sudo groupdel rubyfunk
   sudo loginctl disable-linger "$USER"      # only if nothing else needs it
   ```

   Drop the `rubyfunk` group rather than keeping it: it can attach emulated USB devices. If you
   set up [Reachable without logging in](/docs/profiles#on-linux), turn it off under **Profiles**
   first and run `sudo userdel rubyfunk`, or `groupdel rubyfunk-door` refuses: the door's user
   holds that group.

4. Close the firewall ports you opened:

   | Firewall | Close |
   |---|---|
   | ufw | `sudo ufw delete allow rubyfunk-native`, and `rubyfunk-gamestream` / `rubyfunk-web` if you allowed them |
   | firewalld | `sudo firewall-cmd --permanent --remove-service=rubyfunk-native` (and the other two), then `sudo firewall-cmd --reload` |

   If the setup moved the management port next to Sunshine, also remove `47991/tcp`.

On Arch you can drop the repository key too:
`sudo pacman-key --delete E0CA04465C99C936E0B0C6510A317015A34DDD69`.

### Bazzite / Fedora Atomic (systemd-sysext)

Stop the services (step 1) before you remove the image, because the binaries leave with it:

```sh
sudo rubyfunk-sysext remove
sudo rm -f /etc/modules-load.d/rubyfunk.conf /etc/udev/rules.d/60-rubyfunk.rules
```

`remove` deletes the image, `/etc/rubyfunk-sysext.conf` and the gamescope session drop-in
unless you edited it. The two files above it leaves. On a Bazzite with Steam's
session manager it may also have added an SELinux module: `sudo semodule -r rubyfunk-ds-inhibit`.
Then do steps 3 and 4.

### SteamOS / Steam Deck host (on-device build)

There is no uninstall script. `sh install.sh --uninstall` only stops the services; do the rest by
hand, in this order.

1. Stop and remove the user services:

   ```sh
   systemctl --user disable --now rubyfunk-host rubyfunk-web \
     rubyfunk-scripting rubyfunk-rebuild-check
   rm -f ~/.config/systemd/user/rubyfunk-*.service
   rm -rf ~/.config/systemd/user/rubyfunk-*.service.d
   systemctl --user daemon-reload
   sudo loginctl disable-linger "$USER"      # only if nothing else on the Deck needs it
   ```

2. Remove the build container and the files under your home:

   ```sh
   distrobox rm -f pf2                       # the build container (~1 GB)
   rm -f  ~/.local/bin/rubyfunk-scripting ~/.local/bin/rubyfunk-gamescope
   rm -rf ~/.local/lib/rubyfunk-scripting ~/.local/share/rubyfunk-scripting
   rm -f  ~/.local/share/rubyfunk/gamescope.stamp
   rm -f  ~/.local/share/applications/io.github.gunu3371.rubyfunk.host.desktop
   rm -f  ~/.local/bin/rubyfunk-tray ~/.config/autostart/io.github.gunu3371.rubyfunk.tray.desktop
   rm -f  ~/.local/share/applications/io.github.gunu3371.rubyfunk.starthost.desktop
   rm -f  ~/.local/share/icons/hicolor/*/apps/rubyfunk-tray*.png
   rm -rf ~/rubyfunk                        # the source checkout and its build
   ```

   The container shares your home, so `~/.cargo`, `~/.rustup` and `~/.bun` are there too. Delete
   them only if nothing else of yours uses Rust or bun.

3. If you set up [Reachable without logging in](/docs/profiles#on-linux), turn it off under
   **Profiles** first, then remove it. The last line deletes every seat's home and the shared
   games folder:

   ```sh
   sudo systemctl disable --now rubyfunk-web-door rubyfunk-door rubyfunk-seats \
     var-lib-rubyfunk.mount 'var-lib-rubyfunk\x2dseats.mount'
   sudo rm -rf /opt/rubyfunk /etc/systemd/system/rubyfunk-seat@.service.d
   sudo rm -f /etc/systemd/system/rubyfunk-{seats,seat@,door,web-door,door-on@,door-off@}.service \
     /etc/systemd/system/var-lib-rubyfunk*.mount \
     /etc/systemd/user/rubyfunk-scripting.service \
     /etc/polkit-1/rules.d/49-rubyfunk-door.rules \
     /etc/udev/rules.d/65-rubyfunk-seats.rules /etc/tmpfiles.d/rubyfunk-seats.conf
   sudo rm -rf /home/.steamos/offload/var/lib/rubyfunk /home/.steamos/offload/var/lib/rubyfunk-seats
   ```

   Each seat's account stays: `getent passwd | grep rubyfunk-seat=` lists them for
   `sudo userdel`, and `sudo userdel rubyfunk` removes the door's. Then drop the groups it used:
   `sudo groupdel rubyfunk-door; sudo groupdel rubyfunk-update; sudo groupdel rubyfunk-games`.

4. Remove the root-owned tuning. Don't skip it: the keep-list entry carries these files through
   every SteamOS update.

   ```sh
   sudo rm -f /etc/atomic-update.conf.d/rubyfunk.conf \
              /etc/udev/rules.d/60-rubyfunk.rules \
              /etc/modules-load.d/rubyfunk.conf \
              /etc/sysctl.d/99-rubyfunk-net.conf \
              /etc/systemd/system/user@.service.d/50-rubyfunk-nice.conf
   sudo udevadm control --reload-rules
   sudo systemctl daemon-reload
   ```

5. Optional: `rm -rf ~/.config/rubyfunk` for a clean slate, and
   `sudo gpasswd -d "$USER" rubyfunk; sudo groupdel rubyfunk`. If you had no KDE RemoteDesktop
   grant before, the installer seeded `~/.local/share/flatpak/db/kde-authorized`; delete it if
   nothing else relies on it. Your `input` group membership is harmless to keep.

### NixOS

Remove what you declared: the `services.rubyfunk.*` options, `rubyfunk.nixosModules.default` and
the `rubyfunk` flake input. Then `sudo nixos-rebuild switch`. The unit, udev rules, tuning,
firewall ports and group memberships go with the generation; store paths stay until you
garbage-collect, and `~/.config/rubyfunk` stays regardless.

## Windows host

Uninstall **RubyFunk Host** from **Settings → Apps → Installed apps**, or run
`winget uninstall gunu3371.RubyFunkHost`. Both remove the service, the drivers, the scheduled tasks and
the firewall rules ([full list](/docs/windows-host#uninstalling)). Left behind on purpose:

- **`%ProgramData%\rubyfunk`**, your config and pairings:
  `Remove-Item -Recurse -Force "$env:ProgramData\rubyfunk"`.
- **The winget source**, if you added it: `winget source remove -n rubyfunk` (admin PowerShell).
- **Seat accounts**, `pf_seat1` to `pf_seat4`, if you used [seats](/docs/windows-seats). Remove
  their profiles under **Profiles** before you uninstall, or delete the accounts in **Computer
  Management** → **Local Users and Groups** afterwards.
- **VB-CABLE**, if an older RubyFunk installed it. Other apps may use it; remove it with its own
  uninstaller (**VB-Audio Virtual Cable** in Installed apps).
- **The old unom certificate**, if you imported it by hand for release 0.28.1 or earlier. Current
  releases don't need it: in `certlm.msc`, delete the certificate issued to **unom** (thumbprint
  `CD1EFDEEEC9743AFC38F56C5AF30C5A3009BE941`) from **Trusted Publishers** and **Trusted Root
  Certification Authorities**.

### A RubyFunk display or gamepad stays in Device Manager

An older build could leave one behind. While the host is still installed, run from an elevated
prompt:

```powershell
rubyfunk-host driver uninstall
rubyfunk-host driver uninstall --gamepad
rubyfunk-host driver uninstall --audio
```

Already uninstalled? Install the current version and uninstall it again; its uninstaller runs all
three.

## Clients

Removing a client doesn't unpair it: unpair the device in the host's
[web console](/docs/web-console) too.

| Client | Remove | Left behind |
|---|---|---|
| Linux Flatpak | `flatpak uninstall --user --delete-data io.github.gunu3371.rubyfunk` | A `~/.config/rubyfunk` an older version used, if any; the Flatpak remote (`flatpak remotes --user`, then `flatpak remote-delete --user <name>`) |
| Linux packages | `sudo apt purge rubyfunk-client`, `sudo dnf remove rubyfunk-client` or `sudo pacman -Rns rubyfunk-client`; drop the repo as for hosts | `~/.config/rubyfunk` |
| Windows installer | **RubyFunk** in **Settings → Apps → Installed apps**, or `& "$env:LOCALAPPDATA\Programs\RubyFunk\unins000.exe" /VERYSILENT`. Portable zip: delete the folder | `%APPDATA%\rubyfunk` |
| Windows MSIX | `Get-AppxPackage *io.github.gunu3371.rubyfunk \| Remove-AppxPackage` | `%APPDATA%\rubyfunk`, if present |
| macOS | Quit it and drag it from **Applications** to the Trash | — |
| iPhone, iPad, Apple TV | Delete the app; if you joined the beta, stop testing in **TestFlight** | — |
| Android, Android TV | Uninstall from Google Play or **Settings → Apps**; leave the testing program on the Play listing if you joined canary | — |
| Steam Deck (Decky) | Uninstall **RubyFunk** from Decky's plugin list ([Steam Deck → Uninstalling](/docs/steam-deck#uninstalling)) | The Steam shortcuts, the Steam Input template, the client and its settings: `~/.var/app/io.github.gunu3371.rubyfunk` for the Flatpak, `~/.config/rubyfunk` for a native client |
| LG webOS TV | Remove it from the TV's launcher; the community [`pf-webos`](https://github.com/dyptan-io/pf-webos) project handles the rest | — |

## Plugins and the script runner

Plugins live in the host's config directory, so they survive host removal. Remove them first, or
delete the directories afterwards:

```sh
rubyfunk-host plugins list             # what's installed
rubyfunk-host plugins remove <name>    # uninstall one
rubyfunk-host plugins disable          # stop and disable the runner
```

On Windows run these from an elevated PowerShell. `plugins remove` leaves each plugin's settings and
cache in `plugin-state/<plugin>/` (including API keys you entered) and the runner's `plugin-token`;
deleting the config directory removes them. The runner package (`rubyfunk-scripting`) comes off
with the host packages; on Windows it goes with the host installer.

## Removing the pairing, not the software

- **On the host:** unpair the device in the [web console](/docs/web-console). It stops being
  trusted immediately.
- **On a Linux or Windows client:** `rubyfunk hosts forget <host>` drops one saved host;
  `rubyfunk reset` drops all of them and the stream settings but keeps the client's identity.
  The Linux desktop app also takes `rubyfunk-client --forget-host <fingerprint|host[:port]>`.

See [Pairing](/docs/pairing) for how the two halves fit.
