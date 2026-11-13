---
title: Updating the Host
description: See when a newer host is out, update it from the web console or with one command, and turn the check off.
---

The web console tells you when a newer host is out, and on most installs updates it for you.

## The Updates card

The top of **Host** in the [web console](/docs/web-console) shows the version you run and whether
it is current; **Check for update** checks right away. Once a newer release exists, the Updates
card unfolds below it with the channel you follow, how the host was installed, and either an
**Update now** button or the command that updates this install. The host checks a signed feed on
`git.unom.io` while the console is open. The host also fires `update.available`
and `update.applied` on the [event stream](/docs/automation).

The channel comes from the repository you installed from (on a Steam Deck, the branch
`~/rubyfunk` follows), and the card never switches it — see [Release Channels](/docs/channels).

## Update now

| Install | Button |
|---|---|
| Windows installer | Always. |
| apt, dnf, Bazzite sysext, rpm-ostree layer | After a one-time opt-in: `sudo usermod -aG rubyfunk-update $USER`, then restart the computer. The host keeps the groups it started with, so logging out is not enough. rpm-ostree stages the update: reboot to finish. |
| Arch (pacman) | The same opt-in, plus `PACMAN_FULL_SYSUPGRADE=1` in `/etc/rubyfunk/update.conf`: the button runs a full `pacman -Syu`. |
| Steam Deck on-device build | Always, except while Reachable without logging in is on: then run `update.sh --pull` in Konsole. It rebuilds on the Deck, which takes a while; the log is `~/.config/rubyfunk/logs/update-steamos.log`. |
| Omarchy, NixOS, source builds | Command only. |

The button asks for the console password and warns you if a stream is live, because updating drops
it. The host restarts at the end and the page reconnects by itself. On Linux the button runs your
package manager against its own signed repositories; it never picks a version.

On Windows every attempt writes `C:\ProgramData\rubyfunk\logs\update-<version>.log` (open it from
an elevated PowerShell). If the new host crash-loops, the service reinstalls the previous version,
says so in the card and writes `update-rollback-from-<version>.log`.

## Update by hand

| How you installed | Command |
|---|---|
| Windows installer | Run the newer `rubyfunk-host-setup-<version>.exe` from the [releases page](https://git.unom.io/unom/punktfunk/releases), or `winget upgrade gunu3371.RubyFunkHost` ([winget source](/docs/windows-host#winget), stable only) |
| Ubuntu (apt) | `sudo apt update && sudo apt install --only-upgrade $(dpkg-query -W -f='${Package}\n' 'rubyfunk*')` |
| Fedora (dnf) | `sudo dnf upgrade 'rubyfunk*'` |
| Bazzite sysext | `sudo rubyfunk-sysext update` |
| Bazzite / Fedora Atomic, layered RPMs | `sudo /usr/share/rubyfunk/update-rubyfunk.sh`, then reboot |
| Arch / CachyOS (pacman) | `sudo pacman -Syu` |
| Omarchy | `omarchy update` |
| Steam Deck on-device build | `bash ~/rubyfunk/scripts/steamdeck/update.sh --pull` |
| NixOS (flake) | `nix flake update rubyfunk` in your flake directory, then rebuild |

On a layered install, `rpm-ostree upgrade` alone reports no updates while the base image stands
still; the script re-resolves just the RubyFunk packages. It takes the newest version from every
enabled `/etc/yum.repos.d/rubyfunk*.repo`, so enable only your channel's repo. If the box also runs
the sysext, the sysext wins: update that instead.

### Restart after a Linux package update

Every update restarts the running console, host and plugin runner for each signed-in user: pacman,
apt, dnf, a NixOS switch, **Update now**, the Windows installer, `rubyfunk-sysext update` and the
Steam Deck script. A service you stopped stays stopped. A live stream drops when the host restarts.
A layered rpm-ostree install moves at the reboot instead.

The apt and dnf commands above update only the host; name `rubyfunk-web` and `rubyfunk-scripting`
too to move all three. A source build restarts by hand, console first:

```bash
systemctl --user restart rubyfunk-web
systemctl --user restart rubyfunk-host
systemctl --user try-restart rubyfunk-scripting
```

A host left running on a replaced binary fails every new KDE desktop session with
`KWin does not expose zkde_screencast_unstable_v1 to this client` until it restarts.

### Bazzite sysext: channels, rollback and rebases

- `rubyfunk-sysext status` shows the channel, the installed and the newest version.
- Switch channel: `sudo rubyfunk-sysext install --channel canary` (or `stable`).
- Keep a build to go back to:

  ```sh
  sudo cp /var/lib/extensions/rubyfunk.raw ~/rubyfunk-known-good.raw   # before updating
  sudo rubyfunk-sysext install --from-file ~/rubyfunk-known-good.raw   # to go back
  ```

- After a Bazzite major rebase the old image refuses to load. A unit the install left in `/etc`
  fetches the image for the new base once the network is up, so the host is back a minute or two
  after the first boot. A host last updated before 0.47.0 has no such unit yet: download the
  script again and update once:

  ```sh
  curl -fsSLO https://git.unom.io/unom/punktfunk/raw/branch/main/packaging/bazzite/punktfunk-sysext.sh
  sudo bash rubyfunk-sysext.sh update
  ```

- `refusing to downgrade`: the feed's newest image is older than yours. Roll back on purpose with
  `sudo RUBYFUNK_SYSEXT_ALLOW_DOWNGRADE=1 rubyfunk-sysext update`, or the file you kept.
- The script checks the feed's signature with `gpg`. If it reports a bad signature, a foreign feed
  or an older serial, don't install: download the script again and retry.

## Turn the check off

Turn off **Check for updates** under **Host → System** (`RUBYFUNK_UPDATE_CHECK=0` in
`host.env`). To keep the check but drop the button, turn off **Console updates** under
**Show advanced** (`RUBYFUNK_UPDATE_APPLY=0`). The check contacts `git.unom.io`, which hands the file over to Cloudflare R2.

## Troubleshooting

### The update feed hasn't changed in over 45 days

Checks work, but nothing new arrived. Usually there was no release. If the
[releases page](https://git.unom.io/unom/punktfunk/releases) lists a newer stable version than the
card, a proxy or DNS between the host and `git.unom.io` serves old data. The releases page is
stable-only, so on a canary host the comparison means nothing.

Anything else: [Troubleshooting](/docs/troubleshooting). Clients update on their own —
[Install a Client → Keeping a client up to date](/docs/install-client#keeping-a-client-up-to-date).
