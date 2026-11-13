#!/usr/bin/env bash
# Build the rubyfunk-scripting .deb — the plugin/script runner (the SDK's `rubyfunk-scripting`,
# built on Effect, run on bun).
#
# Runtime is BUN: the runner `import()`s the operator's `.ts` plugin/script files directly, which
# only bun can do. Like the web console it runs on the vendored bun from rubyfunk-bun
# (build-bun-deb.sh), pinned to this exact version. Unlike the console it is NOT a Nitro
# bundle: we `bun build` the runner CLI into ONE self-contained JS (effect + the SDK inlined; the
# dynamic plugin import stays a runtime import), so there is no node_modules to ship. The host's
# rubyfunk-host .deb Recommends this so a default `apt install rubyfunk-host` pulls the runner too;
# its systemd --user unit is installed but NOT auto-enabled (the runner is inert until you add
# scripts/plugins — enable it with `systemctl --user enable --now rubyfunk-scripting`).
#
# Usage: VERSION=0.0.1~ci42.gdeadbee [DEB_ARCH=amd64] bash packaging/debian/build-scripting-deb.sh
# Output: dist/rubyfunk-scripting_<version>_<arch>.deb
set -euo pipefail

VERSION="${VERSION:?set VERSION (e.g. 0.0.1 or 0.0.1~ci42.gdeadbee)}"
PKG="rubyfunk-scripting"
ROOTDIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOTDIR"

# Per-arch, like the rubyfunk-bun it depends on.
DEB_ARCH="${DEB_ARCH:-$(dpkg --print-architecture)}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
SHAREDIR="$STAGE/usr/share/$PKG"
DOCDIR="$STAGE/usr/share/doc/$PKG"

# --- build the runner bundle -------------------------------------------------
# One self-contained JS: `bun build --target=bun` inlines effect + the @rubyfunk/host SDK; the
# runner's dynamic `import()` of the operator's plugin files is left as a runtime import (bun keeps
# unresolvable dynamic specifiers external). `--ignore-scripts` on install: nothing needs a
# postinstall, and we skip the `prepare` codegen (it wants ../api/openapi.json — not needed here).
mkdir -p "$SHAREDIR"
(
  cd sdk
  bun install --frozen-lockfile --ignore-scripts
  bun build src/runner-cli.ts --target=bun --outfile="$SHAREDIR/runner-cli.js"
)
grep -q 'attempt=' "$SHAREDIR/runner-cli.js" \
  || { echo "ERROR: runner bundle missing the dynamic plugin import — wrong build" >&2; exit 1; }

# --- file layout -------------------------------------------------------------
# Stable PATH-independent launcher (the systemd unit's ExecStart) — runs the bundle on vendored bun.
install -d "$STAGE/usr/bin"
cat > "$STAGE/usr/bin/rubyfunk-scripting" <<'WRAP'
#!/bin/sh
# The runner runs on rubyfunk-bun's private bun (it import()s the operator's .ts plugins).
exec /usr/lib/rubyfunk-bun/bun /usr/share/rubyfunk-scripting/runner-cli.js "$@"
WRAP
chmod 0755 "$STAGE/usr/bin/rubyfunk-scripting"
install -Dm0644 scripts/rubyfunk-scripting.service "$STAGE/usr/lib/systemd/user/rubyfunk-scripting.service"
# Where AppArmor restricts unprivileged user namespaces, the generator trades the unit's namespace
# sandbox for this profile.
install -Dm0644 packaging/linux/apparmor/rubyfunk-scripting "$STAGE/etc/apparmor.d/rubyfunk-scripting"
install -Dm0755 packaging/linux/rubyfunk-scripting-apparmor.generator \
  "$STAGE/usr/lib/systemd/user-generators/rubyfunk-scripting-apparmor"
install -Dm0644 LICENSE-MIT    "$DOCDIR/LICENSE-MIT"
install -Dm0644 LICENSE-APACHE "$DOCDIR/LICENSE-APACHE"
install -Dm0644 sdk/README.md  "$DOCDIR/README.md"

cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: rubyfunk
Source: https://github.com/gunu3371/RubyFunk

Files: *
Copyright: rubyfunk contributors
License: MIT or Apache-2.0
 Dual-licensed. Full texts in /usr/share/doc/$PKG/LICENSE-MIT and
 /usr/share/doc/$PKG/LICENSE-APACHE.
EOF
printf '%s (%s) stable; urgency=medium\n\n  * Automated build %s.\n\n -- unom <packages@unom.io>  %s\n' \
  "$PKG" "$VERSION" "$VERSION" "$(date -uR 2>/dev/null || echo 'Thu, 01 Jan 1970 00:00:00 +0000')" \
  | gzip -9n > "$DOCDIR/changelog.Debian.gz"

INSTALLED_KB="$(du -k -s "$STAGE" | cut -f1)"

install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: unom <packages@unom.io>
Installed-Size: $INSTALLED_KB
Section: net
Priority: optional
Depends: bubblewrap, rubyfunk-bun (= $VERSION)
Homepage: https://github.com/gunu3371/RubyFunk
Description: rubyfunk plugin/script runner (Effect SDK on bun)
 Runs a rubyfunk host's automation: loose scripts in ~/.config/rubyfunk/scripts and installed
 rubyfunk-plugin-* packages under ~/.config/rubyfunk/plugins, each supervised (Effect fibers with
 capped-jittered restart; SIGTERM shuts the whole tree down structurally so plugin finalizers run).
 Runs on the bun from rubyfunk-bun (no system nodejs/bun dependency).
 .
 ON BY DEFAULT: the systemd --user unit is enabled for every user (systemctl --global). The runner is
 inert until you add scripts or plugins, and the game-library scanners now ship AS plugins — so a
 host without the runner has an empty library and no obvious reason why. A plugin auto-wires to the
 host's mgmt token + identity cert on the same box — no env editing.
 Opt out per user with: systemctl --user mask rubyfunk-scripting
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    # `--global`, not `--user`: a maintainer script has no user session to act on, and this is the
    # only mechanism that makes a `--user` unit on-by-default for everyone (it symlinks into
    # /etc/systemd/user/…wants/). The library's scanners are plugins now, so the runner is a default
    # component rather than an add-on (design D9) — but installing it stays opt-OUT, and the opt-out
    # is `systemctl --user mask rubyfunk-scripting`, since a plain `--user disable` cannot remove a
    # global symlink.
    #
    # Only on FIRST configure ($2 empty): re-running it on every upgrade would silently undo the
    # mask of anyone who turned it off.
    if [ -z "$2" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl --global enable rubyfunk-scripting.service >/dev/null 2>&1 || true
    fi
    # Boot loads it from /etc/apparmor.d; this covers the running kernel.
    if command -v apparmor_parser >/dev/null 2>&1 && aa-enabled --quiet 2>/dev/null; then
        apparmor_parser -r -T -W /etc/apparmor.d/rubyfunk-scripting || true
    fi
    echo "rubyfunk-scripting installed and enabled for all users."
    echo "It runs your automation — game-library sources, scripts in"
    echo "    ~/.config/rubyfunk/scripts/  (loose .ts/.js files)"
    echo "and plugins under ~/.config/rubyfunk/plugins/."
    echo "It starts with your next login; start it now with:"
    echo "    systemctl --user start rubyfunk-scripting"
    echo "Don't want it? systemctl --user mask rubyfunk-scripting"
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"
echo /etc/apparmor.d/rubyfunk-scripting > "$STAGE/DEBIAN/conffiles"

mkdir -p dist
OUT="dist/${PKG}_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT" >/dev/null
echo "built $OUT"
dpkg-deb -I "$OUT" | sed -n 's/^/  /p' | grep -E 'Version|Installed-Size|Depends' || true
