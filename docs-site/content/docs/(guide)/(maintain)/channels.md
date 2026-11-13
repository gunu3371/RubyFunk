---
title: Release Channels
description: Stable follows releases, canary follows main — pick one per machine, subscribe to it, pin a version or switch.
---

Pick a release channel per machine, subscribe to it, and pin or switch versions when you need to.

- **Stable** moves on each `vX.Y.Z` release. Every install guide uses it. Pick it for anything you
  don't want to babysit.
- **Canary** is built from `main` whenever a merge touches that platform. It is fast and sometimes
  broken; pick it for a test machine.

The channels are separate repositories, so a stable box never picks up a canary build. Canary is
always one minor version ahead of stable, so going back to stable is a downgrade. The web console's
**Updates** card follows the channel you installed from ([Updating](/docs/updating)).

## Subscribe

`…` stands for `https://git.unom.io/api/packages/unom`.

| Platform | Canary | Stable |
|---|---|---|
| **apt** | `canary main` at the end of the line in `/etc/apt/sources.list.d/rubyfunk.list` | `stable main` |
| **dnf / rpm-ostree** | baseurl `…/rpm/fedora-44-canary` (Bazzite: `…/rpm/bazzite-canary`) | `…/rpm/fedora-44` (`…/rpm/bazzite`) |
| **Bazzite sysext** | `sudo rubyfunk-sysext install --channel canary` | `sudo rubyfunk-sysext install` |
| **pacman** | a `[rubyfunk-canary]` section in `/etc/pacman.conf` | `[rubyfunk]` |
| **Flatpak client** | `https://flatpak.unom.io/io.unom.punktfunk.canary.flatpakref` | `…/io.github.gunu3371.rubyfunk.flatpakref` |
| **NixOS** | flake input `git+https://git.unom.io/unom/punktfunk?ref=nix-canary`, built nightly | `?ref=nix-stable` |
| **Decky plugin** | `https://unom.io/pf-decky-canary` | `https://unom.io/pf-decky` |
| **SteamOS on-device build** | `~/rubyfunk` on the `main` branch | `~/rubyfunk` on the `stable` branch |
| **Windows host and client** | `canary/` in the download URL, e.g. `…/generic/rubyfunk-host-windows/canary/rubyfunk-host-setup.exe` | `latest/` in the URL, the releases page, or winget |
| **Android** | Google Play open testing, or `…/generic/rubyfunk-android/canary/rubyfunk-android.apk` | [Google Play](https://play.google.com/store/apps/details?id=io.unom.punktfunk), or `latest/` |
| **Apple** | TestFlight | [App Store](https://apps.apple.com/app/id6779991756) for iPhone, iPad and Apple TV; the `.dmg` on the releases page for the Mac |

The [releases page](https://git.unom.io/unom/punktfunk/releases) and winget carry stable only.

## Pin a version, or roll back

| How you installed | Pin or roll back |
|---|---|
| **apt** | `apt-cache madison rubyfunk-host` lists versions; `sudo apt install rubyfunk-host=<version>`. `sudo apt-mark hold rubyfunk-host` stays there, `apt-mark unhold` resumes. |
| **dnf** | `sudo dnf --showduplicates list rubyfunk` lists versions; `sudo dnf install rubyfunk-<version>` or `sudo dnf downgrade rubyfunk`. |
| **pacman** | `sudo pacman -U /var/cache/pacman/pkg/rubyfunk-host-<version>-x86_64.pkg.tar.zst`, then `IgnorePkg = rubyfunk-host` in `/etc/pacman.conf` so `-Syu` leaves it. |
| **Bazzite sysext** | `rubyfunk-sysext status` prints the feed URL; download `rubyfunk-<version>-x86-64.raw` from it and `sudo rubyfunk-sysext install --from-file rubyfunk-<version>-x86-64.raw`. |
| **Windows installer** | Run the older `rubyfunk-host-setup-<version>.exe` over the current install. |
| **winget** | `winget install gunu3371.RubyFunkHost --version <x.y.z>` |
| **Decky plugin** | Install from URL: `…/generic/rubyfunk-decky/<version>/rubyfunk.zip`. |
| **SteamOS on-device build** | `git -C ~/rubyfunk checkout v<x.y.z>`, then `bash ~/rubyfunk/scripts/steamdeck/update.sh`. Updates stop until you switch back to a branch. |
| **NixOS** | `sudo nixos-rebuild switch --rollback`, or pin the flake input to a `v<x.y.z>` tag and rebuild. |

Your config, console password and paired devices carry across in both directions.

## Switch an installed box between channels

On a Linux host the guided installer switches either way, and asks before it moves:

```sh
curl -fsSLO https://punktfunk.unom.io/install.sh
sh install.sh --channel canary    # or: --channel stable
```

Without `--channel` it stays on the box's current channel. By hand:

```sh
# apt
sudo sed -i 's/ stable main/ canary main/' /etc/apt/sources.list.d/rubyfunk.list
sudo apt update && sudo apt upgrade

# dnf (Fedora)
sudo sed -i 's#/rpm/fedora-44#/rpm/fedora-44-canary#' /etc/yum.repos.d/rubyfunk.repo
sudo dnf upgrade rubyfunk rubyfunk-web rubyfunk-scripting

# rpm-ostree layer (Bazzite / Fedora Atomic)
sudo sed -i 's#/rpm/bazzite#/rpm/bazzite-canary#' /etc/yum.repos.d/rubyfunk.repo   # or fedora-44
sudo /usr/share/rubyfunk/update-rubyfunk.sh

# pacman: rename the section, then -Sy and -S (-Syu never steps down)
sudo sed -i 's/^\[rubyfunk\]$/[rubyfunk-canary]/' /etc/pacman.conf
sudo pacman -Sy && sudo pacman -S rubyfunk-host rubyfunk-web rubyfunk-scripting

# Bazzite sysext
sudo rubyfunk-sysext install --channel canary

# SteamOS on-device build: follow main, then rebuild
git -C ~/rubyfunk fetch && git -C ~/rubyfunk switch main
bash ~/rubyfunk/scripts/steamdeck/update.sh --pull

# Flatpak client
flatpak install --user https://flatpak.unom.io/io.unom.punktfunk.canary.flatpakref

# NixOS: change ?ref=nix-stable to ?ref=nix-canary on the flake input, then
nix flake update rubyfunk && sudo nixos-rebuild switch
```

Back to stable is the same edit reversed, plus a step down the package manager allows:
`sudo apt install --allow-downgrades rubyfunk-host=<version>` (versions from `apt-cache madison`),
`sudo dnf distro-sync rubyfunk rubyfunk-web rubyfunk-scripting`, the same `pacman -S`,
`sudo rubyfunk-sysext install --channel stable`, or `switch stable` on a Steam Deck.

Cutting a release is on [Releasing](/docs/developers/releasing).
