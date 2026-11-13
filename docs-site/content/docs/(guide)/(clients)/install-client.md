---
title: Install a Client
description: Install, update and remove the RubyFunk app on the device you stream to — Linux, Steam Deck, Windows, macOS, iPhone, iPad, Apple TV or Android.
---

Install the RubyFunk app on the device you stream *to*, then [pair](/docs/pairing) it with your
host once. To pick between the apps, see [Clients](/docs/clients).

These links are the **stable** channel. For builds of `main`, see [Release Channels](/docs/channels).

## Pick your device

| Device | Install |
|--------|---------|
| Linux desktop or laptop | [Flatpak](#linux-desktop-flatpak), or the apt, dnf or pacman package |
| Steam Deck | [Decky plugin](/docs/steam-deck) for Gaming Mode, [Flatpak](#steam-deck) for Desktop Mode |
| Windows 10 or 11 (x64, Arm64) | [Installer](#windows) |
| Mac (macOS 14+) | [`.dmg`](#macos) |
| iPhone, iPad, Apple TV (17+) | [App Store](#ios-ipados-apple-tv) |
| Android 9+ phone or TV | [Google Play or APK](#android) |
| LG webOS TV | [Community client](#lg-webos-tv-community) |
| Samsung TV | [Samsung TV](/docs/samsung-tv) |
| Anything else | [Moonlight](/docs/moonlight) |

## Linux desktop (Flatpak)

Works on any distro with Flatpak:

```sh
flatpak install --user https://flatpak.unom.io/io.unom.punktfunk.flatpakref
flatpak run io.github.gunu3371.rubyfunk
```

Update with `flatpak update`, **without `sudo`**: `sudo` only updates system installs and skips this
one.

To use your package manager instead, add the RubyFunk repo from your distro's guide, then:

| Distro | Install |
|--------|---------|
| Ubuntu 26.04 or newer | `sudo apt install rubyfunk-client` ([packaging/debian](https://git.unom.io/unom/punktfunk/src/branch/main/packaging/debian/README.md)) |
| Fedora 43 or newer | `sudo dnf install rubyfunk-client` ([Fedora](/docs/fedora)) |
| Arch | `sudo pacman -Syu rubyfunk-client` ([Arch Linux](/docs/arch)) |
| Bazzite, Fedora Atomic | Use the Flatpak. Layering with `rpm-ostree install rubyfunk-client` slows every OS update ([Bazzite](/docs/bazzite)). |

On Ubuntu 24.04, Debian and older distros the client package can't install: use the Flatpak.

Open **RubyFunk** from your app menu, or **RubyFunk Console** for the controller interface. Every
package, the Flatpak included, also installs the [`rubyfunk` command](/docs/clients#scripting-the-rubyfunk-cli)
for scripts.

## Steam Deck

For Gaming Mode, install the [Decky plugin](/docs/steam-deck). It uses the Flatpak client, so
install that too, in Desktop Mode:

```sh
flatpak install --user https://flatpak.unom.io/io.unom.punktfunk.flatpakref
```

## Windows

1. Download the installer. In PowerShell:

   ```powershell
   curl.exe -LO https://git.unom.io/api/packages/unom/generic/punktfunk-client-windows/latest/punktfunk-client-setup_x64.exe
   ```

   On an Arm device, use `_arm64` in place of `_x64`. The file is also on every
   [release](https://git.unom.io/unom/punktfunk/releases).
2. Run it. No admin prompt: it installs to `%LOCALAPPDATA%\Programs\RubyFunk`, registers
   `rubyfunk://` links, puts `rubyfunk` on your PATH and fetches the Windows App Runtime if it's
   missing.
3. Open **RubyFunk** from the Start menu, or **RubyFunk Console** for the controller interface
   (x64 only: the Arm64 build has no console yet).

**Steam overlay and Big Picture.** In Steam, **Add a Non-Steam Game** and browse to
`%LOCALAPPDATA%\Programs\RubyFunk\rubyfunk-client.exe` (or `rubyfunk-console.exe`).

**Portable zip and MSIX.** The same build ships as
`…/latest/rubyfunk-client-windows_x64-portable.zip` (unzip and run `rubyfunk-client.exe`; no
links, no PATH entry) and `…/latest/rubyfunk-client-windows_x64.msix`
(`Add-AppxPackage .\rubyfunk-client-windows_x64.msix`). Both need the
[Windows App Runtime 2.x](https://learn.microsoft.com/windows/apps/windows-app-sdk/downloads). The
MSIX can't be added to Steam.

## macOS

1. Download `RubyFunk-<version>.dmg` from the [releases page](https://git.unom.io/unom/punktfunk/releases).
2. Open it and drag **RubyFunk** to **Applications**.

The Mac app is also in the [TestFlight beta](https://testflight.apple.com/join/Qr7uSemk).

## iOS, iPadOS, Apple TV

**[Get RubyFunk on the App Store](https://apps.apple.com/app/id6779991756)**. One app covers
iPhone, iPad and Apple TV.

For beta builds, install Apple's [TestFlight](https://apps.apple.com/app/testflight/id899247664)
app, then [join the RubyFunk beta](https://testflight.apple.com/join/Qr7uSemk).

## Android

**[Get RubyFunk on Google Play](https://play.google.com/store/apps/details?id=io.unom.punktfunk)**.
The same app runs on phones, tablets and Android TV.

To skip Play, install the signed APK:

```text
https://git.unom.io/api/packages/unom/generic/punktfunk-android/latest/punktfunk-android.apk
```

For canary builds, join the beta from the app's Play listing (open testing, anyone can join), or
use `canary` in place of `latest` in the APK link.

## LG webOS TV (community)

[`pf-webos`](https://github.com/dyptan-io/pf-webos) is built by
[dyptan-io](https://github.com/dyptan-io), not the RubyFunk team. Report its bugs on
[its repo](https://github.com/dyptan-io/pf-webos/issues).

1. Turn on Developer Mode on the TV and install the [Homebrew Channel](https://www.webosbrew.org/)
   ([guide](https://www.webosbrew.org/guide/getting-started.html)).
2. Download the latest `.ipk` from the
   [pf-webos releases](https://github.com/dyptan-io/pf-webos/releases/latest).
3. Install it with `ares-install`, or copy it to the TV and install it from the Homebrew Channel.
4. Open **RubyFunk** from the TV's launcher.

## Keeping a client up to date

A client and a host don't need the same version. To update the host, see [Updating](/docs/updating).

| Client | Update |
|---|---|
| Flatpak | `flatpak update`, without `sudo` |
| apt, dnf, pacman | Your normal system upgrade, or [`rubyfunk-client --apply-update`](#the-linux-client-can-update-itself) |
| Fedora Atomic, layered | See below |
| Windows installer | Run the newer installer. Hosts and pairing are kept. |
| Windows MSIX or portable | Add the newer `.msix`, or unzip the newer build over the old one. An MSIX named `gunu3371.RubyFunk` is the older package and doesn't upgrade: remove it as below first. |
| macOS `.dmg` | Drag the newer app over the old one |
| iPhone, iPad, Apple TV | App Store, or TestFlight for the beta |
| Android | Google Play. For the APK, install the newer one over it. |
| Steam Deck (Decky) | The panel's update button: [Steam Deck → Updating](/docs/steam-deck#updating) |
| LG webOS | Install the newer `.ipk` |

**Fedora Atomic with a layered client.** `rpm-ostree upgrade` doesn't pick up a newer client while
the base image is unchanged. Run this, then reboot:

```sh
sudo rpm-ostree refresh-md --force
sudo rpm-ostree update --uninstall rubyfunk-client --install rubyfunk-client
```

**Moving from the MSIX to the installer.** Remove the MSIX first, then run the installer. The MSIX
takes its saved hosts and pairing with it, so pair again once:

```powershell
Get-AppxPackage *io.github.gunu3371.rubyfunk | Remove-AppxPackage
```

### The Linux client can update itself

```sh
rubyfunk-client --check-update    # installed vs available on this box's channel
rubyfunk-client --apply-update    # install it
```

`--check-update` exits **0** when up to date, **10** when an update is available, and **1** when it
couldn't tell. Add `--json` for machine-readable output. `--apply-update` needs you in the
`rubyfunk-update` group (no re-login needed):

```sh
sudo usermod -aG rubyfunk-update $USER
```

A Flatpak client updates with `flatpak update` instead.

## Removing a client

See [Uninstalling → Clients](/docs/uninstall#clients): the command for each client, and what stays
behind on the device and the host.
